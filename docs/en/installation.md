---
title: Installation
description: Flash a Weelikeit F83W with flash.sh. Requirements, download and the seven steps from factory state to signing in to Home Assistant on the wall display.
order: 10
slug: installation
section: Getting started
---

Everything runs through one script: `flash.sh`. It guides you step by step, waits for input on the tablet and detects
by itself when it can continue. Steps already done are skipped; after an interruption simply start it again.

## Requirements

- **Mac** with Apple Silicon or Intel and `python3` (Xcode Command Line Tools: `xcode-select --install`)
- **Homebrew**: if it is missing, the script offers to install it. It provides `adb` and `fastboot`
  (`android-platform-tools`) and `xz` to unpack the image.
- **USB data cable**: charging-only cables are not enough.
- **Battery** at least 40 %, or the tablet on its charger
- about **2.5 GB** of free space for the packed and the unpacked image
- Internet: the script downloads the image (about 650 MB) on the first run.

## Download and run

```bash
git clone https://github.com/DasRed/weelike-f83w-homeassistant-kiosk.git
cd weelike-f83w-homeassistant-kiosk
./flash.sh
```

The system image is not stored in the repository. GitHub Actions builds it and publishes it as a
[release](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases) named
`lineage-20-a64_bvS-f83w-<version>.img.xz` (about 650 MB, 1.6 GB unpacked). On the first run the script downloads the
configured version (`IMAGE_VERSION` in `flash.sh`, currently `v8`) into `images/`, verifies the checksums from the
release and unpacks it. An interrupted download resumes on the next run.

Choose another image version with an environment variable:

```bash
F83W_IMAGE_VERSION=v9 ./flash.sh
```

## The seven steps

| Step | What happens                                                  | Your task                                          |
|------|---------------------------------------------------------------|----------------------------------------------------|
| 1    | Check and install tools, download the image, checksums        | confirm the Homebrew installation if asked         |
| 2    | Detect and check the tablet (device, hardware, firmware, battery) | enable developer options and USB debugging, confirm the prompt |
| 3    | Unlock the bootloader – **wipes all data**                    | enable OEM unlocking, confirm unlocking            |
| 4    | Flash the system                                              | –                                                  |
| 5    | First boot, takes 3–5 minutes                                 | wait                                               |
| 6    | LineageOS setup wizard                                        | language, Wi-Fi, date and time                     |
| 7    | Home Assistant                                                | choose server, sign in, choose dashboard           |

### Step 2: prepare the tablet

On the tablet with factory firmware:

1. Click through the setup up to the home screen (you can skip Wi-Fi and the Google account).
2. **Settings → About tablet** → tap **Build number** 7 times.
3. **Settings → System → Developer options** → turn on **USB debugging**.
4. Connect the tablet to the Mac with a data cable and confirm the "Allow USB debugging?" prompt.

> [!IMPORTANT]
> Only one Android device may be connected to the Mac, otherwise the script stops.

### Steps 3 and 4: unlock and flash

The script reboots the tablet into the bootloader and unlocks it with `fastboot oem unlock`. If the macOS `fastboot`
does not see the Allwinner bootloader, it tries direct USB access via libusb (`tools/fastboot_usb.py`). For that it
installs `libusb` if needed and creates a Python environment with `pyusb` in `.venv/`. If that fails too, it shows the
one-time detour via a Windows PC, see [Troubleshooting](troubleshooting.md#bootloader-not-reachable-from-the-mac).

Then, in `fastbootd`, it flashes an empty `vbmeta` (verification off), removes the `product` partition to make room,
writes the system into the active slot and wipes the data partition.

### Step 7: Home Assistant

Sign in to the app with the user the wall display should use. The watchdog then sets the current Wi-Fi as home Wi-Fi
and the persistent connection and restarts the app once. Finally choose the dashboard in the app.

## Logs

Every run writes a log to `logs/flash-<date>.log`, plus the device properties (`getprop`) and, at the end, the
watchdog logs from the tablet.
