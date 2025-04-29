# wireguard-access-manager
Fine-grained client access control and IP segmentation for maximum wireguard VPN security.

📦 Installation

WireGuard Access Manager provides a secure and user-isolated VPN configuration tool for Linux systems.

✅ Quick Install (Recommended)

You can install the WireGuard Manager globally with one command:

curl -sfL https://raw.githubusercontent.com/nazmul-islam21/wireguard-access-manager/main/wg-nstall.sh | sh -s
This will:

Install required packages (wireguard-tools, qrencode, zip, unzip, etc.)
Download the wireguard_manager script
Place it in /usr/local/bin/ as a global command
Make it executable
After installation, you can run the manager from anywhere using:

wireguard_manager
🧱 Requirements


Component	Required
Linux OS	✅ Ubuntu, Debian, Rocky, AlmaLinux
Bash Shell	✅ /bin/bash
WireGuard	✅ wireguard-tools
QR Code Generator	✅ qrencode
Archiver Tools	✅ zip, unzip
Internet Access	✅ To fetch installer and dependencies
🖥️ Supported Distributions

✅ Ubuntu 20.04 / 22.04 / 24.04
✅ Debian 10 / 11 / 12
✅ Rocky Linux / AlmaLinux 8 or 9
✅ Other bash-based Linux (manual install supported)
🔒 File Locations After Install


Path	Purpose
/usr/local/bin/wireguard_manager	The main executable script
~/.wireguard_manager/configs/	Client config files
~/.wireguard_manager/iptables/	IPTables per-client rule scripts
~/.wireguard_manager/qrcodes/	QR code PNG files
~/wg-backup/	Backup zip files (optional backup location)
🧪 Post-Install Test

After installation, verify the command works:

wireguard_manager
You should see the ProPlusDeploy menu.

💡 Need to Update?

To update the tool later:

sudo rm -f /usr/local/bin/wireguard_manager
curl -sfL https://raw.githubusercontent.com/nazmul-islam21/wireguard-access-manager/main/wireguard_manager.sh -o /usr/local/bin/wireguard_manager
sudo chmod +x /usr/local/bin/wireguard_manager
🛠 Uninstall

To remove the manager:

sudo rm -f /usr/local/bin/wireguard_manager
rm -rf ~/.wireguard_manager ~/wg-backup
