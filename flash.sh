#!/usr/bin/env bash
# =============================================================================
#  F83W -> Home-Assistant-Wanddisplay
#
#  Baut ein Weelikeit F83W (Allwinner A133, Android 13 Werksfirmware) zu einem
#  schlanken LineageOS-20-Wanddisplay mit fest eingebauter Home-Assistant-App um.
#
#  Ablauf: Voraussetzungen -> Tablet verbinden -> Bootloader entsperren ->
#          System flashen -> Ersteinrichtung -> Home-Assistant-Anmeldung
#
#  Laeuft auf macOS. Bereits erledigte Schritte werden erkannt und uebersprungen,
#  das Skript kann also jederzeit neu gestartet werden.
# =============================================================================
set -u

cd "$(dirname "$0")" || exit 1
ROOT=$(pwd)
IMAGE_VERSION="v7"
IMAGE="images/lineage-20-a64_bvS-f83w-$IMAGE_VERSION.img"
IMAGE_URL="https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases/download/$IMAGE_VERSION/lineage-20-a64_bvS-f83w-$IMAGE_VERSION.img.gz"
VBMETA="images/vbmeta_disabled.img"
PKG="io.homeassistant.companion.android.minimal"
HA_DB="/data/data/$PKG/databases/HomeAssistantDB"
VENV="$ROOT/.venv"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/flash-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# ----------------------------------------------------------------------------- Ausgabe
if [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else B=""; G=""; Y=""; R=""; C=""; N=""; fi
step()  { echo; echo "${B}${C}==> $*${N}"; }
info()  { echo "    $*"; }
ok()    { echo "    ${G}OK${N}  $*"; }
warn()  { echo "    ${Y}!!${N}  $*"; }
fail()  { echo; echo "${R}${B}FEHLER:${N} $*"; echo "Protokoll: $LOG"; exit 1; }
ask()   { local a; read -r -p "    ${B}?${N}  $* [j/N] " a </dev/tty; case "$a" in j|J|ja|Ja|y|Y) return 0;; *) return 1;; esac; }
pause() { read -r -p "    ${B}>${N}  $* – weiter mit Enter " _ </dev/tty; }

# wait_until "Beschreibung" TIMEOUT_SEKUNDEN befehl...  (0 = unbegrenzt)
wait_until() {
  local desc=$1 timeout=$2; shift 2
  local start=$SECONDS n=0
  printf "    ... %s " "$desc"
  while ! "$@" >/dev/null 2>&1; do
    if [ "$timeout" -gt 0 ] && [ $((SECONDS - start)) -ge "$timeout" ]; then echo " ${Y}(Zeit abgelaufen)${N}"; return 1; fi
    n=$((n + 1)); [ $((n % 5)) -eq 0 ] && printf "."
    sleep 2
  done
  echo " ${G}ok${N}"
}

# ----------------------------------------------------------------------------- ADB/Fastboot
adb_state()      { adb devices 2>/dev/null | awk 'NR>1 && NF>=2 {print $2; exit}'; }
adb_ready()      { [ "$(adb_state)" = "device" ]; }
adb_unauth()     { [ "$(adb_state)" = "unauthorized" ]; }
adb_count()      { adb devices 2>/dev/null | awk 'NR>1 && NF>=2' | wc -l | tr -d ' '; }
prop()           { adb shell getprop "$1" 2>/dev/null | tr -d '\r'; }
fb_present()     { [ -n "$(fastboot devices 2>/dev/null | awk '{print $1; exit}')" ]; }
fb_var()         { fastboot getvar "$1" 2>&1 | awk -F': ' -v k="$1" '$1 ~ k {print $2; exit}' | tr -d '\r '; }
fb_userspace()   { fb_present && [ "$(fb_var is-userspace)" = "yes" ]; }
boot_completed() { adb_ready && [ "$(prop sys.boot_completed)" = "1" ]; }
setup_complete() { adb_ready && [ "$(adb shell settings get secure user_setup_complete 2>/dev/null | tr -d '\r')" = "1" ]; }
pyfb()           { "$VENV/bin/python" "$ROOT/tools/fastboot_usb.py" "$@"; }
# SQL auf der App-Datenbank (als root). SQL darf nur einfache Anfuehrungszeichen enthalten.
hadb()           { adb shell "su -c \"sqlite3 $HA_DB \\\"$1\\\"\"" 2>/dev/null | tr -d '\r'; }
oem_allowed()    { [ "$(prop sys.oem_unlock_allowed)" = "1" ]; }
ha_is_home()     { adb shell cmd package resolve-activity -c android.intent.category.HOME -a android.intent.action.MAIN 2>/dev/null | grep -q "$PKG"; }
ha_logged_in()   { [ "$(hadb "select count(*) from servers;")" -ge 1 ] 2>/dev/null; }
ha_ssid_set()    { [ "$(hadb "select count(*) from servers where internal_ssids != '[]';")" -ge 1 ] 2>/dev/null; }

# ----------------------------------------------------------------------------- 1. Voraussetzungen
prerequisites() {
  step "1/7  Voraussetzungen auf dem Mac"
  [ "$(uname -s)" = "Darwin" ] || fail "Dieses Skript ist fuer macOS gedacht."

  if ! command -v brew >/dev/null 2>&1; then
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
  fi
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew ist nicht installiert."
    ask "Homebrew jetzt installieren (offizielles Installationsskript von brew.sh)?" || fail "Homebrew wird benoetigt."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail "Homebrew-Installation fehlgeschlagen."
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
  fi
  ok "Homebrew: $(brew --version | head -1)"

  if ! command -v adb >/dev/null 2>&1 || ! command -v fastboot >/dev/null 2>&1; then
    info "Installiere android-platform-tools (adb, fastboot)"
    brew install android-platform-tools || fail "brew install android-platform-tools fehlgeschlagen."
  fi
  ok "adb/fastboot: $(adb version | head -1)"

  [ -f "$VBMETA" ] || fail "images/vbmeta_disabled.img fehlt."
  if [ ! -f "$IMAGE" ]; then
    if [ ! -f "$IMAGE.gz" ]; then
      info "System-Image fehlt – lade $IMAGE_VERSION aus dem GitHub-Release (ca. 800 MB) ..."
      curl -fL --progress-bar -o "$IMAGE.gz.part" "$IMAGE_URL" && mv "$IMAGE.gz.part" "$IMAGE.gz" \
        || fail "Download fehlgeschlagen: $IMAGE_URL"
    fi
    info "Entpacke $IMAGE.gz ..."
    gunzip -k "$IMAGE.gz" || fail "Entpacken fehlgeschlagen."
  fi
  info "Pruefe Pruefsummen der Images (dauert einen Moment) ..."
  (cd images && grep -E "  (lineage-20-a64_bvS-f83w-$IMAGE_VERSION.img|vbmeta_disabled.img)$" SHA256SUMS | shasum -a 256 -c - >/dev/null 2>&1) \
    || fail "Pruefsumme stimmt nicht – Image beschaedigt? Datei in images/ loeschen und Skript neu starten."
  ok "Images vollstaendig"
}

# ----------------------------------------------------------------------------- 2. Tablet verbinden
connect_device() {
  step "2/7  Tablet verbinden"
  if ! adb_ready; then
    info "Auf dem Tablet (Werksfirmware) bitte:"
    info "  1. Einrichtung bis zum Startbildschirm durchklicken (WLAN/Google-Konto koennen uebersprungen werden)"
    info "  2. Einstellungen -> Ueber das Tablet -> 7x auf 'Build-Nummer' tippen"
    info "  3. Einstellungen -> System -> Entwickleroptionen -> 'USB-Debugging' einschalten"
    info "  4. Tablet mit einem DATENKABEL an den Mac anschliessen (reine Ladekabel gehen nicht)"
    info "  5. Abfrage 'USB-Debugging zulassen?' auf dem Tablet bestaetigen"
    local warned=0
    printf "    ... warte auf das Tablet "
    while ! adb_ready; do
      if adb_unauth && [ $warned -eq 0 ]; then echo; warn "Tablet gefunden, aber nicht freigegeben – bitte Abfrage auf dem Tablet bestaetigen"; printf "    ... "; warned=1; fi
      printf "."; sleep 2
    done
    echo " ${G}ok${N}"
  fi
  [ "$(adb_count)" = "1" ] || fail "Es ist mehr als ein Android-Geraet verbunden. Bitte nur das Tablet anschliessen."
  export ANDROID_SERIAL; ANDROID_SERIAL=$(adb get-serialno | tr -d '\r')

  local dev hw inc lin locked
  dev=$(prop ro.product.vendor.device); hw=$(prop ro.boot.hardware)
  inc=$(prop ro.vendor.build.version.incremental); lin=$(prop ro.lineage.version)
  locked=$(prop ro.boot.flash.locked)
  info "Seriennummer: $ANDROID_SERIAL"
  info "Geraet: $dev / Hardware: $hw / Vendor-Build: $inc"
  [ -n "$lin" ] && info "Aktuelles System: LineageOS $lin"
  adb shell getprop > "$LOGDIR/$ANDROID_SERIAL-getprop-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null

  [ "$dev" = "F83W" ] && [ "$hw" = "sun50iw10p1" ] || { warn "Das ist kein Weelikeit F83W mit Allwinner A133."; ask "Trotzdem fortfahren (auf eigenes Risiko)?" || exit 1; }
  [ "$inc" = "20231212" ] || { warn "Abweichende Werksfirmware ($inc statt 20231212) – Image ist dafuer nicht getestet."; ask "Trotzdem fortfahren?" || exit 1; }

  local lvl; lvl=$(adb shell dumpsys battery 2>/dev/null | awk '/level:/{print $2; exit}' | tr -d '\r')
  if [ -n "$lvl" ] && [ "$lvl" -lt 40 ]; then warn "Akku nur bei $lvl % – bitte waehrend des Vorgangs am Netzteil lassen."; fi

  if [ "$locked" = "0" ]; then ok "Bootloader ist bereits entsperrt"; else info "Bootloader ist gesperrt"; fi
  if [ -n "$lin" ] && adb shell ls /system/bin/f83w-watchdog.sh >/dev/null 2>&1; then
    ok "Das F83W-System ist bereits installiert"
    ask "Trotzdem neu flashen? (ALLE Daten auf dem Tablet werden geloescht)" || SKIP_FLASH=1
  fi
}

# Notfallweg fuer den Allwinner-Bootloader: libusb + pyusb nur bei Bedarf installieren
usb_fallback_ready() {
  brew list libusb >/dev/null 2>&1 || { info "Installiere libusb"; brew install libusb || return 1; }
  if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c "import usb" >/dev/null 2>&1; then
    command -v python3 >/dev/null 2>&1 || { info "Installiere Python"; brew install python || return 1; }
    info "Lege Python-Umgebung mit pyusb an ($VENV)"
    python3 -m venv "$VENV" && "$VENV/bin/pip" install -q --upgrade pip pyusb || return 1
  fi
}

# ----------------------------------------------------------------------------- 3. Bootloader entsperren
unlock_bootloader() {
  [ "$(prop ro.boot.flash.locked)" = "0" ] && return 0
  step "3/7  Bootloader entsperren"
  warn "Beim Entsperren werden ALLE Daten auf dem Tablet geloescht."
  ask "Bootloader jetzt entsperren?" || exit 1

  if ! oem_allowed; then
    info "Bitte in den Entwickleroptionen 'OEM-Entsperrung' einschalten."
    wait_until "warte auf OEM-Entsperrung" 0 oem_allowed
  fi
  ok "OEM-Entsperrung erlaubt"

  info "Starte in den Bootloader (gruenes Maennchen) ..."
  adb reboot bootloader
  local done_unlock=0
  if wait_until "warte auf Fastboot (macOS-fastboot)" 25 fb_present; then
    fastboot oem unlock && done_unlock=1
    [ $done_unlock -eq 1 ] && fastboot reboot >/dev/null 2>&1
  fi
  if [ $done_unlock -eq 0 ]; then
    info "macOS-fastboot sieht den Allwinner-Bootloader nicht – versuche direkten USB-Zugriff (libusb) ..."
    if usb_fallback_ready && pyfb wait 20 && pyfb oem unlock; then
      done_unlock=1; pyfb reboot >/dev/null 2>&1
    fi
  fi
  if [ $done_unlock -eq 0 ]; then
    warn "Entsperren vom Mac aus nicht moeglich. Ausweg ueber einen Windows-PC (einmalig):"
    info "  1. Google Platform Tools + Google USB Driver laden (developer.android.com)"
    info "  2. Tablet steht im Bootloader (gruenes Maennchen); im Geraete-Manager 'USB Developer'"
    info "     -> Treiber aktualisieren -> android_winusb.inf -> 'Android Bootloader Interface'"
    info "  3. .\\fastboot oem unlock   und danach   .\\fastboot reboot"
    pause "Wenn das Tablet entsperrt ist und wieder hochfaehrt, das Kabel zurueck an den Mac"
  fi

  info "Das Tablet startet neu. Falls es dabei zurueckgesetzt wurde: Einrichtung durchklicken,"
  info "Entwickleroptionen und USB-Debugging wieder einschalten (siehe Schritt 2)."
  wait_until "warte auf das Tablet" 0 adb_ready
  [ "$(prop ro.boot.flash.locked)" = "0" ] || fail "Bootloader ist weiterhin gesperrt (ro.boot.flash.locked=$(prop ro.boot.flash.locked))."
  ok "Bootloader entsperrt (Status: $(prop ro.boot.verifiedbootstate))"
}

# ----------------------------------------------------------------------------- 4. Flashen
flash_system() {
  [ "${SKIP_FLASH:-0}" = "1" ] && return 0
  step "4/7  System flashen"
  adb reboot fastboot
  wait_until "warte auf fastbootd" 120 fb_userspace || fail "fastbootd nicht erreichbar. Tablet aus, Lauter+Power halten -> Recovery -> 'Enter fastboot', dann Skript neu starten."
  local slot; slot=$(fb_var current-slot); [ -n "$slot" ] || slot=a
  info "Aktiver Slot: $slot"
  fastboot --disable-verity --disable-verification flash "vbmeta_$slot" "$VBMETA" || fail "vbmeta flashen fehlgeschlagen"
  fastboot delete-logical-partition "product_$slot" >/dev/null 2>&1 && info "product_$slot entfernt (Platz fuer das System)"
  fastboot erase "system_$slot"                     || fail "system_$slot loeschen fehlgeschlagen"
  fastboot flash "system_$slot" "$IMAGE"            || fail "System flashen fehlgeschlagen"
  fastboot -w                                       || warn "Datenbereich loeschen meldete einen Fehler (wird beim Start neu angelegt)"
  fastboot reboot
  ok "System geflasht"
}

# ----------------------------------------------------------------------------- 5. Erster Start
first_boot() {
  step "5/7  Erster Start"
  info "Der erste Start dauert 3-5 Minuten (Lineage-Startanimation)."
  wait_until "warte auf ADB" 600 adb_ready     || fail "Tablet meldet sich nicht. Siehe Fehlerbehebung in README.md."
  wait_until "warte auf Systemstart" 600 boot_completed || fail "System startet nicht fertig."
  case "$(prop ro.lineage.version)" in *a64_bvS*) ok "LineageOS $(prop ro.lineage.version) laeuft";; *) fail "Unerwartetes System: $(prop ro.lineage.version)";; esac
  [ "$(prop ro.surface_flinger.primary_display_orientation)" = "ORIENTATION_90" ] && ok "Querformat aktiv"
}

# ----------------------------------------------------------------------------- 6. Ersteinrichtung
setup_wizard() {
  step "6/7  Ersteinrichtung (Lineage-Assistent)"
  if ! setup_complete; then
    info "Bitte auf dem Tablet den Einrichtungsassistenten durchgehen:"
    info "  Sprache Deutsch, WLAN verbinden, Datum/Uhrzeit – der Rest kann uebersprungen werden."
    wait_until "warte auf Abschluss der Einrichtung" 0 setup_complete
  fi
  ok "Einrichtung abgeschlossen"
  wait_until "warte auf Home Assistant als Startbildschirm" 120 ha_is_home \
    && ok "Home Assistant ist Startbildschirm" || warn "Home Assistant ist (noch) nicht Startbildschirm"
}

# ----------------------------------------------------------------------------- 7. Home Assistant
home_assistant() {
  step "7/7  Home Assistant"
  info "Bitte in der Home-Assistant-App auf dem Tablet:"
  info "  Server waehlen, mit dem Wanddisplay-Benutzer anmelden, Abfragen bestaetigen."
  wait_until "warte auf Anmeldung" 0 ha_logged_in
  ok "Angemeldet"
  info "Der Waechter traegt jetzt Heim-WLAN und dauerhafte Verbindung ein und startet die App einmal neu ..."
  wait_until "warte auf Waechter" 180 ha_ssid_set \
    && ok "Heim-WLAN: $(hadb "select internal_ssids from servers limit 1;")" \
    || warn "Heim-WLAN wurde nicht automatisch eingetragen (WLAN verbunden?)"
  ok "Dauerhafte Verbindung: $(hadb "select group_concat(websocket_setting) from settings;")"
  adb logcat -d -s f83w f83w-watchdog > "$LOGDIR/$ANDROID_SERIAL-f83w-$(date +%Y%m%d-%H%M%S).log" 2>/dev/null
  info "Jetzt noch in der App das Standard-Dashboard waehlen."
}

# ----------------------------------------------------------------------------- Hauptablauf
echo "${B}F83W -> Home-Assistant-Wanddisplay${N}   (Protokoll: $LOG)"
prerequisites
connect_device
unlock_bootloader
flash_system
first_boot
setup_wizard
home_assistant
step "Fertig"
ok "Tablet $ANDROID_SERIAL ist eingerichtet."
info "Helligkeit aus Home Assistant: notify.mobile_app_<geraet> mit message 'command_screen_brightness_level'."
