---
title: Überblick
description: Flash-Kit, das ein Weelikeit F83W mit LineageOS 20 und fest eingebauter Home-Assistant-App zu einem schlanken Wanddisplay macht.
order: 0
section: Einstieg
---

Das **Weelikeit F83W** ist ein günstiges 8-Zoll-Tablet mit Allwinner A133. Mit diesem Kit wird es zu einem
Wanddisplay für Home Assistant: Ein einziges Skript entsperrt den Bootloader, flasht ein angepasstes LineageOS und
führt durch die Einrichtung. Danach startet das Tablet direkt in die Home-Assistant-App, im Vollbild, ohne
Sperrbildschirm und mit dauerhaft eingeschaltetem Display.

Wie das Projekt entstanden ist – Bootloader, Bootschleife, Lagesensor, Kiosk – erzählt der Artikel
[How I Turned Four Cheap Android Tablets into Rock-Solid Home Assistant Wall Panels](https://medium.com/@marco.starker/how-i-turned-four-cheap-android-tablets-into-rock-solid-home-assistant-wall-panels-6e24d7c8c7ba)
auf Medium (Englisch).

## Was das Image mitbringt

- **LineageOS 20** (Android 13) als GSI `a64_bvS` von AndyYan, angepasst für das F83W
- **Querformat** als Grundausrichtung, Lagesensor korrigiert, keine Navigationsleiste
- **Home-Assistant-App fest eingebaut**, als Startbildschirm, im Vollbild, mit allen Rechten. Es ist die
  „minimal“-Variante ohne Google-Dienste.
- **Schlank:** rund 30 überflüssige Apps entfernt, keine Animationen, kein Sperrbildschirm, Display bleibt am
  Netzteil an
- **Hersteller-Apps ausgeblendet**, sonst hängt das GSI in einer Bootschleife
- **Wächter:** hält die App im Vordergrund, trägt nach der Anmeldung Heim-WLAN und dauerhafte Verbindung ein und
  startet die App jede Nacht um 04:00 neu

Die Einzelheiten stehen unter [Konfiguration](configuration.md).

## Kompatibilität

| Was              | Getestet mit                                         |
|------------------|------------------------------------------------------|
| Gerät            | Weelikeit F83W, Allwinner A133 (`sun50iw10p1`)       |
| Werksfirmware    | `weelikeit_F83W_V01_20240111`, Vendor-Build `20231212` |
| Rechner          | Mac mit Apple Silicon oder Intel                     |
| Image            | `lineage-20-a64_bvS-f83w-v8`                         |

Das Skript prüft Gerät und Vendor-Build und fragt nach, bevor es auf einem anderen Stand weitermacht.

> [!CAUTION]
> Auf eigenes Risiko. Das Entsperren des Bootloaders löscht alle Daten und kann die Garantie kosten. Eine Sicherung
> der Werksfirmware gibt es nicht: Das Tablet lässt sich danach nicht ohne Weiteres auf den Auslieferungszustand
> zurücksetzen.

## Status

Image-Version 8 von November 2026. Das Image baut GitHub Actions aus dem Original-GSI und den Änderungen in
`src/` und veröffentlicht es als Release, siehe [Image bauen](build.md).

## Credits

- [LineageOS](https://lineageos.org): Android-Basis
- [AndyYan](https://sourceforge.net/projects/andyyan-gsi/): LineageOS-20-GSI `a64_bvS`, auf dem das Image aufbaut
- [TrebleDroid / phhusson](https://github.com/TrebleDroid): GSI-Unterbau (`rw-system.sh`, phh-superuser)
- [Home Assistant Companion for Android](https://github.com/home-assistant/android): die App (Apache-2.0),
  unverändert eingebaut
