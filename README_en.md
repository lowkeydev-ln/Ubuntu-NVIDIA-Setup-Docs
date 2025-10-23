# Improved Guide for Setting Up Ubuntu Workstations with NVIDIA GPU

> **Last updated:** October 16, 2025

---

## Index

* [1. Pre-Installation Requirements](#1-pre-installation-requirements)
* [2. Ubuntu System Installation](#2-ubuntu-system-installation)
* [3. Initial Ubuntu System Preparation](#3-initial-ubuntu-system-preparation)
* [4. Installing NVIDIA Drivers on Ubuntu](#4-installing-nvidia-drivers-on-ubuntu)
* [5. Installing CUDA Toolkit](#5-installing-cuda-toolkit)
* [6. Specific Setup for Compression Workstations](#6-specific-setup-for-compression-workstations)
* [7. Specific Setup for Analytics Workstations](#7-specific-setup-for-analytics-workstations)
* [8. Managing the Graphical Interface](#8-managing-the-graphical-interface)
* [9. Common Network Issues with New Motherboards](#9-common-network-issues-with-new-motherboards)
* [10. Wake-on-LAN (WOL): Windows to Windows and Ubuntu to Windows](#10-wake-on-lan-wol-windows-to-windows-and-ubuntu-to-windows)
* [11. Post-Installation Script (Optional)](#11-post-installation-script-optional)
* [12. Security Best Practices (Optional)](#12-security-best-practices-optional)
* [FAQ: Frequently Asked Questions](#faq-frequently-asked-questions)
* [Annex A: Identifying NVIDIA GPUs](#annex-a-identifying-nvidia-gpus)
* [Annex B: Compatibility Verification](#annex-b-compatibility-verification)

---

> **Welcome!** This improved guide will help you install and configure Ubuntu with an NVIDIA GPU, optimizing each step and explaining the reasoning behind every action. All original commands and procedures are preserved, with added explanations, tips, and warnings for clarity.

---

## Visual Process Overview

`BIOS/UEFI` → `Ubuntu Installation` → `System Preparation` → `NVIDIA Drivers` → `CUDA Toolkit` → `Specific Configuration`

## 1. Pre-Installation Requirements

### What do you need before starting?

* **Bootable USB drive** Use Ventoy or BalenaEtcher to create it.
* **Ubuntu Desktop image** Download the recommended LTS version (22.04 or 24.04).
* **Purpose of the workstation** Decide if it will be used for Compression/Data or Analytics.

> **Tip:** Ubuntu Desktop is the most standard and compatible option for these setups.

---

## 2. Ubuntu System Installation

### Key steps and recommendations

1. **Access the BIOS/UEFI** (common keys: F2, F8, F11, F12, DEL, BACKSPACE).

1. **Configure the BIOS/UEFI:**

* Disable Secure Boot and TPM.
* (Optional) Set AC Power Loss to Always On for servers.

1. **Save and reboot** (usually F10).

1. **Boot from USB** and select the Ubuntu image.

1. **Edit boot parameters:**

* Add `nomodeset` after `---` to avoid graphics conflicts.
* Explanation: This prevents issues with new GPUs not supported by generic drivers.

1. **Install Ubuntu:**

* Choose language, keyboard layout, normal installation, and check third-party and multimedia options.
* Set up user and timezone.
* **Warning:** "Erase disk and install Ubuntu" will delete all data on the selected disk.

1. **Reboot and remove the USB.**

> **Note:** If unsure about any BIOS option, consult your motherboard manual.

---

## 3. Initial Ubuntu System Preparation

* **GDM3 Configuration (Optional but Recommended for Graphical Installation):** If you plan to use the graphical interface, it's recommended to disable Wayland to avoid issues with proprietary drivers.

  Edit the configuration file:
  ```bash
  sudo nano /etc/gdm3/custom.conf
  ```
  Find the line `#WaylandEnable=false` and **remove the `#`** to uncomment it. It should read:
  ```
  WaylandEnable=false
  ```
  Save (Ctrl+O, Enter) and close (Ctrl+X).

### Before installing drivers, prepare the system

* **Update the system**

  ```bash
  sudo apt update && sudo apt upgrade -y
  ```

* **Reboot to apply updates**

  ```bash
  sudo reboot
  ```

* **Install common dependencies**

  ```bash
  sudo apt install -y build-essential dkms pkg-config libglvnd-dev libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev libx11-dev libxmu-dev libxi-dev libglu1-mesa-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev mesa-utils inxi net-tools openssh-server curl git wget
  ```

* **Configure GDM3 (optional):** Disable Wayland to avoid issues with proprietary GPU drivers.

* **Configure the firewall for SSH**

  ```bash
  sudo ufw allow ssh
  sudo ufw --force enable
  ```

* **Version-specific preparation**
  * **Ubuntu 22.04:** Install and configure GCC/G++ 12.
  * **Ubuntu 24.04:** Install the `libtinfo5` dependency (needed for some older drivers/tools). You can download the package directly from the official repository:

    [Download libtinfo5 for Ubuntu 24.04 (noble)](http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb)

    ```bash
    wget http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb
    sudo apt install ./libtinfo5_6.3-2ubuntu0.1_amd64.deb
    rm libtinfo5_6.3-2ubuntu0.1_amd64.deb # Clean up the downloaded file
    ```

> **Warning:** Check driver and CUDA compatibility before installing. Commands with `sudo` can alter the system.

---

## 4. Installing NVIDIA Drivers on Ubuntu

* **Preparation for Installation:**
  Make sure the graphical environment (GDM) is not running or switch to text mode:
  ```bash
  sudo systemctl set-default multi-user.target
  sudo reboot
  ```
  Give execution permissions to the `.run` file:
  ```bash
  sudo chmod +x NVIDIA-Linux-x86_64-XXX.XX.run # Replace XXX.XX with the downloaded version number
  ```
* **Driver Installation:**
  Run the installer with `sudo` and the `--dkms` flag to facilitate kernel updates:
  ```bash
  sudo ./NVIDIA-Linux-x86_64-XXX.XX.run --dkms
  ```
  The installer will ask questions:
  - `The distribution-provided pre-install script failed! Are you sure you want to continue?` -> `Continue Installation`
  - `Would you like to register the kernel module sou...` -> `Yes` (if you used `--dkms`)
  - `Install NVIDIA's 32-bit compatibility libraries?` -> `Yes`
  - `Would you like to run nvidia-xconfig?` -> `No` (unless you have a specific X11 configuration)
  - `Would you like to enable nvidia-apply-extra-quirks?` -> `Yes` (if available)

### How to properly install the drivers?

* **Identify your GPU**

  ```bash
  lspci | grep -i nvidia
  ```

* **Check compatibility** Refer to the GPU table and Annex B.

* **Remove old drivers**

  ```bash
  sudo apt-get purge '^nvidia-.*'
  sudo apt-get purge nvidia-* --autoremove -y
  sudo apt-get autoremove -y
  sudo reboot
  ```

* **Download the official driver** from NVIDIA's website:

  [Official NVIDIA Drivers Page](https://www.nvidia.com/drivers/)

  Select your GPU, operating system, and version. Download the `.run` file manually from the web, or copy the direct link and download it via terminal with `wget`:

  ```bash
  wget https://us.download.nvidia.com/XFree86/Linux-x86_64/XXX.XX/NVIDIA-Linux-x86_64-XXX.XX.run
  # Replace XXX.XX with the version corresponding to your GPU and system
  ```

* **Prepare for installation**
  * Switch to text mode if needed.
  * Make the `.run` file executable.

* **Install the driver**
  * Use the `--dkms` flag for easier kernel updates.
  * Answer the installer questions as recommended.

* **Verify the installation**

  ```bash
  nvidia-smi
  ```
  * If you see your GPU information, everything is correct!

> **Tip:** If you have issues with the graphical environment, check the graphical interface management section.

---

## 5. Installing CUDA Toolkit

### Install CUDA safely and compatibly

> **Important:** Check compatibility in Annex B before installing. Make sure your GPU and NVIDIA driver are compatible with the desired CUDA version.

There are two main methods to install CUDA Toolkit: via APT repository (recommended for ease of updates) or manual installation with the `.run` file (greater control).

---

#### **Method 1: Installation via APT Repository (Recommended)**

This method facilitates updates and package management.

1. **Download and install the repository key:**

   For Ubuntu 24.04:
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
   sudo dpkg -i cuda-keyring_1.1-1_all.deb
   sudo apt-get update
   ```

   For Ubuntu 22.04:
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
   sudo dpkg -i cuda-keyring_1.1-1_all.deb
   sudo apt-get update
   ```

2. **Install CUDA Toolkit:**

   To install the latest available version:
   ```bash
   sudo apt-get install -y cuda-toolkit
   ```

   To install a specific version (example: CUDA 12.8):
   ```bash
   sudo apt-get install -y cuda-toolkit-12-8
   ```

3. **Configure environment variables:**

   Edit your `.bashrc` file:
   ```bash
   nano ~/.bashrc
   ```

   Add these lines at the end (adjust the version according to what was installed):
   ```bash
   export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}
   export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
   ```

   Save (Ctrl+O, Enter) and close (Ctrl+X).

   Reload the `.bashrc` file:
   ```bash
   source ~/.bashrc
   ```

4. **Verify the installation:**

   ```bash
   nvcc --version
   ```

   You should see information about the installed CUDA version.

---

#### **Method 2: Manual Installation with .run file**

This method offers greater control over which components to install.

1. **Download the installer from the official website:**

   Visit [https://developer.nvidia.com/cuda-downloads](https://developer.nvidia.com/cuda-downloads) and select:
   - Operating System: Linux
   - Architecture: x86_64
   - Distribution: Ubuntu
   - Version: 22.04 or 24.04
   - Installer Type: **runfile (local)**

   Download with `wget` (example for CUDA 12.8):
   ```bash
   wget https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda_12.8.0_550.54.15_linux.run
   ```

2. **Prepare the system:**

   Switch to text mode (optional but recommended):
   ```bash
   sudo systemctl set-default multi-user.target
   sudo reboot
   ```

   Give execution permissions:
   ```bash
   chmod +x cuda_12.8.0_550.54.15_linux.run
   ```

3. **Run the installer:**

   ```bash
   sudo sh cuda_12.8.0_550.54.15_linux.run
   ```

   **During installation:**
   - Accept the EULA (End User License Agreement)
   - **DO NOT install the driver if you already have one installed** (uncheck that option)
   - Select the components you want to install:
     - CUDA Toolkit (mandatory)
     - CUDA Samples (optional)
     - CUDA Documentation (optional)

4. **Configure environment variables:**

   Edit your `.bashrc` file:
   ```bash
   nano ~/.bashrc
   ```

   Add these lines at the end:
   ```bash
   export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}
   export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
   ```

   Save (Ctrl+O, Enter) and close (Ctrl+X).

   Reload the `.bashrc` file:
   ```bash
   source ~/.bashrc
   ```

5. **Verify the installation:**

   ```bash
   nvcc --version
   nvidia-smi
   ```

6. **Reactivate the graphical environment (if you disabled it):**

   ```bash
   sudo systemctl set-default graphical.target
   sudo reboot
   ```

---

### Which method to choose?

| Feature | APT Repository | .run Installer |
|---------|----------------|----------------|
| **Ease of installation** | ⭐⭐⭐⭐⭐ Very easy | ⭐⭐⭐ Moderate |
| **Updates** | ⭐⭐⭐⭐⭐ Automatic with `apt` | ⭐⭐ Manual |
| **Component control** | ⭐⭐⭐ Limited | ⭐⭐⭐⭐⭐ Complete |
| **Multiple versions** | ⭐⭐⭐ Possible but complex | ⭐⭐⭐⭐⭐ Easy |
| **Recommended for** | General users | Advanced developers |

> **Recommendation:** For most users, the APT repository method is more convenient and facilitates system maintenance.

> **Warning:** Installing CUDA may require rebooting the system. If you encounter conflicts with drivers, review section 4 on NVIDIA drivers.

> **Note:** For Ubuntu 24.04, CUDA 12.8 or higher is recommended. Always check compatibility in Annex B.

---

## 6. Specific Setup for Compression Workstations

* **MongoDB Installation:**
  Import the official GPG key:
  ```bash
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
  ```
  Add the MongoDB repository (adjust `jammy` to `noble` if using Ubuntu 24.04):
  ```bash
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
  ```
  Update and install MongoDB:
  ```bash
  sudo apt-get update
  sudo apt-get install -y mongodb-org
  ```
  Start and enable the service:
  ```bash
  sudo systemctl start mongod
  sudo systemctl enable mongod
  ```
  (Optional) Check the status:
  ```bash
  sudo systemctl status mongod
  ```

### Recommended tools for compression/data

Below are the installations of additional tools for compression/data workstations.

* **EMQX Installation:**
  
  Add the repository and install:
  ```bash
  curl -sL https://assets.emqx.com/scripts/install-emqx-deb.sh | sudo bash
  sudo apt-get install emqx
  ```
  
  Start and enable the service:
  ```bash
  sudo systemctl start emqx
  sudo systemctl enable emqx
  ```
  
  (Optional) Check the status:
  ```bash
  sudo systemctl status emqx
  ```

* **Golang Installation (Snap):**
  
  ```bash
  sudo snap install go --classic
  ```

* **Visual Studio Code Installation (Snap):**
  
  ```bash
  sudo snap install code --classic
  ```

* **GStreamer and Plugins Installation:**
  
  Install the necessary plugins:
  ```bash
  sudo apt-get install -y gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav gstreamer1.0-tools gstreamer1.0-x gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-qt5 gstreamer1.0-pulseaudio gstreamer1.0-rtsp
  ```
  
  Verify the installation of specific plugins:
  ```bash
  gst-inspect-1.0 rtspclientsink
  gst-inspect-1.0 nvh264enc
  ```

* **Angry IP Scanner Installation:**
  
  Download the `.deb` package from [Angry IP Scanner Releases](https://github.com/angryip/ipscan/releases) and install it:
  ```bash
  sudo apt install ./ipscan_<version>_amd64.deb
  # Replace <version> with the downloaded file
  ```

* **Anydesk Installation for remote support:**
  
  Add the official repository and install:
  ```bash
  sudo apt update
  sudo apt install ca-certificates curl apt-transport-https
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://keys.anydesk.com/repos/DEB-GPG-KEY -o /etc/apt/keyrings/keys.anydesk.com.asc
  sudo chmod a+r /etc/apt/keyrings/keys.anydesk.com.asc
  echo "deb [signed-by=/etc/apt/keyrings/keys.anydesk.com.asc] https://deb.anydesk.com all main" | sudo tee /etc/apt/sources.list.d/anydesk-stable.list > /dev/null
  sudo apt update
  sudo apt install anydesk
  ```
  
  > **Important:** Take note of the Anydesk ID and set a unique password.

* **Rustdesk Installation for remote support:**
  
  Download the `.deb` package from [Rustdesk Releases](https://github.com/rustdesk/rustdesk/releases) (x86-64 version for Ubuntu) and install it:
  ```bash
  sudo apt install ./<package.deb>
  # Replace <package.deb> with the downloaded file name
  ```
  
  > **Important:** Take note of the Rustdesk ID, set a unique password, and check the box that allows direct IP connection.

* **Tips:**
  * Check service status after installation.
  * Set unique passwords for remote access.
  * Verify specific plugin installation with `gst-inspect-1.0`.

> **Additional Resources:**
> * [Official MongoDB Documentation](https://www.mongodb.com/docs/)
> * [Official EMQX Documentation](https://www.emqx.io/docs/)
> * [Official GStreamer Documentation](https://gstreamer.freedesktop.org/documentation/)

---

## 7. Specific Setup for Analytics Workstations

* **MongoDB Configuration (Database and User Creation):**
  Access the MongoDB console:
  ```bash
  mongosh
  ```
  Create the database and a user with read/write permissions (replace `DB_NAME`, `USER`, `PASSWORD` with your actual values):
  ```javascript
  use DB_NAME
  db.createUser({
    user: "USER",
    pwd: "PASSWORD",
    roles: [
      {
        role: "readWrite",
        db: "DB_NAME"
      }
    ]
  })
  ```
  Edit the MongoDB configuration to enable authorization:
  ```bash
  sudo nano /etc/mongod.conf
  ```
  Uncomment the `security:` section and add below (indenting 2 spaces):
  ```yaml
  security:
    authorization: enabled
  ```
  Save (Ctrl+O, Enter) and close (Ctrl+X).
  Restart the service to apply changes:
  ```bash
  sudo systemctl restart mongod
  ```

* **Node-RED Installation:**
  Run the installation script:
  ```bash
  bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)
  ```
  (Optional) Enable the service manually if the script didn't do it:
  ```bash
  sudo systemctl enable nodered
  sudo systemctl start nodered
  ```
  (Optional) Check the status:
  ```bash
  sudo systemctl status nodered
  ```

### Recommended tools for analytics/machine learning

Below are the installations of additional tools for analytics workstations.

* **Python and Pip Installation:**
  
  ```bash
  sudo apt install -y python3 python3-pip
  ```

* **Python Libraries Installation for Machine Learning:**
  
  Update pip:
  ```bash
  pip3 install --upgrade pip
  ```
  
  Install the necessary libraries:
  ```bash
  pip3 install pandas numpy scikit-learn paho-mqtt ultralytics
  ```
  
  > **Note:** You can add more libraries according to your needs (matplotlib, tensorflow, pytorch, opencv-python, etc.).

> **Additional Resources:**
> * [Official Node-RED Documentation](https://nodered.org/docs/)
> * [MongoDB Documentation](https://www.mongodb.com/docs/)
> * [Pandas Documentation](https://pandas.pydata.org/docs/)
> * [Scikit-learn Documentation](https://scikit-learn.org/stable/)

> **Tip:** Update pip regularly and consider using virtual environments for specific projects.

---

## 8. Graphical Interface Management

To switch between login screen environments for graphical mode and console mode:

```bash
sudo dpkg-reconfigure gdm3
```

* Select **gdm3** for graphical environment (default).
* Select **lightdm** or other display manager if you prefer a different login screen.

### Stopping Graphical Mode (temporarily)

If you need to work in console mode (without the graphical environment, saves resources), run:

```bash
sudo systemctl stop gdm3
```

To start it again:

```bash
sudo systemctl start gdm3
```

### Disabling Graphical Mode at Startup (permanent change)

To set the system to boot in console mode (multi-user text mode):

```bash
sudo systemctl set-default multi-user.target
```

To re-enable graphical mode at startup:

```bash
sudo systemctl set-default graphical.target
```

> **Note:** If working in console mode, you can manually start the graphical interface with:
> ```bash
> startx
> ```
> Or switch to a graphical session using `Ctrl+Alt+F7` (or another function key like F1-F6 to return to console).

---

## 9. Network Issues with Realtek RTL8125 Controller

If you experience **network connectivity or stability issues** with the Realtek RTL8125 2.5G Ethernet controller (common on some motherboards like MSI B550), here's how to **update to the latest driver**:

### Step-by-Step Solution

1. **Download the latest driver:**
   
   Go to the official Realtek page or use this direct link to download the latest driver package for Linux:
   
   [Realtek RTL8125 Driver (Official)](https://www.realtek.com/Download/Index?type=network-ethernet)

   Alternatively, you can download the `r8125-9.013.02.tar.bz2` version directly (or the latest available).

2. **Extract the compressed file:**
   
   ```bash
   tar -xvjf r8125-9.013.02.tar.bz2
   ```

3. **Navigate to the extracted directory:**
   
   ```bash
   cd r8125-9.013.02
   ```

4. **Install necessary dependencies (if not already installed):**
   
   ```bash
   sudo apt install -y build-essential dkms linux-headers-$(uname -r)
   ```

5. **Compile and install the driver:**
   
   Within the extracted folder, run:
   ```bash
   sudo ./autorun.sh
   ```

6. **Reboot the system:**
   
   ```bash
   sudo reboot
   ```

7. **Verify the driver is loaded correctly:**
   
   After rebooting, check the driver version:
   ```bash
   ethtool -i enp6s0 | grep driver
   ethtool -i enp6s0 | grep version
   ```
   
   Replace `enp6s0` with your network interface name (check with `ip link` or `ifconfig`).

### Additional Considerations

* **DKMS (Dynamic Kernel Module Support):** If you want the driver to automatically rebuild when the kernel updates, copy the driver to the DKMS directory before running `autorun.sh`:
  ```bash
  sudo cp -r r8125-9.013.02 /usr/src/
  sudo dkms add -m r8125 -v 9.013.02
  sudo dkms build -m r8125 -v 9.013.02
  sudo dkms install -m r8125 -v 9.013.02
  ```

* **Common network interface names:**
  - `enp6s0`, `enp7s0`, `eno1`, `eth0`, etc.
  - Use `ip link show` to list all network interfaces.

> **Note:** This procedure is especially useful if the default driver included with Ubuntu (`r8169`) doesn't work correctly with the RTL8125 2.5G controller.

> **Additional Resources:**
> * [Official Realtek Downloads](https://www.realtek.com/Download/Index?type=network-ethernet)
> * [Ubuntu Forums - Network Issues](https://ubuntuforums.org/)

---

## 10. Wake-on-LAN Configuration

**Wake-on-LAN (WoL)** allows you to remotely power on a computer via the network. This is useful for remote management, scheduled maintenance, and resource optimization.

### Requirements

1. **BIOS/UEFI Support:**
   - Enable the **Wake-on-LAN** option in the BIOS/UEFI.
   - Common settings: **"Wake on PCIe"**, **"Wake on LAN"**, or **"Power On By PCI-E Device"**.

2. **Network Adapter Support:**
   - The network adapter must support Wake-on-LAN (most modern adapters do).

3. **Power Supply:**
   - The computer must remain connected to power (PSU).

### Linux Configuration (Target Computer)

1. **Install `ethtool`:**
   
   ```bash
   sudo apt install -y ethtool
   ```

2. **Check if Wake-on-LAN is enabled:**
   
   ```bash
   sudo ethtool enp6s0 | grep Wake-on
   ```
   
   Replace `enp6s0` with your network interface name (use `ip link` to list interfaces).
   
   * If `Wake-on: d`, it means **disabled**.
   * If `Wake-on: g`, it means **enabled** (magic packet).

3. **Enable Wake-on-LAN:**
   
   ```bash
   sudo ethtool -s enp6s0 wol g
   ```

4. **Make Wake-on-LAN persistent after reboot:**
   
   Create a systemd service to enable WoL on boot:
   
   ```bash
   sudo nano /etc/systemd/system/wol.service
   ```
   
   Paste the following content (replace `enp6s0` with your interface):
   
   ```ini
   [Unit]
   Description=Enable Wake-on-LAN for enp6s0
   After=network.target
   
   [Service]
   Type=oneshot
   ExecStart=/usr/sbin/ethtool -s enp6s0 wol g
   
   [Install]
   WantedBy=multi-user.target
   ```
   
   Save (Ctrl+O, Enter) and close (Ctrl+X).
   
   Enable and start the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable wol.service
   sudo systemctl start wol.service
   ```

5. **Get the MAC Address:**
   
   Note the MAC address of the network interface:
   ```bash
   ip link show enp6s0
   ```
   
   Example output: `link/ether 00:11:22:33:44:55`

### Sending Wake-on-LAN from Windows

You can send a magic packet from a Windows computer on the same network to wake up the Linux machine.

<details>
<summary><strong>Click here to view the PowerShell script</strong></summary>

Save the following script as `WakeOnLAN.ps1`:

```powershell
# WakeOnLAN.ps1
# Sends a magic packet to wake up a computer via Wake-on-LAN

param(
    [Parameter(Mandatory=$true)]
    [string]$MacAddress
)

# Remove separators (colons, dashes, dots) from the MAC address
$MacClean = $MacAddress -replace '[:-\.]', ''

# Validate that the MAC address has 12 hexadecimal characters
if ($MacClean.Length -ne 12 -or $MacClean -notmatch '^[0-9A-Fa-f]{12}$') {
    Write-Host "Error: Invalid MAC address. Use format XX:XX:XX:XX:XX:XX, XX-XX-XX-XX-XX-XX, or XXXXXXXXXXXX" -ForegroundColor Red
    exit 1
}

# Convert the MAC address to an array of bytes
$MacBytes = [byte[]]@()
for ($i = 0; $i -lt 12; $i += 2) {
    $MacBytes += [convert]::ToByte($MacClean.Substring($i, 2), 16)
}

# Build the magic packet: 6 bytes of 0xFF + 16 repetitions of the MAC address
$MagicPacket = [byte[]](,0xFF * 6) + ($MacBytes * 16)

# Create a UDP client and send the packet to the broadcast address on port 9
$UdpClient = New-Object System.Net.Sockets.UdpClient
try {
    $UdpClient.Connect("255.255.255.255", 9)
    $BytesSent = $UdpClient.Send($MagicPacket, $MagicPacket.Length)
    
    Write-Host "Magic packet sent successfully to MAC: $MacAddress ($BytesSent bytes)" -ForegroundColor Green
} catch {
    Write-Host "Error sending magic packet: $_" -ForegroundColor Red
} finally {
    $UdpClient.Close()
}
```

**Usage:**

```powershell
.\WakeOnLAN.ps1 -MacAddress "00:11:22:33:44:55"
```

Replace `00:11:22:33:44:55` with the MAC address of the target computer.

</details>

### Sending Wake-on-LAN from Linux

Use the `wakeonlan` tool (or alternatives like `etherwake`):

```bash
sudo apt install -y wakeonlan
wakeonlan 00:11:22:33:44:55
```

Replace `00:11:22:33:44:55` with the target MAC address.

### Troubleshooting

1. **Check BIOS/UEFI:** Ensure Wake-on-LAN is enabled.
2. **Check router/switch:** Some routers block broadcast packets; ensure they allow WoL magic packets.
3. **Verify Wake-on-LAN status:**
   ```bash
   sudo ethtool enp6s0 | grep Wake-on
   ```
   Should show `Wake-on: g`.
4. **Firewall:** Ensure UDP port 9 is not blocked.

> **Additional Resources:**
> * [Wake-on-LAN Wikipedia](https://en.wikipedia.org/wiki/Wake-on-LAN)
> * [Ubuntu WoL Guide](https://help.ubuntu.com/community/WakeOnLan)

> **Tip:** For remote WoL over the internet, configure port forwarding on your router (UDP port 9) and use a dynamic DNS service.

---

## 11. Post-Installation Bash Script (Optional)

For those who prefer to automate many of the steps described in this guide, below is a **Bash script** that:

- Updates and upgrades the system.
- Installs basic utilities (curl, wget, git, vim, net-tools, htop).
- Adds the graphics-drivers PPA repository and installs the NVIDIA driver (version 565 in this example).
- Installs CUDA 12.8 via the APT repository method.
- Installs MongoDB 8.0.
- Installs EMQX.
- Installs Golang (via Snap).
- Installs Visual Studio Code (via Snap).
- Installs GStreamer plugins.
- Installs Node-RED.
- Installs Python3, pip, and basic libraries for analytics.

> **Important:** This script is **illustrative** and should be reviewed before running. Adjust package versions, drivers, and configurations according to your specific needs.

```bash
#!/bin/bash
# post-installation.sh
# Post-installation script for Ubuntu 22.04/24.04 with NVIDIA drivers and CUDA.

set -e  # Exit on any error

echo "========================================="
echo " Ubuntu Post-Installation Script"
echo " NVIDIA + CUDA + Development Tools"
echo "========================================="

# 1. System Update
echo "[1/12] Updating the system..."
sudo apt update && sudo apt upgrade -y

# 2. Basic Utilities
echo "[2/12] Installing basic utilities..."
sudo apt install -y curl wget git vim net-tools htop build-essential

# 3. GCC/G++ 12 (for Ubuntu 24.04)
if lsb_release -r | grep -q "24.04"; then
  echo "[3/12] Installing GCC/G++ 12 for Ubuntu 24.04..."
  sudo apt install -y gcc-12 g++-12
  sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
  sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100
else
  echo "[3/12] Skipping GCC/G++ 12 (not Ubuntu 24.04)."
fi

# 4. Reconfigure GDM3 and install libtinfo5 (for Ubuntu 24.04)
echo "[4/12] Configuring GDM3 and installing libtinfo5..."
sudo dpkg-reconfigure gdm3
if lsb_release -r | grep -q "24.04"; then
  sudo apt install -y libtinfo5
fi

# 5. NVIDIA Driver Installation
echo "[5/12] Adding graphics-drivers PPA and installing NVIDIA driver..."
sudo add-apt-repository -y ppa:graphics-drivers/ppa
sudo apt update
sudo apt install -y nvidia-driver-565

# 6. CUDA Toolkit Installation (APT Method)
echo "[6/12] Installing CUDA Toolkit 12.8..."
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y cuda-toolkit-12-8

# Add CUDA to PATH
if ! grep -q "/usr/local/cuda-12.8/bin" ~/.bashrc; then
  echo 'export PATH=/usr/local/cuda-12.8/bin:$PATH' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
fi

# 7. MongoDB Installation
echo "[7/12] Installing MongoDB 8.0..."
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
sudo apt update
sudo apt install -y mongodb-org
sudo systemctl enable mongod
sudo systemctl start mongod

# 8. EMQX Installation
echo "[8/12] Installing EMQX..."
curl -s https://assets.emqx.com/scripts/install-emqx-deb.sh | sudo bash
sudo apt install -y emqx
sudo systemctl enable emqx
sudo systemctl start emqx

# 9. Golang Installation (Snap)
echo "[9/12] Installing Golang..."
sudo snap install go --classic

# 10. Visual Studio Code Installation (Snap)
echo "[10/12] Installing Visual Studio Code..."
sudo snap install code --classic

# 11. GStreamer Installation
echo "[11/12] Installing GStreamer plugins..."
sudo apt install -y gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-libav

# 12. Node-RED Installation
echo "[12/12] Installing Node-RED..."
bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)
sudo systemctl enable nodered
sudo systemctl start nodered

# 13. Python and Libraries
echo "[13/13] Installing Python3, pip, and analytics libraries..."
sudo apt install -y python3 python3-pip
pip3 install --upgrade pip
pip3 install pandas numpy scikit-learn paho-mqtt ultralytics

echo "========================================="
echo " Installation Complete!"
echo " Reboot the system to apply all changes:"
echo " sudo reboot"
echo "========================================="
```

**Usage:**

1. Save the script as `post-installation.sh`:
   ```bash
   nano post-installation.sh
   ```
   Paste the content above, save (Ctrl+O, Enter), and close (Ctrl+X).

2. Make it executable:
   ```bash
   chmod +x post-installation.sh
   ```

3. Run the script:
   ```bash
   ./post-installation.sh
   ```

4. Reboot after completion:
   ```bash
   sudo reboot
   ```

> **Note:** This script is a **starting point**. Review each section and adjust versions, configurations, and tools according to your specific requirements. Some installations may require manual interaction (e.g., GDM3 reconfiguration, NVIDIA installer questions).

> **Tip:** For a fully automated installation, consider using configuration management tools like Ansible, Puppet, or Chef.

---

## 12. Security Best Practices

When setting up a workstation with NVIDIA drivers, CUDA, and development tools, it's essential to follow security best practices:

### 1. Keep the System Updated

Regularly update the system and packages:

```bash
sudo apt update && sudo apt upgrade -y
```

Enable automatic security updates:

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades
```

### 2. Configure a Firewall

Install and enable UFW (Uncomplicated Firewall):

```bash
sudo apt install -y ufw
sudo ufw enable
```

Allow only necessary services (example for SSH):

```bash
sudo ufw allow ssh
sudo ufw status
```

### 3. Secure SSH Access

If you use SSH to remotely access your workstation:

* Change the default SSH port (edit `/etc/ssh/sshd_config`):
  ```bash
  sudo nano /etc/ssh/sshd_config
  ```
  Change `#Port 22` to `Port 2222` (or another port), save, and restart SSH:
  ```bash
  sudo systemctl restart ssh
  ```

* Disable root login via SSH:
  ```bash
  sudo nano /etc/ssh/sshd_config
  ```
  Set `PermitRootLogin no`, save, and restart SSH.

* Use SSH keys instead of passwords:
  ```bash
  ssh-keygen -t ed25519 -C "your_email@example.com"
  ssh-copy-id user@remote_host
  ```

### 4. Create Strong Passwords

Use strong, unique passwords for all user accounts. Consider using a password manager.

### 5. Enable Automatic Backups

Set up automatic backups for critical data using tools like `rsync`, `timeshift`, or cloud services.

### 6. Monitor System Logs

Regularly check system logs for suspicious activity:

```bash
sudo journalctl -xe
sudo tail -f /var/log/syslog
```

### 7. Limit User Privileges

Grant sudo access only to trusted users. Avoid using the root account for daily tasks.

### 8. Install and Configure Fail2Ban

Protect against brute-force attacks:

```bash
sudo apt install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

Configure `/etc/fail2ban/jail.local` to customize ban rules for SSH and other services.

### 9. Use AppArmor or SELinux

AppArmor is enabled by default on Ubuntu and provides mandatory access control. Verify it's active:

```bash
sudo aa-status
```

### 10. Disable Unnecessary Services

Review and disable services that are not needed:

```bash
sudo systemctl list-unit-files --type=service
sudo systemctl disable <service_name>
```

> **Additional Resources:**
> * [Ubuntu Security Guide](https://ubuntu.com/security)
> * [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
> * [OWASP Top Ten](https://owasp.org/www-project-top-ten/)

> **Tip:** Regularly review security practices and stay informed about emerging threats and vulnerabilities.

---

## FAQ: Frequently Asked Questions

* **What if the NVIDIA driver doesn't install correctly?**
  * Check compatibility in Annex B and make sure old drivers are removed.

* **How do I know which CUDA version to install?**
  * Check the official website and verify compatibility with your GPU and driver.

* **Why doesn't Wake-on-LAN work?**
  * Check BIOS settings, power options, and ensure the PC is connected via cable.

* **Can I use this guide for Ubuntu variants?**
  * Yes, but there may be minor differences. Ubuntu Desktop is recommended.

---

## Annex A: Identifying NVIDIA GPUs

### How to identify your NVIDIA GPU?

To identify your NVIDIA GPU generation and model, run:

```bash
lspci | grep VGA
```

Then compare the hexadecimal Device ID with the following tables:

#### Series 3000 (Ampere)

| Series | Model      | Device ID (hex) |
| ------ | ---------- | --------------- |
| 3000   | RTX 3090   | 2204            |
| 3000   | RTX 3090 Ti| 22C6            |
| 3000   | RTX 3080   | 2206            |
| 3000   | RTX 3080 Ti| 2382            |
| 3000   | RTX 3070 Ti| 24C0            |
| 3000   | RTX 3070   | 2484            |
| 3000   | RTX 3060 Ti| 2489            |
| 3000   | RTX 3060   | 2503            |
| 3000   | RTX 3050 Ti| 2191            |
| 3000   | RTX 3050   | 25A0            |

#### Series 4000 (Ada Lovelace)

| Series | Model            | Device ID (hex) |
| ------ | ---------------- | --------------- |
| 4000   | RTX 4090         | 2684            |
| 4000   | RTX 4080 Super   | 2702            |
| 4000   | RTX 4080         | 2704            |
| 4000   | RTX 4070 Ti Super| 26B0            |
| 4000   | RTX 4070 Ti      | 2782            |
| 4000   | RTX 4070 Super   | 2788            |
| 4000   | RTX 4070         | 2786            |
| 4000   | RTX 4060 Ti      | 28A3            |
| 4000   | RTX 4060         | 2882            |
| 4000   | RTX 4050         | 28A1            |

#### Series 5000 (Blackwell)

| Series | Model      | Device ID (hex) |
| ------ | ---------- | --------------- |
| 5000   | RTX 5090   | 2B80            |
| 5000   | RTX 5080   | 2B81            |
| 5000   | RTX 5070 Ti| 2B82            |
| 5000   | RTX 5070   | 2B83            |
| 5000   | RTX 5060 Ti| 2B84            |
| 5000   | RTX 5060   | 2B85            |

---

## Annex B: Compatibility Verification

### How to verify compatibility between GPU, driver, and CUDA?

1. **GPU and NVIDIA Driver:**
   * Visit [https://www.nvidia.com/drivers/](https://www.nvidia.com/drivers/).
   * Select your GPU and operating system to see compatible drivers.

2. **NVIDIA Driver and CUDA Toolkit:**
   * Visit [https://developer.nvidia.com/cuda-downloads](https://developer.nvidia.com/cuda-downloads).
   * Look for the "CUDA Compatibility" or "CUDA Requirements" section.
   * Example: CUDA 12.8 requires NVIDIA driver >= 525.x.
   * Check your driver version with:

   ```bash
   nvidia-smi
   ```

   The version must be equal to or greater than the minimum required by CUDA.

3. **CUDA Toolkit and Ubuntu:**
   * The CUDA download page lists supported Ubuntu versions for each CUDA Toolkit version.

---
