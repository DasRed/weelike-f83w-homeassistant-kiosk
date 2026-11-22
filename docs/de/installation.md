---
title: Installation
description: Voraussetzungen, Download und die sieben Schritte von flash.sh – vom Werkszustand bis zur Anmeldung in Home Assistant.
order: 10
slug: installation
section: Einstieg
---

Alles läuft über ein Skript: `flash.sh`. Es führt Schritt für Schritt durch, wartet auf Eingaben am Tablet und
erkennt selbst, wann es weitergehen kann. Bereits erledigte Schritte überspringt es, nach einem Abbruch startest du es
einfach neu. Die Ausgaben des Skripts sind auf Englisch.

## Voraussetzungen

- **Mac** mit Apple Silicon oder Intel und `python3` (Xcode Command Line Tools: `xcode-select --install`)
- **Homebrew**: Fehlt es, bietet das Skript die Installation an. Darüber kommen `adb` und `fastboot`
  (`android-platform-tools`) sowie `xz` zum Entpacken des Images.
- **USB-Datenkabel**: Reine Ladekabel reichen nicht.
- **Akku** mindestens 40 % oder Tablet am Netzteil
- rund **2,5 GB** freier Platz für das gepackte und das entpackte Image
- Internet: Das Image (rund 650 MB) lädt das Skript beim ersten Start herunter.

## Herunterladen und starten

```bash
git clone https://github.com/DasRed/weelike-f83w-homeassistant-kiosk.git
cd weelike-f83w-homeassistant-kiosk
./flash.sh
```

Das System-Image liegt nicht im Repository. GitHub Actions baut es und veröffentlicht es als
[Release](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases) mit dem Namen
`lineage-20-a64_bvS-f83w-<version>.img.xz` (rund 650 MB, entpackt 1,6 GB). Beim ersten Start lädt das Skript die
eingestellte Version (`IMAGE_VERSION` in `flash.sh`, derzeit `v8`) nach `images/`, prüft die Prüfsummen aus dem
Release und entpackt es. Ein abgebrochener Download wird beim nächsten Start fortgesetzt.

Eine andere Image-Version wählst du über eine Umgebungsvariable:

```bash
F83W_IMAGE_VERSION=v9 ./flash.sh
```

## Die sieben Schritte

| Schritt | Was passiert                                         | Deine Aufgabe                                        |
|---------|------------------------------------------------------|------------------------------------------------------|
| 1       | Werkzeuge prüfen und installieren, Image laden, Prüfsummen | ggf. Homebrew-Installation bestätigen          |
| 2       | Tablet erkennen und prüfen (Gerät, Hardware, Firmware, Akku) | Entwickleroptionen und USB-Debugging an, Abfrage bestätigen |
| 3       | Bootloader entsperren – **löscht alle Daten**        | OEM-Entsperrung an, Entsperren bestätigen            |
| 4       | System flashen                                       | –                                                    |
| 5       | Erster Start, dauert 3–5 Minuten                     | warten                                               |
| 6       | Einrichtungsassistent von LineageOS                  | Sprache, WLAN, Datum und Uhrzeit                     |
| 7       | Home Assistant                                       | Server wählen, anmelden, Dashboard wählen            |

### Schritt 2: Tablet vorbereiten

Auf dem Tablet mit Werksfirmware:

1. Einrichtung bis zum Startbildschirm durchklicken (WLAN und Google-Konto kannst du überspringen).
2. **Einstellungen → Über das Tablet** → 7-mal auf **Build-Nummer** tippen.
3. **Einstellungen → System → Entwickleroptionen** → **USB-Debugging** einschalten.
4. Tablet per Datenkabel an den Mac anschließen und die Abfrage „USB-Debugging zulassen?“ bestätigen.

> [!IMPORTANT]
> Es darf nur ein Android-Gerät am Mac hängen, sonst bricht das Skript ab.

### Schritt 3 und 4: Entsperren und Flashen

Das Skript startet das Tablet in den Bootloader und entsperrt ihn mit `fastboot oem unlock`. Erkennt das
`fastboot` von macOS den Allwinner-Bootloader nicht, versucht es den direkten USB-Zugriff über libusb
(`tools/fastboot_usb.py`). Dafür installiert es bei Bedarf `libusb` und legt eine Python-Umgebung mit `pyusb` in
`.venv/` an. Klappt auch das nicht, zeigt es den einmaligen Umweg über einen Windows-PC, siehe
[Fehlerbehebung](troubleshooting.md#bootloader-vom-mac-nicht-erreichbar).

Danach flasht es im `fastbootd` ein leeres `vbmeta` (Verifizierung aus), entfernt die `product`-Partition, um Platz
zu schaffen, schreibt das System in den aktiven Slot und löscht den Datenbereich.

### Schritt 7: Home Assistant

Melde dich in der App mit dem Benutzer an, den das Wanddisplay nutzen soll. Danach trägt der Wächter das aktuelle
WLAN als Heim-WLAN und die dauerhafte Verbindung ein und startet die App einmal neu. Zum Schluss wählst du in der App
das Dashboard.

## Protokolle

Jeder Lauf schreibt ein Protokoll nach `logs/flash-<datum>.log`. Dazu kommen die Geräte-Eigenschaften
(`getprop`) und am Ende die Logs des Wächters vom Tablet.
