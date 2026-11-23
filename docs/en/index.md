---
title: Overview
description: Flash kit that turns a Weelikeit F83W into a lean Home Assistant wall display with LineageOS 20 and a built-in Home Assistant app. Features and compatibility.
order: 0
section: Getting started
---

The **Weelikeit F83W** is an inexpensive 8-inch tablet with an Allwinner A133. This kit turns it into a wall display
for Home Assistant: a single script unlocks the bootloader, flashes a customised LineageOS and guides you through the
setup. Afterwards the tablet boots straight into the Home Assistant app, full screen, without a lock screen and with
the display always on.

The story behind it – bootloader unlock, boot loop, orientation sensor, kiosk – is told in the article
[How I Turned Four Cheap Android Tablets into Rock-Solid Home Assistant Wall Panels](https://medium.com/@marco.starker/how-i-turned-four-cheap-android-tablets-into-rock-solid-home-assistant-wall-panels-6e24d7c8c7ba)
on Medium.

## What the image brings

- **LineageOS 20** (Android 13) as AndyYan's GSI `a64_bvS`, adapted for the F83W
- **Landscape** as the base orientation, orientation sensor corrected, no navigation bar
- **Home Assistant app built in** as the home screen, full screen, with all permissions. It is the "minimal" flavour
  without Google services.
- **Lean:** about 30 unneeded apps removed, no animations, no lock screen, display stays on while powered
- **Vendor apps hidden**, otherwise the GSI ends up in a boot loop
- **Watchdog:** keeps the app in the foreground, sets home Wi-Fi and the persistent connection after sign-in and
  restarts the app every night at 04:00

The details are under [Configuration](configuration.md).

## Compatibility

| What              | Tested with                                           |
|-------------------|-------------------------------------------------------|
| Device            | Weelikeit F83W, Allwinner A133 (`sun50iw10p1`)        |
| Factory firmware  | `weelikeit_F83W_V01_20240111`, vendor build `20231212` |
| Computer          | Mac with Apple Silicon or Intel                       |
| Image             | `lineage-20-a64_bvS-f83w-v8`                          |

The script checks device and vendor build and asks before it continues on a different version.

> [!CAUTION]
> At your own risk. Unlocking the bootloader wipes all data and may void the warranty. There is no backup of the
> factory firmware: the tablet cannot easily be returned to its original state afterwards.

## Status

Image version 8 from November 2026. GitHub Actions builds the image from the original GSI and the changes in
`src/` and publishes it as a release, see [Building the image](build.md).

## Credits

- [LineageOS](https://lineageos.org): Android base
- [AndyYan](https://sourceforge.net/projects/andyyan-gsi/): LineageOS 20 GSI `a64_bvS` the image is built on
- [TrebleDroid / phhusson](https://github.com/TrebleDroid): GSI foundation (`rw-system.sh`, phh-superuser)
- [Home Assistant Companion for Android](https://github.com/home-assistant/android): the app (Apache-2.0), built in
  unchanged
