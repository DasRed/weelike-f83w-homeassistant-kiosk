# weelike-f83w-homeassistant-kiosk

Flash kit that turns a **Weelikeit F83W** (8″, Allwinner A133, stock Android 13) into a slim wall panel for Home
Assistant: LineageOS 20 GSI adapted for the F83W, landscape, no lock screen, screen always on while powered and the
Home Assistant app (minimal, without Google services) built in as the full-screen home app.

Documentation: https://www.marco-starker.de/en/projects/weelike-f83w-homeassistant-kiosk/docs
(Deutsch: https://www.marco-starker.de/de/projekte/weelike-f83w-homeassistant-kiosk/doku)

The story behind it is told in the article
[How I Turned Four Cheap Android Tablets into Rock-Solid Home Assistant Wall Panels](https://medium.com/@marco.starker/how-i-turned-four-cheap-android-tablets-into-rock-solid-home-assistant-wall-panels-6e24d7c8c7ba)
on Medium.

> [!CAUTION]
> Use at your own risk. Unlocking the bootloader erases all data and may void the warranty. There is no backup of
> the stock firmware.

## Quick start

Requires a Mac with `python3` (Xcode Command Line Tools), a USB data cable and the tablet at 40 % battery or on its
charger. Missing tools (`adb`, `fastboot`, `xz`) are installed through Homebrew.

```bash
git clone https://github.com/DasRed/weelike-f83w-homeassistant-kiosk.git
cd weelike-f83w-homeassistant-kiosk
./flash.sh
```

The script downloads the system image from the [releases](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases)
(about 650 MB), verifies it and guides through seven steps: tools and image, connect the tablet, unlock the
bootloader, flash, first boot, LineageOS setup and Home Assistant login. It can be restarted at any time and skips
steps that are already done.

Tested with stock firmware `weelikeit_F83W_V01_20240111` (vendor build `20231212`).

The image is built by GitHub Actions from the original GSI and `src/` (`tools/build_image.py`), see the documentation.

## Credits

- [LineageOS](https://lineageos.org) – Android base
- [AndyYan](https://sourceforge.net/projects/andyyan-gsi/) – LineageOS 20 GSI `a64_bvS` the image is based on
- [TrebleDroid / phhusson](https://github.com/TrebleDroid) – GSI foundation (`rw-system.sh`, phh superuser)
- [Home Assistant Companion for Android](https://github.com/home-assistant/android) – app (Apache-2.0), included
  unmodified

## License

The scripts and files in this repository are licensed under [MIT](LICENSE). The system images published as releases
contain third-party software that keeps its own licenses (see Credits).
