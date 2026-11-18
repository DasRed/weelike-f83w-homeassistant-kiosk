#!/system/bin/sh
# F83W Wand-Display: haelt Home Assistant im Vordergrund und startet die App
# naechtlich einmal neu (gegen haengende/weisse WebView).
PKG=io.homeassistant.companion.android.minimal
ACT=$PKG/io.homeassistant.companion.android.launch.LaunchActivity
INTERVAL=30          # Sekunden zwischen Pruefungen
GRACE=600            # so lange darf eine andere App vorne sein (z. B. Einstellungen)
RESTART_AT=400       # naechtlicher App-Neustart (HMM ohne fuehrende Null, 400 = 04:00)
DB=/data/data/$PKG/databases/HomeAssistantDB
log() { /system/bin/log -t f83w-watchdog "$*"; }

current_ssid() {
  cmd wifi status 2>/dev/null | grep -m1 -o 'SSID: "[^"]*"' | sed 's/^SSID: "//; s/"$//'
}

# Nach dem Anmelden einmalig je Server:
#  - dauerhafte Verbindung = ALWAYS (ohne Google-Dienste noetig fuer Befehle aus HA)
#  - Heim-WLAN = aktuell verbundenes WLAN, falls noch keins eingetragen ist
fix_server_settings() {
  [ -f "$DB" ] || return 0
  ws=$(sqlite3 "$DB" "select count(*) from settings where websocket_setting != 'ALWAYS';" 2>/dev/null)
  ssid=$(current_ssid)
  case "$ssid" in ""|"<unknown ssid>"|*\"*|*\\*) ssid="" ;; esac
  wl=0
  [ -n "$ssid" ] && wl=$(sqlite3 "$DB" "select count(*) from servers where internal_ssids = '[]';" 2>/dev/null)
  [ "${ws:-0}" -gt 0 ] 2>/dev/null || [ "${wl:-0}" -gt 0 ] 2>/dev/null || return 0

  am force-stop "$PKG"; sleep 1
  if [ "${ws:-0}" -gt 0 ] 2>/dev/null; then
    sqlite3 "$DB" "update settings set websocket_setting = 'ALWAYS';"
    log "dauerhafte Verbindung -> ALWAYS ($ws Server)"
  fi
  if [ "${wl:-0}" -gt 0 ] 2>/dev/null; then
    q=$(echo "$ssid" | sed "s/'/''/g")
    sqlite3 "$DB" "update servers set internal_ssids = '[\"$q\"]' where internal_ssids = '[]';"
    log "Heim-WLAN -> $ssid ($wl Server)"
  fi
  am start -n "$ACT" >/dev/null 2>&1
}

# Erst nach abgeschlossener Ersteinrichtung eingreifen
until [ "$(settings get secure user_setup_complete 2>/dev/null)" = "1" ]; do sleep 15; done
log "Ersteinrichtung abgeschlossen -> Home Assistant einrichten"
/system/bin/f83w-boot.sh ha

foreign=0; last_restart=""
while true; do
  sleep $INTERVAL
  pm path "$PKG" >/dev/null 2>&1 || continue
  fix_server_settings
  dumpsys power | grep -q "mWakefulness=Awake" || continue

  # naechtlicher Neustart der App
  now=$(date +%H%M | sed "s/^0*//"); now=${now:-0}; today=$(date +%Y%m%d)
  if [ "$now" -ge "$RESTART_AT" ] && [ "$last_restart" != "$today" ] && [ "$now" -lt $((RESTART_AT + 10)) ]; then
    log "naechtlicher Neustart von $PKG"
    am force-stop "$PKG"; sleep 2; am start -n "$ACT" >/dev/null 2>&1
    last_restart=$today; foreign=0; continue
  fi

  top=$(dumpsys activity activities | grep -m1 -E "topResumedActivity|mResumedActivity")
  case "$top" in
    *"$PKG"/*) foreign=0 ;;
    *)
      foreign=$((foreign + INTERVAL))
      if [ -z "$top" ] || [ "$foreign" -ge "$GRACE" ]; then
        log "Home Assistant nicht im Vordergrund (${top:-keine Activity}) -> zurueckholen"
        am start -n "$ACT" >/dev/null 2>&1; foreign=0
      fi ;;
  esac
done
