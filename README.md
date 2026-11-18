# F83W → Home-Assistant-Wanddisplay

Baut ein **Weelikeit F83W** (8″, Allwinner A133, Android 13 Werksfirmware) zu einem
schlanken Wanddisplay für Home Assistant um:

- LineageOS 20 (Android 13) GSI `a64_bvS` von AndyYan, angepasst für das F83W
- Querformat als Grundausrichtung, Lagesensor korrigiert
- Hersteller-Apps ausgeblendet (sie lassen ein GSI sonst in einer Bootschleife hängen)
- rund 30 überflüssige Apps entfernt, keine Animationen, kein Sperrbildschirm,
  Display bleibt am Netzteil an
- **Home-Assistant-App (minimal, ohne Google-Dienste) fest eingebaut** als
  Startbildschirm, im Vollbild, mit allen Rechten
- Wächter: hält die App im Vordergrund, trägt nach dem Anmelden Heim-WLAN und
  dauerhafte Verbindung ein, startet die App täglich um 04:00 neu

Getestet mit Werksfirmware `weelikeit_F83W_V01_20240111` (Vendor-Build `20231212`).

## Download

```bash
git clone https://github.com/DasRed/weelike-f83w-homeassistant-kiosk.git
cd weelike-f83w-homeassistant-kiosk
./flash.sh
```

Das System-Image (~800 MB gepackt, 1,6 GB entpackt) liegt nicht im Repository, sondern im
[GitHub-Release](https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases).
`flash.sh` lädt es beim ersten Start selbst herunter, entpackt es nach `images/` und
prüft die Prüfsumme (`images/SHA256SUMS`).

## Voraussetzungen

- Mac (Apple Silicon oder Intel) – fehlende Werkzeuge installiert das Skript
  selbst über Homebrew (`android-platform-tools`). Nur falls `fastboot` den
  Allwinner-Bootloader nicht erkennt, kommen zusätzlich `libusb` und Python/`pyusb`
  für den Notfallweg dazu.
- **USB-Datenkabel** (reine Ladekabel – z. B. das Apple-Netzteilkabel – reichen nicht)
- Tablet mit mindestens 40 % Akku oder am Netzteil

## Ausführen

Das Skript führt Schritt für Schritt durch, wartet auf Eingaben am Tablet und prüft
selbstständig, wann es weitergehen kann. Bereits erledigte Schritte erkennt es –
nach einem Abbruch einfach neu starten.

| Schritt | Was passiert | Deine Aufgabe |
|---|---|---|
| 1 | Werkzeuge prüfen/installieren, Image laden, Prüfsummen | ggf. Homebrew-Installation bestätigen |
| 2 | Tablet erkennen und prüfen | Entwickleroptionen + USB-Debugging an, Abfrage bestätigen |
| 3 | Bootloader entsperren (**löscht alle Daten**) | OEM-Entsperrung an, Bestätigen |
| 4 | System flashen | – |
| 5 | Erster Start | 3–5 Minuten warten |
| 6 | Lineage-Einrichtungsassistent | Sprache, WLAN, Datum/Zeit |
| 7 | Home Assistant | Server wählen, anmelden, Dashboard wählen |

Protokolle landen in `logs/`.

## Home Assistant

Die App bringt keine Schalter mit, sondern Sensoren und Befehle. Helligkeit setzen:

```yaml
action: notify.mobile_app_<geraet>
data:
  message: command_screen_brightness_level
  data:
    command: 120   # 0..255
```

Als Regler über ein Template-`number` (in der App den Sensor *Bildschirmhelligkeit*
aktivieren, damit der Regler den aktuellen Wert zeigt):

```yaml
template:
  - number:
      - name: "F83W Bildschirmhelligkeit"
        unique_id: f83w_bildschirmhelligkeit
        min: 0
        max: 255
        step: 1
        state: "{{ states('sensor.<geraet>_bildschirmhelligkeit') | int(0) }}"
        set_value:
          - action: notify.mobile_app_<geraet>
            data:
              message: command_screen_brightness_level
              data:
                command: "{{ value | int }}"
```

## Fehlerbehebung

- **Tablet startet nicht / hängt:** Tablet aus, **Lauter + Power** gedrückt halten,
  bis das Recovery-Menü erscheint → `Enter fastboot` → `./flash.sh` neu starten.
- **Bootloader vom Mac nicht erreichbar:** Das Skript versucht zuerst `fastboot`, dann
  direkten USB-Zugriff über libusb (`tools/fastboot_usb.py`). Klappt beides nicht,
  zeigt es den einmaligen Umweg über einen Windows-PC an.
- **Android-Einstellungen:** Statusleiste vom oberen Rand herunterwischen → Zahnrad,
  oder `adb shell am start -a android.settings.SETTINGS`. Nach 10 Minuten holt der
  Wächter Home Assistant zurück.
- **Logs vom Tablet:** `adb logcat -d -s f83w f83w-watchdog`

## Aufbau

```
flash.sh                      Hauptskript
images/                       leeres vbmeta, SHA256SUMS (System-Image kommt aus dem Release)
tools/fastboot_usb.py         Fastboot über libusb (für den Allwinner-Bootloader am Mac)
src/                          alle Änderungen gegenüber dem Original-GSI
  system/bin/f83w-boot.sh       Standardeinstellungen, Rechte, Startbildschirm
  system/bin/f83w-watchdog.sh   Wächter
  system/bin/rw-system.sh.patch Bind-Mounts (Hersteller-Apps, Lagesensor) + Navigationsleiste
  system/etc/init/f83w.rc       Startet Skripte/Wächter
  system/etc/sysconfig/f83w.xml App von Akku-/Datensparen ausnehmen
  system/etc/f83w/gsensor.cfg   korrigierte Sensorachsen (Eintrag "msa")
  product/build.prop.append     Displayausrichtung, Navigationsleiste
  removed-apps.txt              entfernte Apps
```

Zusätzlich im Image: Home-Assistant-App unter `/system/app/HomeAssistant`
(mit entpackten `armeabi-v7a`-Bibliotheken), leerer Ordner `/system/etc/hide-vendor-app`,
ext4-Deduplizierung (`shared_blocks`) entfernt.

## Credits

- [LineageOS](https://lineageos.org) – Android-Basis
- [AndyYan](https://sourceforge.net/projects/andyyan-gsi/) – LineageOS-20-GSI `a64_bvS`, auf dem das Image aufbaut
- [TrebleDroid / phhusson](https://github.com/TrebleDroid) – GSI-Unterbau (`rw-system.sh`, phh-superuser)
- [Home Assistant Companion for Android](https://github.com/home-assistant/android) – App (Apache-2.0), unverändert eingebaut

## Haftung

Auf eigenes Risiko. Das Entsperren des Bootloaders löscht alle Daten und kann die
Garantie kosten. Eine Sicherung der Werksfirmware gibt es nicht – das Tablet lässt sich
danach nicht ohne Weiteres auf den Auslieferungszustand zurücksetzen.
