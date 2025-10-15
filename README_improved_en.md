# Improved Guide for Setting Up Ubuntu Workstations with NVIDIA GPU

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
* [FAQ: Frequently Asked Questions](#faq-frequently-asked-questions)
* [Annex A: Identifying NVIDIA GPUs](#annex-a-identifying-nvidia-gpus)
* [Annex B: Compatibility Verification](#annex-b-compatibility-verification)

---

> **Welcome!** This improved guide will help you install and configure Ubuntu with an NVIDIA GPU, optimizing each step and explaining the reasoning behind every action. All original commands and procedures are preserved, with added explanations, tips, and warnings for clarity.

---

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

* Ubuntu 22.04: Install and configure GCC/G++ 12.
* Ubuntu 24.04: Install libtinfo5 if needed.

> **Warning:** Check driver and CUDA compatibility before installing. Commands with `sudo` can alter the system.

---

## 4. Installing NVIDIA Drivers on Ubuntu

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

* **Download the official driver** from NVIDIA's website.

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

* **Check compatibility** See Annex B before installing.

* **Download and install the APT repository**

* Follow the steps on the official CUDA website.

* **Set environment variables**

* Edit `.bashrc` and add CUDA paths.

* **Verify the installation**

```bash
nvcc --version
```

> **Note:** Adjust the CUDA version according to your hardware and needs.

---

## 6. Specific Setup for Compression Workstations

### Recommended tools for compression/data

* Install common packages, MongoDB, EMQX, Golang, VS Code, GStreamer, Angry IP Scanner, Anydesk, and Rustdesk following the original commands.

* **Tips:**

* Check service status after installation.
* Set unique passwords for remote access.
* Check specific plugin installation with `gst-inspect-1.0`.

---

## 7. Specific Setup for Analytics Workstations

### Recommended tools for analytics/machine learning

* Install MongoDB and configure it with user and database.

* Install NodeRED and enable the service.

* Install Python, pip, and necessary libraries for data analysis and machine learning.

> **Tip:** Upgrade pip before installing libraries.

---

## 8. Managing the Graphical Interface

### How to enable or disable the graphical environment?

* **Disable**

```bash
sudo systemctl disable gdm3
sudo systemctl set-default multi-user.target
sudo reboot
```

* **Enable**

```bash
sudo systemctl enable gdm3
sudo systemctl set-default graphical.target
sudo reboot
```

> **Explanation:** Disabling the graphical interface frees up resources, useful for servers managed via SSH.

---

## 9. Common Network Issues with New Motherboards

### Issues with Realtek RTL8125?

* Diagnose the network interface and update the system.

* Install the correct driver and blacklist the old one.

* Update initramfs and reboot.

* Check the interface after reboot.

> **Tip:** If the network still doesn't work, check your exact motherboard model and look for specific drivers.

---

## 10. Wake-on-LAN (WOL): Windows to Windows and Ubuntu to Windows

### How to wake up a PC over the network?

* Properly configure BIOS and Windows on the target PC.

* Send the magic packet from Windows (PowerShell) or Ubuntu (`wakeonlan` or `etherwake`).

* Verify the packet with Wireshark or tcpdump.

* Check the common issues section if it doesn't work.

> **Note:** WOL over Wi-Fi is rarely supported. Always use Ethernet.

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
