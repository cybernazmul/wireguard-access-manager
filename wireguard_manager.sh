#!/bin/bash

# WireGuard ProPlusDeploy Final
# Full Management System: Client Names, Auto IP, Safe IPTables, Clean Deletion

set -e

BASE_DIR="$HOME/.wireguard"
CONFIG_DIR="${BASE_DIR}/configs"
IPTABLES_DIR="${BASE_DIR}/iptables"
QRCODES_DIR="${BASE_DIR}/qrcodes"
ZIP_FILE="${BASE_DIR}/clients.zip"
DEFAULT_BACKUP_DIR="${HOME}/wg-backup"

SERVER_PORT=51820
SERVER_VPN_IP="172.16.0.1/24"
WG_INTERFACE="wg0"

mkdir -p "${CONFIG_DIR}" "${IPTABLES_DIR}" "${QRCODES_DIR}"

find_next_ip() {
  USED_IPS=($(grep "Address =" ${CONFIG_DIR}/wg0c-*.conf 2>/dev/null | awk '{print $3}' | cut -d'/' -f1 | awk -F. '{print $4}' | sort -n))
  NEXT_IP=2
  for ip in "${USED_IPS[@]}"; do
    if (( NEXT_IP == ip )); then
      ((NEXT_IP++))
    fi
  done
}

generate_iptables_for_client() {
  local client_ip="$1"
  local allowed_blocks="$2"
  local iptables_script="$3"

  echo "#!/bin/bash" > "${iptables_script}"
  echo "# IPTables rules for ${client_ip}" >> "${iptables_script}"
  echo "" >> "${iptables_script}"

  cat <<EOF >> "${iptables_script}"
while iptables -C FORWARD -i ${WG_INTERFACE} -s ${client_ip} -j ACCEPT 2>/dev/null; do
  iptables -D FORWARD -i ${WG_INTERFACE} -s ${client_ip} -j ACCEPT
done

while iptables -C FORWARD -i ${WG_INTERFACE} -s ${client_ip} -j DROP 2>/dev/null; do
  iptables -D FORWARD -i ${WG_INTERFACE} -s ${client_ip} -j DROP
done
EOF

  for block in $(echo "${allowed_blocks}" | tr ',' ' '); do
    echo "iptables -A FORWARD -i ${WG_INTERFACE} -s ${client_ip} -d ${block} -j ACCEPT" >> "${iptables_script}"
  done

  echo "iptables -A FORWARD -i ${WG_INTERFACE} -s ${client_ip} -j DROP" >> "${iptables_script}"

  chmod +x "${iptables_script}"
}

rebuild_zip() {
  cd "${BASE_DIR}"
  zip -q -r clients.zip configs qrcodes
  cd -
}

restart_wireguard() {
  echo "🚀 Copying wg0.conf to /etc/wireguard/"
  sudo mkdir -p /etc/wireguard
  sudo cp "${CONFIG_DIR}/wg0.conf" /etc/wireguard/wg0.conf
  sudo chmod 600 /etc/wireguard/wg0.conf

  echo "🔄 Restarting WireGuard wg0..."
  sudo wg-quick down wg0 2>/dev/null || true
  sudo wg-quick up wg0
  echo "✅ WireGuard restarted."
  apply_all_iptables
}

create_new_client() {
  echo "📜 Existing Clients:"
  ls ${CONFIG_DIR}/wg0c-*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||'

  read -p "👉 Enter a short client name (no spaces): " CLIENT_NAME
  CLIENT_NAME=$(echo "$CLIENT_NAME" | tr ' ' '_' | tr 'A-Z' 'a-z')
  CLIENT_FILENAME="wg0c-${CLIENT_NAME}.conf"
  CLIENT_FULL_PATH="${CONFIG_DIR}/${CLIENT_FILENAME}"

  # Check if client already exists
  if [ -f "${CLIENT_FULL_PATH}" ]; then
    echo "❌ Client '${CLIENT_NAME}' already exists!"
    echo "⚠️ Aborting creation to avoid overwriting."
    return
  fi

  #read -p "👉 Enter a short client name (no spaces): " CLIENT_NAME
  CLIENT_NAME=$(echo "$CLIENT_NAME" | tr ' ' '_' | tr 'A-Z' 'a-z')
  CLIENT_FILENAME="wg0c-${CLIENT_NAME}.conf"

  read -p "👉 Enter your Server Public IP: " SERVER_PUBLIC_IP
  read -p "👉 Enter DNS server for client (default 8.8.8.8): " CLIENT_DNS
  CLIENT_DNS=${CLIENT_DNS:-8.8.8.8}

  if [ ! -f "${CONFIG_DIR}/wg0.conf" ]; then
    echo "🔵 Creating server config wg0.conf..."
    SERVER_PRIVATE_KEY=$(wg genkey)
    SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

    cat <<EOF > "${CONFIG_DIR}/wg0.conf"
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${SERVER_VPN_IP}
ListenPort = ${SERVER_PORT}

PostUp = sysctl -w net.ipv4.ip_forward=1
PostDown = sysctl -w net.ipv4.ip_forward=0
EOF
  else
    SERVER_PRIVATE_KEY=$(grep -m1 "PrivateKey" "${CONFIG_DIR}/wg0.conf" | awk '{print $3}')
    SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
  fi

  find_next_ip
  CLIENT_IP="172.16.0.${NEXT_IP}/32"

  read -p "👉 Enter destination CIDR blocks (comma separated): " ALLOWED_BLOCKS
  ALLOWED_BLOCKS_CLEAN=$(echo "$ALLOWED_BLOCKS" | tr -d ' ')

  CLIENT_PRIVATE_KEY=$(wg genkey)
  CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

  cat <<EOF > "${CONFIG_DIR}/${CLIENT_FILENAME}"
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_PUBLIC_IP}:${SERVER_PORT}
AllowedIPs = ${ALLOWED_BLOCKS_CLEAN}
PersistentKeepalive = 25
EOF

  cat <<EOF >> "${CONFIG_DIR}/wg0.conf"

# Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}
EOF

  generate_iptables_for_client "${CLIENT_IP}" "${ALLOWED_BLOCKS_CLEAN}" "${IPTABLES_DIR}/iptables_wg0c-${CLIENT_NAME}.sh"

  if command -v qrencode >/dev/null 2>&1; then
    qrencode -o "${QRCODES_DIR}/wg0c-${CLIENT_NAME}.png" < "${CONFIG_DIR}/${CLIENT_FILENAME}"
    echo "📸 QR code generated for Client ${CLIENT_NAME}"
  fi

  rebuild_zip
  restart_wireguard
}

modify_existing_client() {
  echo "📜 Existing Clients:"
  ls ${CONFIG_DIR}/wg0c-*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||'

  read -p "👉 Enter Client Name to modify AllowedIPs (e.g., marketing): " CLIENT_NAME
  CLIENT_CONF="${CONFIG_DIR}/wg0c-${CLIENT_NAME}.conf"

  if [ ! -f "${CLIENT_CONF}" ]; then
    echo "❌ Client '${CLIENT_NAME}' not found!"
    return
  fi

  # Load current AllowedIPs
  CURRENT_ALLOWED=$(grep "AllowedIPs =" "${CLIENT_CONF}" | awk -F'= ' '{print $2}')

  # Convert to array
  IFS=',' read -r -a ALLOWED_IP_ARRAY <<< "$CURRENT_ALLOWED"

  while true; do
    echo ""
    echo "🎯 Modify Allowed IPs for Client '${CLIENT_NAME}'"
    echo "========================================================="
    echo "Current Allowed IPs:"
    for idx in "${!ALLOWED_IP_ARRAY[@]}"; do
      echo "[$idx] ${ALLOWED_IP_ARRAY[$idx]}"
    done
    echo "========================================================="
    echo "1️⃣  Add New IP Block"
    echo "2️⃣  Remove Existing IP Block"
    echo "3️⃣  Save and Exit"
    echo "4️⃣  Cancel and Exit without Saving"
    echo "========================================================="
    read -p "👉 Select an option (1-4): " action

    case $action in
      1)
        read -p "➕ Enter new IP Block to add (e.g., 10.50.0.0/24): " NEW_BLOCK
        ALLOWED_IP_ARRAY+=("$NEW_BLOCK")
        echo "✅ Added $NEW_BLOCK."
        ;;
      2)
        read -p "➖ Enter index number to remove: " REMOVE_IDX
        if [[ "$REMOVE_IDX" =~ ^[0-9]+$ ]] && [ "$REMOVE_IDX" -ge 0 ] && [ "$REMOVE_IDX" -lt "${#ALLOWED_IP_ARRAY[@]}" ]; then
          echo "❌ Removing ${ALLOWED_IP_ARRAY[$REMOVE_IDX]}"
          unset 'ALLOWED_IP_ARRAY[REMOVE_IDX]'
          ALLOWED_IP_ARRAY=("${ALLOWED_IP_ARRAY[@]}")  # Repack array
        else
          echo "⚠️ Invalid index."
        fi
        ;;
      3)
        # Merge and save
        FINAL_ALLOWED=$(IFS=, ; echo "${ALLOWED_IP_ARRAY[*]}")
        sed -i "s|AllowedIPs = .*|AllowedIPs = ${FINAL_ALLOWED}|" "${CLIENT_CONF}"

        # Get client IP
        CLIENT_IP=$(grep "Address =" "${CLIENT_CONF}" | awk '{print $3}')

        # Re-generate iptables
        IPTABLES_SCRIPT="${IPTABLES_DIR}/iptables_wg0c-${CLIENT_NAME}.sh"

        echo "#!/bin/bash" > "${IPTABLES_SCRIPT}"
        echo "# IPTables rules for ${CLIENT_IP}" >> "${IPTABLES_SCRIPT}"
        echo "" >> "${IPTABLES_SCRIPT}"

        cat <<EOF >> "${IPTABLES_SCRIPT}"
# Flush old rules
while iptables -C FORWARD -i ${WG_INTERFACE} -s ${CLIENT_IP} -j ACCEPT 2>/dev/null; do
  iptables -D FORWARD -i ${WG_INTERFACE} -s ${CLIENT_IP} -j ACCEPT
done

while iptables -C FORWARD -i ${WG_INTERFACE} -s ${CLIENT_IP} -j DROP 2>/dev/null; do
  iptables -D FORWARD -i ${WG_INTERFACE} -s ${CLIENT_IP} -j DROP
done
EOF

        for block in "${ALLOWED_IP_ARRAY[@]}"; do
          echo "iptables -A FORWARD -i ${WG_INTERFACE} -s ${CLIENT_IP} -d ${block} -j ACCEPT" >> "${IPTABLES_SCRIPT}"
        done

        echo "iptables -A FORWARD -i ${WG_INTERFACE} -s ${CLIENT_IP} -j DROP" >> "${IPTABLES_SCRIPT}"

        chmod +x "${IPTABLES_SCRIPT}"

        # Regenerate QR code
        if command -v qrencode >/dev/null 2>&1; then
          qrencode -o "${QRCODES_DIR}/wg0c-${CLIENT_NAME}.png" < "${CLIENT_CONF}"
        fi

        rebuild_zip
        restart_wireguard

        echo "✅ AllowedIPs updated, iptables refreshed, QR regenerated for client ${CLIENT_NAME}."
        break
        ;;
      4)
        echo "❌ Cancelled. No changes saved."
        break
        ;;
      *)
        echo "⚠️ Invalid selection."
        ;;
    esac
  done
}



delete_client() {
  echo "📜 Existing Clients:"
  ls ${CONFIG_DIR}/wg0c-*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||'
  read -p "👉 Enter Client Name to delete: " CLIENT_NAME
  CLIENT_CONF="${CONFIG_DIR}/wg0c-${CLIENT_NAME}.conf"
  CLIENT_IPTABLES="${IPTABLES_DIR}/iptables_wg0c-${CLIENT_NAME}.sh"
  CLIENT_QR="${QRCODES_DIR}/wg0c-${CLIENT_NAME}.png"

  if [ ! -f "${CLIENT_CONF}" ]; then
    echo "❌ Client not found."
    return
  fi

  read -p "❓ Are you sure you want to delete ${CLIENT_NAME}? (y/n): " CONFIRM
  if [[ "$CONFIRM" != "y" ]]; then
    echo "❌ Aborted."
    return
  fi

  # Correct: Only delete this client's Peer block
  if grep -q "# Client ${CLIENT_NAME}" "${CONFIG_DIR}/wg0.conf"; then
    sudo sed -i "/# Client ${CLIENT_NAME}/,/^$/d" "${CONFIG_DIR}/wg0.conf"
    echo "✅ Peer block for ${CLIENT_NAME} removed from wg0.conf."
  else
    echo "⚠️ No Peer block found for ${CLIENT_NAME}."
  fi

  rm -f "${CLIENT_CONF}" "${CLIENT_IPTABLES}" "${CLIENT_QR}"
  rebuild_zip
  restart_wireguard
  echo "✅ Client ${CLIENT_NAME} deleted and WireGuard restarted."
}


apply_all_iptables() {
  echo "🧹 Flushing old FORWARD rules for wg0..."
  sudo iptables -F
  sudo iptables -X
  sudo iptables -Z
  sudo iptables-save | grep "\-A FORWARD -i ${WG_INTERFACE}" | while read -r rule; do
    sudo iptables -D FORWARD $(echo $rule | sed -e "s/-A FORWARD //")
  done
  echo "✅ Old wg0 FORWARD rules flushed."

  echo "🔒 Applying fresh IPTables rules..."
  for rule_script in ${IPTABLES_DIR}/iptables_wg0c-*.sh; do
    if [[ -f "$rule_script" ]]; then
      sudo bash "$rule_script"
      echo "✅ Applied: $rule_script"
    fi
  done
}

view_qr_code() {
  echo "📜 Existing Clients:"
  ls ${CONFIG_DIR}/wg0c-*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||'
  read -p "👉 Enter Client Name to view QR: " CLIENT_NAME
  CLIENT_CONF="${CONFIG_DIR}/wg0c-${CLIENT_NAME}.conf"

  if [ ! -f "${CLIENT_CONF}" ]; then
    echo "❌ Client not found."
    return
  fi

  qrencode -t ansiutf8 < "${CLIENT_CONF}"
}

show_iptables_for_client() {
  echo "📜 Existing Clients:"
  ls ${CONFIG_DIR}/wg0c-*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||'
  read -p "👉 Enter Client Name to view IPTables rules: " CLIENT_NAME
  CLIENT_CONF="${CONFIG_DIR}/wg0c-${CLIENT_NAME}.conf"

  if [ ! -f "${CLIENT_CONF}" ]; then
    echo "❌ Client not found."
    return
  fi

  CLIENT_IP=$(grep "Address =" "${CLIENT_CONF}" | awk '{print $3}' | cut -d'/' -f1)

  echo "🔍 Showing IPTables rules for Client ${CLIENT_NAME} (IP: ${CLIENT_IP})"
  sudo iptables -L FORWARD -n --line-numbers | grep "${CLIENT_IP}" || echo "❗ No IPTables rules found for this client."
}

list_clients_with_peering_ip() {
  echo ""
  echo "📋 Existing Clients and Peering IP Addresses"
  echo "============================================"
  printf "%-20s | %-20s\n" "Client Name" "Assigned IP"
  echo "--------------------------------------------"

  for file in ${CONFIG_DIR}/wg0c-*.conf; do
    if [ -f "$file" ]; then
      CLIENT_NAME=$(basename "$file" | sed 's/wg0c-//;s/.conf//')
      CLIENT_IP=$(grep "Address =" "$file" | awk '{print $3}')
      printf "%-20s | %-20s\n" "$CLIENT_NAME" "$CLIENT_IP"
    fi
  done

  echo "============================================"
}

view_connected_clients() {
  echo "🔍 Showing Connected Clients on ${WG_INTERFACE}"
  echo "==============================================="
  sudo wg show ${WG_INTERFACE}
  echo "==============================================="
}


view_client_config() {
  echo "📜 Existing Clients:"
  ls ${CONFIG_DIR}/wg0c-*.conf 2>/dev/null | sed 's|.*/||;s|\.conf||'

  read -p "👉 Enter Client Name to view config (e.g., marketing): " CLIENT_NAME
  CLIENT_CONF="${CONFIG_DIR}/wg0c-${CLIENT_NAME}.conf"

  if [ ! -f "${CLIENT_CONF}" ]; then
    echo "❌ Client '${CLIENT_NAME}' not found!"
    return
  fi

  echo ""
  echo "📋 Showing Configuration for Client: ${CLIENT_NAME}"
  echo "==============================================="
  cat "${CLIENT_CONF}"
  echo "==============================================="
}

# Backup all configs

backup_all_configs() {
  echo "📦 Default Backup Directory: ${DEFAULT_BACKUP_DIR}"
  read -p "👉 Enter Backup Directory path [ENTER for default]: " BACKUP_DIR
  BACKUP_DIR=${BACKUP_DIR:-$DEFAULT_BACKUP_DIR}

  # Ensure backup directory exists (auto-create if needed)
  if [ ! -d "${BACKUP_DIR}" ]; then
    echo "📂 Backup directory does not exist. Creating: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
    echo "✅ Backup directory created."
  fi

  # Check if Base Directory exists
  if [ ! -d "${BASE_DIR}" ]; then
    echo "❌ Base WireGuard directory (${BASE_DIR}) does not exist!"
    echo "⚠️ Cannot perform backup."
    return
  fi

  # Generate timestamp
  TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
  BACKUP_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.zip"

  # Backup by zipping RELATIVE folders inside .wireguard_manager
  echo "📦 Creating backup ZIP..."

  cd "${BASE_DIR}" || { echo "❌ Failed to access ${BASE_DIR}"; return; }
  zip -r "${BACKUP_FILE}" configs/ iptables/ qrcodes/ > /dev/null 2>&1
  cd -

  echo "✅ Backup created at: ${BACKUP_FILE}"
}

list_backups() {
  BACKUP_DIR="${HOME}/wg-backup"

  if [ ! -d "${BACKUP_DIR}" ]; then
    echo "❌ No backup directory found at ${BACKUP_DIR}."
    return
  fi

  BACKUP_FILES=($(ls -1t "${BACKUP_DIR}"/backup_*.zip 2>/dev/null))

  if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
    echo "❌ No backups found in ${BACKUP_DIR}."
    return
  fi

  echo ""
  echo "🗂 Available Backups:"
  echo "=============================================================="
  printf "%-40s %-20s %-10s\n" "Backup File" "Modified Time" "Size"
  echo "--------------------------------------------------------------"

  for backup in "${BACKUP_FILES[@]}"; do
    filename=$(basename "${backup}")
    mod_time=$(date -r "${backup}" +"%Y-%m-%d %H:%M:%S")
    size=$(du -h "${backup}" | awk '{print $1}')
    printf "%-40s %-20s %-10s\n" "${filename}" "${mod_time}" "${size}"
  done
  echo "=============================================================="
}

restore_backup() {
  BACKUP_DIR="${HOME}/wg-backup"
  BASE_DIR="$HOME/.wireguard_manager"

  if [ ! -d "${BACKUP_DIR}" ]; then
    echo "❌ No backup directory found at ${BACKUP_DIR}."
    return
  fi

  BACKUP_FILES=($(ls -1t "${BACKUP_DIR}"/backup_*.zip 2>/dev/null))

  if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
    echo "❌ No backups available to restore."
    return
  fi

  echo ""
  echo "🗂 Available Backups to Restore:"
  echo "=============================================="
  for idx in "${!BACKUP_FILES[@]}"; do
    filename=$(basename "${BACKUP_FILES[$idx]}")
    echo "[$idx] ${filename}"
  done
  echo "=============================================="

  read -p "👉 Enter the index number of backup to restore: " restore_idx

  if [[ "$restore_idx" =~ ^[0-9]+$ ]] && [ "$restore_idx" -ge 0 ] && [ "$restore_idx" -lt "${#BACKUP_FILES[@]}" ]; then
    SELECTED_BACKUP="${BACKUP_FILES[$restore_idx]}"
    echo "⚡ Restoring ${SELECTED_BACKUP}..."

    # Extract backup into BASE_DIR
    unzip -o "${SELECTED_BACKUP}" -d "${BASE_DIR}" > /dev/null 2>&1

    echo "✅ Backup restored successfully into ${BASE_DIR}."
    rebuild_zip
    restart_wireguard
    echo "✅ WireGuard reloaded with restored configs."
  else
    echo "❌ Invalid index selected. Aborting restore."
  fi
}

user_manager() {
  while true; do
    echo ""
    echo "👤 User Manager"
    echo "=============================================="
    echo "1️⃣  Create User "
    echo "2️⃣  Edit User"
    echo "3️⃣  View User Config"
    echo "4️⃣  View User QR Code"
    echo "5️⃣  User Peering IPs"
    echo "6️⃣  Show Allowed IPs"
    echo "7️⃣  Delete User"
    echo "8️⃣  Exit"
    echo "=============================================="
    read -p "👉 Select an option (1-8): " user_choice

    case $user_choice in
      1) create_new_client  ;;
      2) modify_existing_client ;;
      3) view_client_config ;;
      4) view_qr_code ;;
      5) list_clients_with_peering_ip ;;
      6) show_iptables_for_client ;;
      7) delete_client ;;
      8) echo "👋 Exiting User Manager..."; break ;;
      *) echo "❌ Invalid selection." ;;
    esac
  done
}



backup_manager() {
  while true; do
    echo ""
    echo "🛡️ Backup Manager"
    echo "=============================================="
    echo "1️⃣  Create Backup"
    echo "2️⃣  List Backups"
    echo "3️⃣  Restore Backup"
    echo "4️⃣  Exit"
    echo "=============================================="
    read -p "👉 Select an option (1-4): " backup_choice

    case $backup_choice in
      1) backup_all_configs ;;
      2) list_backups ;;
      3) restore_backup ;;
      4) echo "👋 Exiting Backup Manager..."; break ;;
      *) echo "❌ Invalid selection." ;;
    esac
  done
}
# Main Menu


while true; do
  echo ""
  echo "🛠 WireGuard ProPlusDeploy Manager"
  echo "=============================================="
  echo "1️⃣  User Manager"
  echo "2️⃣  Connected Users"
  echo "3️⃣  Reload WireGuard"
  echo "4️⃣  Reload Iptables"
  echo "5️⃣  View User Config"
  echo "6️⃣  List User IP"
  echo "7️⃣  Backup Manager"
  echo "0️⃣  Exit"
  echo "=============================================="
  read -p "👉 Select option (1-9): " choice

  case $choice in
    1) user_manager ;;
    2) view_connected_clients ;;
    3) restart_wireguard ;;
    4) apply_all_iptables ;;
    5) view_client_config ;;
    6) list_clients_with_peering_ip ;;
    7) backup_manager ;; 
    0) echo "👋 Goodbye!"; exit 0 ;;
    *) echo "❌ Invalid selection." ;;
  esac
done

