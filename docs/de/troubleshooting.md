---
title: Fehlerbehebung
description: Was tun, wenn das F83W nicht startet, der Bootloader vom Mac nicht erreichbar ist oder Home Assistant nicht vorne bleibt.
order: 40
slug: fehlerbehebung
section: Details
---

## Tablet startet nicht oder hängt

1. Tablet ausschalten.
2. **Lauter + Power** gedrückt halten, bis das Recovery-Menü erscheint.
3. **Enter fastboot** wählen.
4. `./flash.sh` neu starten. Das Skript macht dort weiter, wo es nötig ist.

## Bootloader vom Mac nicht erreichbar

Das Skript versucht zuerst `fastboot` und dann den direkten USB-Zugriff über libusb. Klappt beides nicht, geht es
einmalig über einen Windows-PC:

1. Google Platform Tools und den Google USB Driver von developer.android.com laden.
2. Das Tablet steht im Bootloader (grünes Männchen). Im Geräte-Manager **USB Developer** → Treiber aktualisieren →
   `android_winusb.inf` → **Android Bootloader Interface**.
3. Entsperren und neu starten:

```powershell
.\fastboot oem unlock
.\fastboot reboot
```

Danach das Kabel wieder an den Mac und im Skript mit Enter weitermachen.

## fastbootd nicht erreichbar

Meldet das Skript in Schritt 4, dass `fastbootd` nicht erreichbar ist: Tablet aus, **Lauter + Power** → Recovery →
**Enter fastboot**, dann das Skript neu starten.

## Download oder Prüfsumme

- **Release nicht gefunden:** Die Version in `F83W_IMAGE_VERSION` bzw. `IMAGE_VERSION` gibt es nicht als Release.
  Prüf die Versionen unter [Releases](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases).
- **Download abgebrochen:** Skript neu starten, der Download wird fortgesetzt.
- **Prüfsumme des Downloads stimmt nicht:** Das Skript löscht die Datei. Starte es neu, dann lädt es das Image noch
  einmal.
- **Prüfsumme des entpackten Images stimmt nicht:** Lösch die Image-Dateien in `images/`
  (`lineage-*.img`, `lineage-*.img.xz`) und starte das Skript neu.

## Heim-WLAN wird nicht eingetragen

Der Wächter trägt das WLAN ein, mit dem das Tablet bei der Anmeldung verbunden ist. War es nicht verbunden, oder
enthält der WLAN-Name Anführungszeichen oder Backslashes, bleibt der Eintrag leer. Trag das Heim-WLAN dann in der App
unter den Server-Einstellungen selbst ein.

## Home Assistant bleibt nicht im Vordergrund

Der Wächter lässt andere Apps bewusst 10 Minuten lang zu, damit du Einstellungen ändern kannst. Danach holt er die
App zurück. Bei ausgeschaltetem Display greift er nicht ein. Was er tut, zeigt das Log:

```bash
adb logcat -d -s f83w-watchdog
```
