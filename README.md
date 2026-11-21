# F83W → Home Assistant wall panel

Turns a **Weelikeit F83W** (8″, Allwinner A133, stock Android 13) into a slim
wall panel for Home Assistant:

- LineageOS 20 (Android 13) GSI `a64_bvS` by AndyYan, adapted for the F83W
- Landscape as the default orientation, accelerometer axes fixed
- Vendor apps hidden (otherwise they keep a GSI in a boot loop)
- About 30 unneeded apps removed, no animations, no lock screen,
  screen stays on while powered
- **Home Assistant app (minimal, without Google services) built in** as the
  home app, full screen, with all permissions
- Watchdog: keeps the app in the foreground, sets the home Wi-Fi and the
  persistent connection after login, restarts the app every day at 04:00

Tested with stock firmware `weelikeit_F83W_V01_20240111` (vendor build `20231212`).

The story behind it – bootloader unlock, boot loop, accelerometer, kiosk – is told in the
article [How I Turned Four Cheap Android Tablets into Rock-Solid Home Assistant Wall Panels](https://medium.com/@marco.starker/how-i-turned-four-cheap-android-tablets-into-rock-solid-home-assistant-wall-panels-6e24d7c8c7ba)
on Medium.

## Download

```bash
git clone https://github.com/DasRed/weelike-f83w-homeassistant-kiosk.git
cd weelike-f83w-homeassistant-kiosk
./flash.sh
```

The system image is not stored in the repository. GitHub Actions builds it from the
original GSI and `src/` and publishes it as a [release](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases)
(`lineage-20-a64_bvS-f83w-<version>.img.xz`, about 650 MB, 1.6 GB unpacked). On the first
run, `flash.sh` downloads the configured version (`IMAGE_VERSION`, currently `v8`),
verifies the checksums and unpacks it into `images/`. To use another version:
`F83W_IMAGE_VERSION=v9 ./flash.sh`.

## Requirements

- Mac (Apple Silicon or Intel) with `python3` (Xcode Command Line Tools) – the script
  installs missing tools itself via Homebrew (`android-platform-tools`, `xz`). Only if
  `fastboot` does not detect the Allwinner bootloader, `libusb` and Python/`pyusb` are
  added for the fallback.
- **USB data cable** (charge-only cables – e.g. the Apple power adapter cable – won't work)
- Tablet with at least 40 % battery or connected to a charger

## Running

The script guides you step by step, waits for input on the tablet and checks by itself
when it can continue. It detects steps that are already done – after an interruption,
simply start it again.

| Step | What happens | Your part |
|---|---|---|
| 1 | Check/install tools, download image, verify checksums | confirm the Homebrew installation if asked |
| 2 | Detect and check the tablet | turn on developer options + USB debugging, confirm the prompt |
| 3 | Unlock the bootloader (**erases all data**) | turn on OEM unlocking, confirm |
| 4 | Flash the system | – |
| 5 | First boot | wait 3–5 minutes |
| 6 | LineageOS setup wizard | language, Wi-Fi, date/time |
| 7 | Home Assistant | choose server, log in, choose dashboard |

Logs are written to `logs/`.

## Home Assistant

The app does not provide switches but sensors and commands. Set the brightness:

```yaml
action: notify.mobile_app_<device>
data:
  message: command_screen_brightness_level
  data:
    command: 120   # 0..255
```

As a slider via a template `number` (enable the *Screen brightness* sensor in the app
so the slider shows the current value):

```yaml
template:
  - number:
      - name: "F83W screen brightness"
        unique_id: f83w_screen_brightness
        min: 0
        max: 255
        step: 1
        state: "{{ states('sensor.<device>_screen_brightness') | int(0) }}"
        set_value:
          - action: notify.mobile_app_<device>
            data:
              message: command_screen_brightness_level
              data:
                command: "{{ value | int }}"
```

## Troubleshooting

- **Tablet doesn't boot / hangs:** turn the tablet off, hold **Volume Up + Power**
  until the recovery menu appears → `Enter fastboot` → start `./flash.sh` again.
- **Bootloader not reachable from the Mac:** the script first tries `fastboot`, then
  direct USB access via libusb (`tools/fastboot_usb.py`). If both fail, it shows the
  one-time workaround via a Windows PC.
- **Android settings:** swipe down the status bar from the top edge → gear icon,
  or `adb shell am start -a android.settings.SETTINGS`. After 10 minutes the
  watchdog brings Home Assistant back.
- **Logs from the tablet:** `adb logcat -d -s f83w f83w-watchdog`

## Structure

```
flash.sh                      main script
images/                       blank vbmeta, SHA256SUMS (the system image is downloaded here)
tools/fastboot_usb.py         fastboot via libusb (for the Allwinner bootloader on the Mac)
tools/build_image.py          builds the system image (runs in GitHub Actions)
build/sources.json            original GSI and Home Assistant app with version and SHA-256
.github/workflows/            "Build image" workflow
src/                          all changes compared to the original GSI
  system-files.txt              target path, mode, owner and SELinux label per file
  system/bin/f83w-boot.sh       defaults, permissions, home app
  system/bin/f83w-watchdog.sh   watchdog
  system/bin/rw-system.sh.patch bind mounts (vendor apps, accelerometer) + navigation bar
  system/etc/init/f83w.rc       starts the scripts/watchdog
  system/etc/sysconfig/f83w.xml exempts the app from battery/data saver
  system/etc/f83w/gsensor.cfg   corrected sensor axes (entry "msa")
  product/build.prop.append     display orientation, navigation bar
  removed-apps.txt              removed apps
```

Also in the image: the Home Assistant app in `/system/app/HomeAssistant`
(with extracted `armeabi-v7a` libraries), ext4 deduplication (`shared_blocks`) removed.

## Building the image

`tools/build_image.py` builds the image without root and without loop mounts: download
GSI and app (checksums from `build/sources.json`), grow the ext4 image and resolve
`shared_blocks`, use `debugfs` to remove apps, write files including SELinux labels,
patch `rw-system.sh` and extend `build.prop`, then check and shrink the file system.
Requires Linux with `e2fsprogs`, `patch` and `xz`:

```bash
python3 tools/build_image.py --version v9 --xz   # output in out/
```

The **Build image** workflow runs automatically:

- **Pull request** that changes `src/`, `build/` or the build script: builds the image and
  keeps it as an artifact for 3 days
- **Push a `v*` tag** (e.g. `git tag v9 && git push origin v9`): builds the image and
  publishes it as a release; then bump `IMAGE_VERSION` in `flash.sh`
- **Manually** (Actions → Build image → Run workflow): with or without a release

New Home Assistant version: update `version`, `url` and `sha256` in `build/sources.json`.

## Credits

- [LineageOS](https://lineageos.org) – Android base
- [AndyYan](https://sourceforge.net/projects/andyyan-gsi/) – LineageOS 20 GSI `a64_bvS` the image is based on
- [TrebleDroid / phhusson](https://github.com/TrebleDroid) – GSI foundation (`rw-system.sh`, phh superuser)
- [Home Assistant Companion for Android](https://github.com/home-assistant/android) – app (Apache-2.0), included unmodified

## Disclaimer

Use at your own risk. Unlocking the bootloader erases all data and may void the
warranty. There is no backup of the stock firmware – the tablet cannot easily be
restored to its factory state afterwards.
