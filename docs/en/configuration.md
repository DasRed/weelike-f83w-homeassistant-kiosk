---
title: Configuration
description: What the image changes compared to the original GSI – default settings, app permissions, watchdog, removed apps and the files in src/.
order: 20
slug: configuration
section: Details
---

All changes compared to the original GSI live in the
[`src/`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/tree/main/src) folder. [Building the image](build.md)
puts them into the system. This page explains what they do.

## Default settings

On the first boot `f83w-boot.sh` sets these values once. If you change them later in Android, your values stay.

| Setting                              | Value    | Effect                                         |
|--------------------------------------|----------|------------------------------------------------|
| `stay_on_while_plugged_in`           | `7`      | display stays on while powered                 |
| `screen_off_timeout`                 | maximum  | no switch-off after a timeout                  |
| `screen_brightness_mode`             | `0`      | no automatic brightness                        |
| Screen saver                         | off      | not when docked or sleeping either             |
| Animations (window, transition, duration) | `0` | no animations                                  |
| Lock screen                          | off      | straight into the app                          |

Built into the image as well: landscape as the base orientation (`ro.surface_flinger.primary_display_orientation`)
and no navigation bar (`qemu.hw.mainkeys=1`).

## Home Assistant app

Once the initial setup is done, the image configures the app `io.homeassistant.companion.android.minimal` on every
boot:

- **Permissions:** notifications, location (including background), Bluetooth, phone state, camera, microphone and
  activity recognition, so the app's sensors work without prompts
- **Special permissions:** modify system settings (for brightness), display over other apps (for `command_webview`
  and `command_launch_app`), run in the background
- **Battery:** exempt from battery and data saving
- **Home screen:** the app is the home activity
- **App settings:** full screen and "keep screen on" are preset as long as you do not change them in the app

## Watchdog

`f83w-watchdog.sh` runs as a service with root rights and only becomes active after the initial setup.

| Value        | Default | Meaning                                                            |
|--------------|---------|--------------------------------------------------------------------|
| `INTERVAL`   | `30`    | seconds between two checks                                         |
| `GRACE`      | `600`   | seconds another app may stay in front (e.g. settings)              |
| `RESTART_AT` | `400`   | time of the nightly app restart as HMM, i.e. 04:00                 |

What it does:

- **Foreground:** if another app has been in front for more than 10 minutes, it brings Home Assistant back. While the
  display is off, it brings nothing back.
- **Nightly restart:** at 04:00 it restarts the app once, against a hanging or white WebView.
- **Server settings:** after sign-in it sets the persistent connection to "always" for each server and enters the
  currently connected Wi-Fi as home Wi-Fi if none is set yet. Without Google services the app needs the persistent
  connection so commands from Home Assistant arrive.

> [!NOTE]
> The values are fixed in the script inside the image. Changing them needs a new image, see
> [Building the image](build.md).

## Removed and hidden apps

About 30 apps of the GSI are removed, among them camera, gallery, clock, calendar, calculator, browser, music,
contacts, phone, messaging, NFC and live wallpapers. The full list is in
[`src/removed-apps.txt`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/src/removed-apps.txt).

The image hides the vendor apps from `/vendor/app` on boot. Their signature does not match the GSI, and they would
send the system server into a boot loop.

## Files in src/

| File                            | Contents                                                         |
|---------------------------------|------------------------------------------------------------------|
| `system-files.txt`              | target path, mode, owner and SELinux label per file in the image |
| `system/bin/f83w-boot.sh`       | default settings, app permissions, home screen                   |
| `system/bin/f83w-watchdog.sh`   | watchdog                                                         |
| `system/bin/rw-system.sh.patch` | hide vendor apps, orientation sensor, navigation bar             |
| `system/etc/init/f83w.rc`       | starts the boot script and the watchdog after boot               |
| `system/etc/sysconfig/f83w.xml` | exempts the app from battery and data saving                     |
| `system/etc/f83w/gsensor.cfg`   | corrected axes of the orientation sensor (entry `msa`)           |
| `product/build.prop.append`     | display orientation, navigation bar                              |
| `removed-apps.txt`              | removed apps                                                     |

Also in the image: the app under `/system/app/HomeAssistant` with extracted `armeabi-v7a` libraries, an empty folder
`/system/etc/hide-vendor-app` and an ext4 file system without deduplication (`shared_blocks`). The app version that is
built in is set in
[`build/sources.json`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/build/sources.json).
