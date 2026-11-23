---
title: Usage
description: Control the F83W wall display from Home Assistant, with brightness as a command and as a slider, more commands, Android settings and logs from the tablet.
order: 30
slug: usage
section: Details
---

In everyday use the tablet is simply a dashboard. It is controlled from Home Assistant through the Companion app: the
app has no switches, but sensors and commands sent as notifications.

## Set the brightness

```yaml
action: notify.mobile_app_<device>
data:
  message: command_screen_brightness_level
  data:
    command: 120   # 0..255
```

`<device>` is the name the tablet is registered with in Home Assistant, e.g. `f83w_hallway`.

## Brightness as a slider

A template number gives you a slider on the dashboard. To show the current value, enable the **Screen brightness**
sensor in the app.

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

> [!TIP]
> The sensor's entity ID depends on the language of your Home Assistant, e.g. `…_bildschirmhelligkeit` in German.
> With an automation you can dim the display at night, e.g. to 20 at 22:00 and back to 150 at 6:30.

## More commands

Because the image grants the app the necessary permissions, commands that display over other apps work too, e.g.
`command_webview` (open a specific view) and `command_launch_app`. The full list is in the
[Companion app docs](https://companion.home-assistant.io/docs/notifications/notification-commands).

## Open the Android settings

Swipe down the status bar from the top edge and tap the gear. From the Mac it also works via `adb`:

```bash
adb shell am start -a android.settings.SETTINGS
```

After 10 minutes the watchdog brings Home Assistant back to the front.

## Logs from the tablet

```bash
adb logcat -d -s f83w f83w-watchdog
```

`f83w` are the messages of the boot script, `f83w-watchdog` those of the watchdog.
