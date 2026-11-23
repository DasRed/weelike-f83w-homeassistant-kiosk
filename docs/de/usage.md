---
title: Verwendung
description: Das F83W-Wanddisplay aus Home Assistant steuern, mit Helligkeit per Befehl und als Regler, weiteren Befehlen, Android-Einstellungen und Logs vom Tablet.
order: 30
slug: verwendung
section: Details
---

Im Alltag ist das Tablet einfach ein Dashboard. Gesteuert wird es aus Home Assistant über die Companion-App: Sie
bringt keine Schalter mit, sondern Sensoren und Befehle per Benachrichtigung.

## Helligkeit setzen

```yaml
action: notify.mobile_app_<geraet>
data:
  message: command_screen_brightness_level
  data:
    command: 120   # 0..255
```

`<geraet>` ist der Name, unter dem das Tablet in Home Assistant angemeldet ist, z. B. `f83w_flur`.

## Helligkeit als Regler

Mit einer Template-Zahl bekommst du einen Regler im Dashboard. Damit er den aktuellen Wert zeigt, aktivierst du in
der App den Sensor **Bildschirmhelligkeit**.

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

> [!TIP]
> Die Entity-ID des Sensors hängt von der Sprache deines Home Assistant ab, auf Englisch etwa
> `…_screen_brightness`.
> Mit einer Automation dimmst du das Display nachts automatisch, etwa um 22:00 auf 20 und um 6:30 zurück auf 150.

## Weitere Befehle

Weil das Image der App die nötigen Rechte gibt, funktionieren auch die Befehle, die über anderen Apps einblenden,
etwa `command_webview` (eine bestimmte Ansicht öffnen) und `command_launch_app`. Die vollständige Liste steht in der
[Doku der Companion-App](https://companion.home-assistant.io/docs/notifications/notification-commands).

## Android-Einstellungen öffnen

Die Statusleiste vom oberen Rand herunterwischen und auf das Zahnrad tippen. Vom Mac aus geht es auch per `adb`:

```bash
adb shell am start -a android.settings.SETTINGS
```

Nach 10 Minuten holt der Wächter Home Assistant wieder nach vorne.

## Logs vom Tablet

```bash
adb logcat -d -s f83w f83w-watchdog
```

`f83w` sind die Meldungen des Boot-Skripts, `f83w-watchdog` die des Wächters.
