#!/usr/bin/env bash
# =============================================================================
#  F83W -> Home Assistant wall panel
#
#  Turns a Weelikeit F83W (Allwinner A133, stock Android 13) into a slim
#  LineageOS 20 wall panel with the Home Assistant app built in.
#
#  Flow: prerequisites -> connect tablet -> unlock bootloader ->
#        flash system -> setup wizard -> Home Assistant login
#
#  Runs on macOS. Completed steps are detected and skipped, so the script can
#  be restarted at any time.
# =============================================================================
set -u

cd "$(dirname "$0")" || exit 1
ROOT=$(pwd)
# The system image is built by GitHub Actions (tools/build_image.py) and published as a release.
IMAGE_VERSION="${F83W_IMAGE_VERSION:-v8}"
IMAGE_NAME="lineage-20-a64_bvS-f83w-$IMAGE_VERSION.img"
IMAGE="images/$IMAGE_NAME"
IMAGE_SUMS="images/SHA256SUMS-$IMAGE_VERSION"
RELEASE_URL="https://github.com/DasRed/weelike-f83w-homeassistant-kiosk/releases/download/$IMAGE_VERSION"
VBMETA="images/vbmeta_disabled.img"
PKG="io.homeassistant.companion.android.minimal"
HA_DB="/data/data/$PKG/databases/HomeAssistantDB"
VENV="$ROOT/.venv"
LOGDIR="$ROOT/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/flash-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# ----------------------------------------------------------------------------- Output
if [ -t 1 ] || [ -n "${FORCE_COLOR:-}" ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else B=""; G=""; Y=""; R=""; C=""; N=""; fi
step()  { echo; echo "${B}${C}==> $*${N}"; }
info()  { echo "    $*"; }
ok()    { echo "    ${G}OK${N}  $*"; }
warn()  { echo "    ${Y}!!${N}  $*"; }
fail()  { echo; echo "${R}${B}ERROR:${N} $*"; echo "Log: $LOG"; exit 1; }
ask()   { local a; read -r -p "    ${B}?${N}  $* [y/N] " a </dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0;; *) return 1;; esac; }
pause() { read -r -p "    ${B}>${N}  $* – press Enter to continue " _ </dev/tty; }

# wait_until "description" TIMEOUT_SECONDS command...  (0 = no limit)
wait_until() {
  local desc=$1 timeout=$2; shift 2
  local start=$SECONDS n=0
  printf "    ... %s " "$desc"
  while ! "$@" >/dev/null 2>&1; do
    if [ "$timeout" -gt 0 ] && [ $((SECONDS - start)) -ge "$timeout" ]; then echo " ${Y}(timed out)${N}"; return 1; fi
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
# SQL on the app database (as root). SQL may only contain single quotes.
hadb()           { adb shell "su -c \"sqlite3 $HA_DB \\\"$1\\\"\"" 2>/dev/null | tr -d '\r'; }
oem_allowed()    { [ "$(prop sys.oem_unlock_allowed)" = "1" ]; }
ha_is_home()     { adb shell cmd package resolve-activity -c android.intent.category.HOME -a android.intent.action.MAIN 2>/dev/null | grep -q "$PKG"; }
ha_logged_in()   { [ "$(hadb "select count(*) from servers;")" -ge 1 ] 2>/dev/null; }
ha_ssid_set()    { [ "$(hadb "select count(*) from servers where internal_ssids != '[]';")" -ge 1 ] 2>/dev/null; }

# ----------------------------------------------------------------------------- 1. Prerequisites
prerequisites() {
  step "1/7  Prerequisites on the Mac"
  [ "$(uname -s)" = "Darwin" ] || fail "This script is meant for macOS."
  command -v python3 >/dev/null 2>&1 \
    || fail "python3 is missing. Run 'xcode-select --install' and start the script again."

  if ! command -v brew >/dev/null 2>&1; then
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
  fi
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew is not installed."
    ask "Install Homebrew now (official installer from brew.sh)?" || fail "Homebrew is required."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail "Homebrew installation failed."
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x "$p" ] && eval "$("$p" shellenv)"; done
  fi
  ok "Homebrew: $(brew --version | head -1)"

  if ! command -v adb >/dev/null 2>&1 || ! command -v fastboot >/dev/null 2>&1; then
    info "Installing android-platform-tools (adb, fastboot)"
    brew install android-platform-tools || fail "brew install android-platform-tools failed."
  fi
  ok "adb/fastboot: $(adb version | head -1)"

  if ! command -v xz >/dev/null 2>&1; then
    info "Installing xz (to unpack the system image)"
    brew install xz || fail "brew install xz failed."
  fi

  [ -f "$VBMETA" ] || fail "images/vbmeta_disabled.img is missing."
  (cd images && grep -E "  vbmeta_disabled.img$" SHA256SUMS | shasum -a 256 -c - >/dev/null 2>&1) \
    || fail "Checksum of images/vbmeta_disabled.img does not match."
  fetch_image
  ok "Images complete ($IMAGE_VERSION)"
}

# Download the system image from the GitHub release, verify and unpack it
image_ok() { (cd images && grep -E "  $IMAGE_NAME$" "$(basename "$IMAGE_SUMS")" | shasum -a 256 -c - >/dev/null 2>&1); }
fetch_image() {
  if [ ! -f "$IMAGE_SUMS" ]; then
    curl -fsSL -o "$IMAGE_SUMS.part" "$RELEASE_URL/SHA256SUMS" && mv "$IMAGE_SUMS.part" "$IMAGE_SUMS" \
      || fail "Release $IMAGE_VERSION not found: $RELEASE_URL"
  fi
  if [ -f "$IMAGE" ]; then
    info "Checking existing system image (takes a moment) ..."
    image_ok && return 0
    warn "Existing system image does not match $IMAGE_VERSION – downloading it again."
    rm -f "$IMAGE"
  fi
  if [ ! -f "$IMAGE.xz" ] || ! (cd images && grep -E "  $IMAGE_NAME.xz$" "$(basename "$IMAGE_SUMS")" | shasum -a 256 -c - >/dev/null 2>&1); then
    info "Downloading system image $IMAGE_VERSION from the GitHub release (about 650 MB) ..."
    curl -fL --progress-bar -C - -o "$IMAGE.xz.part" "$RELEASE_URL/$IMAGE_NAME.xz" && mv "$IMAGE.xz.part" "$IMAGE.xz" \
      || fail "Download failed: $RELEASE_URL/$IMAGE_NAME.xz (restarting the script resumes the download)"
    (cd images && grep -E "  $IMAGE_NAME.xz$" "$(basename "$IMAGE_SUMS")" | shasum -a 256 -c - >/dev/null 2>&1) \
      || { rm -f "$IMAGE.xz"; fail "Checksum of the download does not match – please restart the script."; }
  fi
  info "Unpacking system image ..."
  xz -dkf "$IMAGE.xz" || fail "Unpacking failed."
  image_ok || fail "Checksum of the unpacked image does not match – delete the files in images/ and restart the script."
}

# ----------------------------------------------------------------------------- 2. Connect tablet
connect_device() {
  step "2/7  Connect the tablet"
  if ! adb_ready; then
    info "On the tablet (stock firmware), please:"
    info "  1. Go through the setup until the home screen (Wi-Fi and Google account can be skipped)"
    info "  2. Settings -> About tablet -> tap 'Build number' 7 times"
    info "  3. Settings -> System -> Developer options -> turn on 'USB debugging'"
    info "  4. Connect the tablet to the Mac with a DATA cable (charge-only cables don't work)"
    info "  5. Confirm 'Allow USB debugging?' on the tablet"
    local warned=0
    printf "    ... waiting for the tablet "
    while ! adb_ready; do
      if adb_unauth && [ $warned -eq 0 ]; then echo; warn "Tablet found but not authorized – please confirm the prompt on the tablet"; printf "    ... "; warned=1; fi
      printf "."; sleep 2
    done
    echo " ${G}ok${N}"
  fi
  [ "$(adb_count)" = "1" ] || fail "More than one Android device is connected. Please connect only the tablet."
  export ANDROID_SERIAL; ANDROID_SERIAL=$(adb get-serialno | tr -d '\r')

  local dev hw inc lin locked
  dev=$(prop ro.product.vendor.device); hw=$(prop ro.boot.hardware)
  inc=$(prop ro.vendor.build.version.incremental); lin=$(prop ro.lineage.version)
  locked=$(prop ro.boot.flash.locked)
  info "Serial number: $ANDROID_SERIAL"
  info "Device: $dev / hardware: $hw / vendor build: $inc"
  [ -n "$lin" ] && info "Current system: LineageOS $lin"
  adb shell getprop > "$LOGDIR/$ANDROID_SERIAL-getprop-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null

  [ "$dev" = "F83W" ] && [ "$hw" = "sun50iw10p1" ] || { warn "This is not a Weelikeit F83W with Allwinner A133."; ask "Continue anyway (at your own risk)?" || exit 1; }
  [ "$inc" = "20231212" ] || { warn "Different stock firmware ($inc instead of 20231212) – the image is not tested with it."; ask "Continue anyway?" || exit 1; }

  local lvl; lvl=$(adb shell dumpsys battery 2>/dev/null | awk '/level:/{print $2; exit}' | tr -d '\r')
  if [ -n "$lvl" ] && [ "$lvl" -lt 40 ]; then warn "Battery only at $lvl % – please keep the tablet on the charger during the process."; fi

  if [ "$locked" = "0" ]; then ok "Bootloader is already unlocked"; else info "Bootloader is locked"; fi
  if [ -n "$lin" ] && adb shell ls /system/bin/f83w-watchdog.sh >/dev/null 2>&1; then
    ok "The F83W system is already installed"
    ask "Flash again anyway? (ALL data on the tablet will be erased)" || SKIP_FLASH=1
  fi
}

# Fallback for the Allwinner bootloader: install libusb + pyusb only when needed
usb_fallback_ready() {
  brew list libusb >/dev/null 2>&1 || { info "Installing libusb"; brew install libusb || return 1; }
  if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c "import usb" >/dev/null 2>&1; then
    info "Creating Python environment with pyusb ($VENV)"
    python3 -m venv "$VENV" && "$VENV/bin/pip" install -q --upgrade pip pyusb || return 1
  fi
}

# ----------------------------------------------------------------------------- 3. Unlock bootloader
unlock_bootloader() {
  [ "$(prop ro.boot.flash.locked)" = "0" ] && return 0
  step "3/7  Unlock the bootloader"
  warn "Unlocking erases ALL data on the tablet."
  ask "Unlock the bootloader now?" || exit 1

  if ! oem_allowed; then
    info "Please turn on 'OEM unlocking' in the developer options."
    wait_until "waiting for OEM unlocking" 0 oem_allowed
  fi
  ok "OEM unlocking allowed"

  info "Rebooting into the bootloader (green Android robot) ..."
  adb reboot bootloader
  local done_unlock=0
  if wait_until "waiting for fastboot (macOS fastboot)" 25 fb_present; then
    fastboot oem unlock && done_unlock=1
    [ $done_unlock -eq 1 ] && fastboot reboot >/dev/null 2>&1
  fi
  if [ $done_unlock -eq 0 ]; then
    info "macOS fastboot doesn't see the Allwinner bootloader – trying direct USB access (libusb) ..."
    if usb_fallback_ready && pyfb wait 20 && pyfb oem unlock; then
      done_unlock=1; pyfb reboot >/dev/null 2>&1
    fi
  fi
  if [ $done_unlock -eq 0 ]; then
    warn "Unlocking from the Mac is not possible. Workaround via a Windows PC (one time):"
    info "  1. Download Google Platform Tools + Google USB Driver (developer.android.com)"
    info "  2. With the tablet in the bootloader (green robot), open Device Manager -> 'USB Developer'"
    info "     -> Update driver -> android_winusb.inf -> 'Android Bootloader Interface'"
    info "  3. .\\fastboot oem unlock   and then   .\\fastboot reboot"
    pause "Once the tablet is unlocked and booting again, plug the cable back into the Mac"
  fi

  info "The tablet reboots. If it was reset in the process: go through the setup,"
  info "turn developer options and USB debugging on again (see step 2)."
  wait_until "waiting for the tablet" 0 adb_ready
  [ "$(prop ro.boot.flash.locked)" = "0" ] || fail "Bootloader is still locked (ro.boot.flash.locked=$(prop ro.boot.flash.locked))."
  ok "Bootloader unlocked (state: $(prop ro.boot.verifiedbootstate))"
}

# ----------------------------------------------------------------------------- 4. Flash
flash_system() {
  [ "${SKIP_FLASH:-0}" = "1" ] && return 0
  step "4/7  Flash the system"
  adb reboot fastboot
  wait_until "waiting for fastbootd" 120 fb_userspace || fail "fastbootd not reachable. Turn the tablet off, hold Volume Up + Power -> recovery -> 'Enter fastboot', then restart the script."
  local slot; slot=$(fb_var current-slot); [ -n "$slot" ] || slot=a
  info "Active slot: $slot"
  fastboot --disable-verity --disable-verification flash "vbmeta_$slot" "$VBMETA" || fail "Flashing vbmeta failed"
  fastboot delete-logical-partition "product_$slot" >/dev/null 2>&1 && info "product_$slot removed (room for the system)"
  fastboot erase "system_$slot"                     || fail "Erasing system_$slot failed"
  fastboot flash "system_$slot" "$IMAGE"            || fail "Flashing the system failed"
  fastboot -w                                       || warn "Wiping userdata reported an error (it is recreated on boot)"
  fastboot reboot
  ok "System flashed"
}

# ----------------------------------------------------------------------------- 5. First boot
first_boot() {
  step "5/7  First boot"
  info "The first boot takes 3-5 minutes (LineageOS boot animation)."
  wait_until "waiting for ADB" 600 adb_ready     || fail "The tablet does not respond. See Troubleshooting in README.md."
  wait_until "waiting for boot to complete" 600 boot_completed || fail "The system does not finish booting."
  case "$(prop ro.lineage.version)" in *a64_bvS*) ok "LineageOS $(prop ro.lineage.version) is running";; *) fail "Unexpected system: $(prop ro.lineage.version)";; esac
  [ "$(prop ro.surface_flinger.primary_display_orientation)" = "ORIENTATION_90" ] && ok "Landscape orientation active"
}

# ----------------------------------------------------------------------------- 6. Setup wizard
setup_wizard() {
  step "6/7  Setup wizard (LineageOS)"
  if ! setup_complete; then
    info "Please go through the setup wizard on the tablet:"
    info "  Language, Wi-Fi, date/time – everything else can be skipped."
    wait_until "waiting for the setup to finish" 0 setup_complete
  fi
  ok "Setup finished"
  wait_until "waiting for Home Assistant as home app" 120 ha_is_home \
    && ok "Home Assistant is the home app" || warn "Home Assistant is not the home app (yet)"
}

# ----------------------------------------------------------------------------- 7. Home Assistant
home_assistant() {
  step "7/7  Home Assistant"
  info "In the Home Assistant app on the tablet, please:"
  info "  choose your server, log in with the wall panel user, confirm the prompts."
  wait_until "waiting for login" 0 ha_logged_in
  ok "Logged in"
  info "The watchdog now sets the home Wi-Fi and the persistent connection and restarts the app once ..."
  wait_until "waiting for the watchdog" 180 ha_ssid_set \
    && ok "Home Wi-Fi: $(hadb "select internal_ssids from servers limit 1;")" \
    || warn "Home Wi-Fi was not set automatically (is Wi-Fi connected?)"
  ok "Persistent connection: $(hadb "select group_concat(websocket_setting) from settings;")"
  adb logcat -d -s f83w f83w-watchdog > "$LOGDIR/$ANDROID_SERIAL-f83w-$(date +%Y%m%d-%H%M%S).log" 2>/dev/null
  info "Finally, choose the default dashboard in the app."
}

# ----------------------------------------------------------------------------- Main
echo "${B}F83W -> Home Assistant wall panel${N}   (log: $LOG)"
prerequisites
connect_device
unlock_bootloader
flash_system
first_boot
setup_wizard
home_assistant
step "Done"
ok "Tablet $ANDROID_SERIAL is set up."
info "Brightness from Home Assistant: notify.mobile_app_<device> with message 'command_screen_brightness_level'."
