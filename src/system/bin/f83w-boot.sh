#!/system/bin/sh
# F83W Wand-Display: wird nach jedem Boot von /system/etc/init/f83w.rc gestartet
# (Kontext phhsu_daemon, root).
PKG=io.homeassistant.companion.android.minimal
HOME_ACT=$PKG/io.homeassistant.companion.android.launch.LauncherAlias
log() { /system/bin/log -t f83w "$*"; }

# ---------------------------------------------------------------------------
# 1) Einmalige Grundeinstellungen pro Datenbereich (spaetere Aenderungen bleiben)
# ---------------------------------------------------------------------------
MARK=/data/system/f83w-defaults-v1.done
if [ "$1" != "ha" ] && [ ! -f "$MARK" ]; then
  settings put global stay_on_while_plugged_in 7          # Display an, solange Strom anliegt
  settings put system screen_off_timeout 2147483647
  settings put system screen_brightness_mode 0             # keine automatische Helligkeit
  settings put secure screensaver_enabled 0
  settings put secure screensaver_activate_on_dock 0
  settings put secure screensaver_activate_on_sleep 0
  settings put global window_animation_scale 0
  settings put global transition_animation_scale 0
  settings put global animator_duration_scale 0
  locksettings set-disabled true
  touch "$MARK" && log "Grundeinstellungen gesetzt"
fi

# 2) Navigationsleiste: wird frueh in rw-system.sh per qemu.hw.mainkeys=1 abgeschaltet

# ---------------------------------------------------------------------------
# Abschnitte 3+4 erst NACH abgeschlossener Ersteinrichtung (Lineage-Assistent:
# Sprache, WLAN, ...). Der Waechter ruft "f83w-boot.sh ha" auf, sobald
# user_setup_complete=1 ist.
# ---------------------------------------------------------------------------
setup_ha() {
  # ---------------------------------------------------------------------------
  # 3) Home Assistant: Rechte, Akku, Startbildschirm (bei jedem Boot, idempotent)
  # ---------------------------------------------------------------------------
  if pm path "$PKG" >/dev/null 2>&1; then
    for p in POST_NOTIFICATIONS ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION \
             BLUETOOTH_CONNECT BLUETOOTH_SCAN BLUETOOTH_ADVERTISE READ_PHONE_STATE CALL_PHONE \
             CAMERA RECORD_AUDIO ACTIVITY_RECOGNITION; do
      pm grant "$PKG" "android.permission.$p" 2>/dev/null
    done
    appops set "$PKG" WRITE_SETTINGS allow          # Helligkeit setzen
    appops set "$PKG" SYSTEM_ALERT_WINDOW allow     # command_webview / command_launch_app
    appops set "$PKG" RUN_ANY_IN_BACKGROUND allow
    appops set "$PKG" RUN_IN_BACKGROUND allow
    dumpsys deviceidle whitelist +"$PKG" >/dev/null # keine Akku-Optimierung
    pm enable "$HOME_ACT" >/dev/null 2>&1
    cmd package set-home-activity "$HOME_ACT" >/dev/null 2>&1
    log "Home Assistant eingerichtet (Rechte, Akku, Startbildschirm)"
  fi

  # ---------------------------------------------------------------------------
  # 4) Home-Assistant-App-Einstellungen vorbelegen (Vollbild, Bildschirm anlassen)
  #    Nur wenn die Schluessel fehlen -> spaetere Aenderungen in der App bleiben.
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
    log "Home-Assistant-Einstellungen vorbelegt (Vollbild, Bildschirm an)"
  fi
}

if [ "$1" = "ha" ] || [ "$(settings get secure user_setup_complete)" = "1" ]; then
  setup_ha
else
  log "Ersteinrichtung noch nicht abgeschlossen -> Home Assistant wird spaeter eingerichtet"
fi
