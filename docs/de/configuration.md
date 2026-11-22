---
title: Konfiguration
description: Was das Image gegenüber dem Original-GSI ändert – Grundeinstellungen, Rechte der App, Wächter, entfernte Apps und die Dateien in src/.
order: 20
slug: konfiguration
section: Details
---

Alle Änderungen gegenüber dem Original-GSI liegen im Ordner
[`src/`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/tree/main/src). Beim [Bauen des Images](build.md)
kommen sie fest ins System. Diese Seite erklärt, was sie bewirken.

## Grundeinstellungen

Beim ersten Start setzt `f83w-boot.sh` einmalig diese Werte. Änderst du sie später in Android, bleiben deine Werte
erhalten.

| Einstellung                    | Wert             | Wirkung                                      |
|--------------------------------|------------------|----------------------------------------------|
| `stay_on_while_plugged_in`     | `7`              | Display bleibt an, solange Strom anliegt     |
| `screen_off_timeout`           | Maximum          | kein Ausschalten nach Zeit                   |
| `screen_brightness_mode`       | `0`              | keine automatische Helligkeit                |
| Bildschirmschoner              | aus              | auch nicht am Dock oder beim Ruhezustand     |
| Animationen (Fenster, Übergänge, Dauer) | `0`     | keine Animationen                            |
| Sperrbildschirm                | aus              | direkt in die App                            |

Dazu kommen fest im Image: Querformat als Grundausrichtung (`ro.surface_flinger.primary_display_orientation`) und
keine Navigationsleiste (`qemu.hw.mainkeys=1`).

## Home-Assistant-App

Nach abgeschlossener Ersteinrichtung richtet das Image die App `io.homeassistant.companion.android.minimal` bei jedem
Start ein:

- **Rechte:** Benachrichtigungen, Standort (auch im Hintergrund), Bluetooth, Telefonstatus, Kamera, Mikrofon und
  Aktivitätserkennung, damit die Sensoren der App ohne Rückfrage funktionieren
- **Sonderrechte:** Systemeinstellungen ändern (für die Helligkeit), Einblenden über anderen Apps (für
  `command_webview` und `command_launch_app`), Ausführen im Hintergrund
- **Akku:** von Akku- und Datensparmaßnahmen ausgenommen
- **Startbildschirm:** die App ist die Home-Activity
- **App-Einstellungen:** Vollbild und „Bildschirm anlassen“ sind vorbelegt, solange du sie in der App nicht selbst
  änderst

## Wächter

`f83w-watchdog.sh` läuft als Dienst mit Root-Rechten und wird erst nach der Ersteinrichtung aktiv.

| Wert         | Standard | Bedeutung                                                         |
|--------------|----------|-------------------------------------------------------------------|
| `INTERVAL`   | `30`     | Sekunden zwischen zwei Prüfungen                                   |
| `GRACE`      | `600`    | Sekunden, die eine andere App vorne sein darf (z. B. Einstellungen) |
| `RESTART_AT` | `400`    | Uhrzeit des nächtlichen App-Neustarts als HMM, also 04:00          |

Was er tut:

- **Vordergrund:** Ist länger als 10 Minuten eine andere App vorne, holt er Home Assistant zurück. Bei
  ausgeschaltetem Display holt er nichts zurück.
- **Nächtlicher Neustart:** Um 04:00 startet er die App einmal neu, gegen eine hängende oder weiße WebView.
- **Server-Einstellungen:** Nach der Anmeldung setzt er je Server die dauerhafte Verbindung auf „immer“ und trägt das
  aktuell verbundene WLAN als Heim-WLAN ein, falls noch keins gesetzt ist. Ohne Google-Dienste braucht die App die
  dauerhafte Verbindung, damit Befehle aus Home Assistant ankommen.

> [!NOTE]
> Die Werte stehen fest im Skript im Image. Ändern lassen sie sich nur über ein neues Image, siehe
> [Image bauen](build.md).

## Entfernte und ausgeblendete Apps

Rund 30 Apps des GSI sind entfernt, darunter Kamera, Galerie, Uhr, Kalender, Taschenrechner, Browser, Musik,
Kontakte, Telefon, Nachrichten, NFC und Live-Hintergründe. Die vollständige Liste steht in
[`src/removed-apps.txt`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/src/removed-apps.txt).

Die Hersteller-Apps aus `/vendor/app` blendet das Image beim Start aus. Ihre Signatur passt nicht zum GSI, und sie
würden den Systemdienst in eine Bootschleife schicken.

## Dateien in src/

| Datei                              | Inhalt                                                           |
|------------------------------------|------------------------------------------------------------------|
| `system-files.txt`                 | Zielpfad, Rechte, Besitzer und SELinux-Label je Datei im Image   |
| `system/bin/f83w-boot.sh`          | Grundeinstellungen, Rechte der App, Startbildschirm              |
| `system/bin/f83w-watchdog.sh`      | Wächter                                                          |
| `system/bin/rw-system.sh.patch`    | Hersteller-Apps ausblenden, Lagesensor, Navigationsleiste        |
| `system/etc/init/f83w.rc`          | startet Boot-Skript und Wächter nach dem Systemstart             |
| `system/etc/sysconfig/f83w.xml`    | nimmt die App von Akku- und Datensparen aus                      |
| `system/etc/f83w/gsensor.cfg`      | korrigierte Achsen des Lagesensors (Eintrag `msa`)               |
| `product/build.prop.append`        | Displayausrichtung, Navigationsleiste                            |
| `removed-apps.txt`                 | entfernte Apps                                                   |

Zusätzlich im Image: die App unter `/system/app/HomeAssistant` mit entpackten `armeabi-v7a`-Bibliotheken, ein
leerer Ordner `/system/etc/hide-vendor-app` und ein ext4-Dateisystem ohne Deduplizierung (`shared_blocks`). Welche
Version der App eingebaut wird, steht in
[`build/sources.json`](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/blob/main/build/sources.json).
