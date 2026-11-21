#!/system/bin/sh
# F83W wall panel: started after every boot by /system/etc/init/f83w.rc
# (context phhsu_daemon, root).
PKG=io.homeassistant.companion.android.minimal
HOME_ACT=$PKG/io.homeassistant.companion.android.launch.LauncherAlias
log() { /system/bin/log -t f83w "$*"; }

# ---------------------------------------------------------------------------
# 1) One-time defaults per data partition (later changes are kept)
# ---------------------------------------------------------------------------
MARK=/data/system/f83w-defaults-v1.done
if [ "$1" != "ha" ] && [ ! -f "$MARK" ]; then
  settings put global stay_on_while_plugged_in 7          # screen stays on while powered
  settings put system screen_off_timeout 2147483647
  settings put system screen_brightness_mode 0             # no adaptive brightness
  settings put secure screensaver_enabled 0
  settings put secure screensaver_activate_on_dock 0
  settings put secure screensaver_activate_on_sleep 0
  settings put global window_animation_scale 0
  settings put global transition_animation_scale 0
  settings put global animator_duration_scale 0
  locksettings set-disabled true
  touch "$MARK" && log "defaults applied"
fi

# 2) Navigation bar: disabled early in rw-system.sh via qemu.hw.mainkeys=1

# ---------------------------------------------------------------------------
# Sections 3+4 only AFTER the setup wizard has finished (LineageOS wizard:
# language, Wi-Fi, ...). The watchdog calls "f83w-boot.sh ha" as soon as
# user_setup_complete=1.
# ---------------------------------------------------------------------------
setup_ha() {
  # ---------------------------------------------------------------------------
  # 3) Home Assistant: permissions, battery, home app (every boot, idempotent)
  # ---------------------------------------------------------------------------
  if pm path "$PKG" >/dev/null 2>&1; then
    for p in POST_NOTIFICATIONS ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION \
             BLUETOOTH_CONNECT BLUETOOTH_SCAN BLUETOOTH_ADVERTISE READ_PHONE_STATE CALL_PHONE \
             CAMERA RECORD_AUDIO ACTIVITY_RECOGNITION; do
      pm grant "$PKG" "android.permission.$p" 2>/dev/null
    done
    appops set "$PKG" WRITE_SETTINGS allow          # set brightness
    appops set "$PKG" SYSTEM_ALERT_WINDOW allow     # command_webview / command_launch_app
    appops set "$PKG" RUN_ANY_IN_BACKGROUND allow
    appops set "$PKG" RUN_IN_BACKGROUND allow
    dumpsys deviceidle whitelist +"$PKG" >/dev/null # no battery optimisation
    pm enable "$HOME_ACT" >/dev/null 2>&1
    cmd package set-home-activity "$HOME_ACT" >/dev/null 2>&1
    log "Home Assistant set up (permissions, battery, home app)"
  fi

  # ---------------------------------------------------------------------------
  # 4) Preset Home Assistant app settings (full screen, keep screen on)
  #    Only if the keys are missing -> later changes in the app are kept.
  # ---------------------------------------------------------------------------
  DATA=/data/data/$PKG
  PREFS=$DATA/shared_prefs/themes_0.xml
  if [ -d "$DATA" ] && ! grep -q 'name="fullscreen_enabled"' "$PREFS" 2>/dev/null; then
    am force-stop "$PKG"
    OWN=$(stat -c %u:%g "$DATA")
    mkdir -p "$DATA/shared_prefs"
    if [ -f "$PREFS" ]; then
      sed -i '/name="keep_screen_on_enabled"/d; /name="fullscreen_enabled"/d' "$PREFS"
      sed -i 's#</map>#    <boolean name="keep_screen_on_enabled" value="true" />\n    <boolean name="fullscreen_enabled" value="true" />\n</map>#' "$PREFS"
    else
      cat > "$PREFS" <<'XML'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="keep_screen_on_enabled" value="true" />
    <boolean name="fullscreen_enabled" value="true" />
</map>
XML
    fi
    CTX=$(ls -Zd "$DATA" | awk '{print $1}')
    chown "$OWN" "$DATA/shared_prefs" "$PREFS"; chmod 771 "$DATA/shared_prefs"; chmod 660 "$PREFS"
    chcon "$CTX" "$DATA/shared_prefs" "$PREFS"
    am start -n "$PKG/io.homeassistant.companion.android.launch.LaunchActivity" >/dev/null 2>&1
    log "Home Assistant settings preset (full screen, keep screen on)"
  fi
}

if [ "$1" = "ha" ] || [ "$(settings get secure user_setup_complete)" = "1" ]; then
  setup_ha
else
  log "setup wizard not finished yet -> Home Assistant will be set up later"
fi
