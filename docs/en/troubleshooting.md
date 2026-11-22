---
title: Troubleshooting
description: What to do if the F83W does not boot, the bootloader is not reachable from the Mac or Home Assistant does not stay in front.
order: 40
slug: troubleshooting
section: Details
---

## Tablet does not boot or hangs

1. Switch the tablet off.
2. Hold **Volume up + Power** until the recovery menu appears.
3. Choose **Enter fastboot**.
4. Start `./flash.sh` again. The script continues where needed.

## Bootloader not reachable from the Mac

The script first tries `fastboot` and then direct USB access via libusb. If both fail, there is a one-time detour via
a Windows PC:

1. Download the Google Platform Tools and the Google USB Driver from developer.android.com.
2. The tablet is in the bootloader (green robot). In Device Manager: **USB Developer** → update driver →
   `android_winusb.inf` → **Android Bootloader Interface**.
3. Unlock and reboot:

```powershell
.\fastboot oem unlock
.\fastboot reboot
```

Then plug the cable back into the Mac and continue in the script with Enter.

## fastbootd not reachable

If the script reports in step 4 that `fastbootd` is not reachable: switch the tablet off, **Volume up + Power** →
recovery → **Enter fastboot**, then start the script again.

## Download or checksum

- **Release not found:** the version in `F83W_IMAGE_VERSION` or `IMAGE_VERSION` does not exist as a release. Check
  the versions under [Releases](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases).
- **Download interrupted:** start the script again, the download resumes.
- **Checksum of the download does not match:** the script deletes the file. Start it again and it downloads the image
  once more.
- **Checksum of the unpacked image does not match:** delete the image files in `images/` (`lineage-*.img`,
  `lineage-*.img.xz`) and start the script again.

## Home Wi-Fi is not set

The watchdog enters the Wi-Fi the tablet is connected to at sign-in. If it was not connected, or the Wi-Fi name
contains quotes or backslashes, the entry stays empty. Then set the home Wi-Fi yourself in the app's server settings.

## Home Assistant does not stay in front

The watchdog deliberately allows other apps for 10 minutes so you can change settings. After that it brings the app
back. While the display is off it does not step in. Its log shows what it does:

```bash
adb logcat -d -s f83w-watchdog
```
