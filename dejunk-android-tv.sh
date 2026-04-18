#!/usr/bin/env bash
# =============================================================================
# Prism+ Android TV 10 — AT4K Launcher + Debloat
# =============================================================================
#
# ONE-TIME MANUAL PREREQUISITE (do this on the TV before running this script):
#   1. Settings → Device Preferences → About → Build Number
#      Press OK 7 times until "You are now a developer" appears
#   2. Settings → Device Preferences → Developer Options
#      Enable "USB Debugging" (or "ADB Debugging")
#   3. Note your TV's IP: Settings → Network & Internet → your WiFi network
#
# USAGE:
#   chmod +x prismplus-tv-setup.sh
#   ./prismplus-tv-setup.sh
#
# RECOVERY (if something goes wrong):
#   adb shell pm install-existing com.google.android.tvlauncher
#   adb shell pm enable com.google.android.tvlauncher
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

TV_IP=""                        # Leave blank to be prompted, or hardcode e.g. "192.168.1.50"
AT4K_APK=""                     # Leave blank to download automatically
AT4K_PKG="com.overdevs.at4k"
AT4K_APKMIRROR_URL="https://www.apkmirror.com/apk/cute-little-apps/at4k-launcher-android-tv/"

STOCK_LAUNCHER="com.google.android.tvlauncher"

# Streaming apps to ensure are installed
# install-existing works if the app has ever been on your Google account.
# If not, the script opens the Play Store page for a single-tap install.
STREAMING_APPS=(
    "com.netflix.ninja"                  # Netflix
    "com.amazon.amazonvideo.livingroom"  # Prime Video
    "com.apple.atve.sony.appletv"        # Apple TV (Android TV / SG)
    "com.google.android.youtube.tv"     # YouTube
    "com.plexapp.android"               # Plex
    "com.disney.disneyplus"             # Disney+
)

DEBLOAT_PACKAGES=(
    com.google.android.tvrecommendations   # Home screen ads / recommendation rows
    com.google.android.tv                  # Live Channels app
    com.google.android.play.games          # Play Games
    com.google.android.youtube.tvmusic     # YouTube Music
    com.google.android.katniss            # Google Assistant TV
    com.google.android.katniss.gsa        # Google Assistant IME
    com.google.android.tungsten.setupwraith # Setup wizard (already done)
    com.google.android.partnersetup        # OEM telemetry shim
    com.google.android.leanbacklauncher.games # Sample games row
    com.mediacorp.mewatch                  # meWATCH (SG preload)
    com.viu.tv                             # Viu (SG preload)
)

# ── Colours ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[+]${RESET} $*"; }
ok()   { echo -e "${GREEN}[✓]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[✗]${RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

header() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}  $*${RESET}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# ── Preflight ─────────────────────────────────────────────────────────────────

header "Prism+ TV Setup — Preflight"

# Check adb — handle adb-enhanced installs where adb may not be in PATH directly
ADB_BIN=""

if command -v adb &>/dev/null; then
    ADB_BIN="adb"
else
    warn "adb not found in PATH — checking for adb-enhanced (adbe)..."

    if command -v adbe &>/dev/null; then
        ok "adbe found — locating underlying adb binary..."

        BREW_PREFIX="$(brew --prefix 2>/dev/null || echo '/opt/homebrew')"

        # Candidate locations, in priority order
        ADB_CANDIDATES=(
            "${BREW_PREFIX}/bin/adb"
            "/usr/local/bin/adb"
            "${BREW_PREFIX}/Caskroom/android-platform-tools/latest/platform-tools/adb"
        )

        # Also search the brew cellar dynamically
        CELLAR_MATCH="$(find "${BREW_PREFIX}/Cellar/android-platform-tools" \
            -name adb -type f 2>/dev/null | sort -V | tail -1)"
        [[ -n "$CELLAR_MATCH" ]] && ADB_CANDIDATES+=("$CELLAR_MATCH")

        # Also check adbe's own libexec for a bundled adb
        ADBE_PATH="$(command -v adbe)"
        ADBE_LIBEXEC="$(dirname "$(dirname "$ADBE_PATH")")/libexec"
        ADBE_ADB="$(find "$ADBE_LIBEXEC" -name adb -type f 2>/dev/null | head -1)"
        [[ -n "$ADBE_ADB" ]] && ADB_CANDIDATES+=("$ADBE_ADB")

        log "Searching candidate paths:"
        for candidate in "${ADB_CANDIDATES[@]}"; do
            if [[ -x "$candidate" ]]; then
                ADB_BIN="$candidate"
                ok "  Found: $candidate"
                break
            else
                warn "  Not found: $candidate"
            fi
        done

        if [[ -z "$ADB_BIN" ]]; then
            echo ""
            err "Could not locate adb binary. adb-enhanced does not bundle adb."
            echo "  Fix with:"
            echo ""
            echo "    brew install android-platform-tools"
            echo ""
            die "Re-run this script after installing android-platform-tools."
        fi
    else
        die "Neither adb nor adbe found. Install via: brew install android-platform-tools"
    fi
fi

ok "adb found: $("$ADB_BIN" version | head -1)"
ok "adb path:  $ADB_BIN"

# Check curl (for optional APK download)
if ! command -v curl &>/dev/null; then
    warn "curl not found — APK auto-download unavailable"
fi

# Resolve TV IP
if [[ -z "$TV_IP" ]]; then
    read -rp "$(echo -e "${CYAN}Enter TV IP address:${RESET} ")" TV_IP
fi
[[ -n "$TV_IP" ]] || die "TV IP cannot be empty"

# Resolve AT4K APK — only needed if not already installed on the device.
# We defer the check until after connecting; just resolve the path for now.
if [[ -z "$AT4K_APK" ]]; then
    AT4K_APK="$(dirname "$0")/at4k-launcher.apk"
fi

# ── Connect ───────────────────────────────────────────────────────────────────

header "Connecting to TV"

log "Connecting to ${TV_IP}:5555 ..."
adb disconnect &>/dev/null || true
sleep 1

connect_output=$("$ADB_BIN" connect "${TV_IP}:5555" 2>&1)
log "$connect_output"

# Wait for device — TV may prompt to accept RSA key
log "Waiting for device authorisation (accept the prompt on your TV if shown)..."
timeout=30
elapsed=0
while ! "$ADB_BIN" -s "${TV_IP}:5555" shell echo ok &>/dev/null; do
    sleep 2
    elapsed=$((elapsed + 2))
    if [[ $elapsed -ge $timeout ]]; then
        die "Timed out waiting for device. Check IP, USB Debugging is enabled, and accept the RSA key prompt on the TV."
    fi
done
ok "Device connected and authorised"

ADB="${ADB_BIN} -s ${TV_IP}:5555"

# Verify it's the right device
MODEL=$($ADB shell getprop ro.product.model 2>/dev/null | tr -d '\r')
ANDROID_VER=$($ADB shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
ok "Device: ${MODEL} — Android ${ANDROID_VER}"

# macOS-compatible timeout wrapper (timeout(1) isn't available by default)
# Uses gtimeout if installed (brew install coreutils), otherwise a bg-job approach.
run_with_timeout() {
    local secs=$1; shift
    if command -v gtimeout &>/dev/null; then
        gtimeout "$secs" "$@"
    elif command -v timeout &>/dev/null; then
        timeout "$secs" "$@"
    else
        # Pure bash fallback: run in background, kill after N seconds
        "$@" &
        local pid=$!
        ( sleep "$secs"; kill "$pid" 2>/dev/null ) &
        local watcher=$!
        wait "$pid" 2>/dev/null
        local rc=$?
        kill "$watcher" 2>/dev/null
        wait "$watcher" 2>/dev/null
        return $rc
    fi
}

# ── Streaming Apps ────────────────────────────────────────────────────────────

header "Installing Streaming Apps"

for pkg in "${STREAMING_APPS[@]}"; do
    pkg="${pkg%% #*}"; pkg="$(echo "$pkg" | xargs)"
    [[ -z "$pkg" ]] && continue

    if $ADB shell pm list packages 2>/dev/null | grep -q "^package:${pkg}$"; then
        ok "Already installed: ${pkg}"
        continue
    fi

    log "Trying install-existing: ${pkg} (timeout 15s)..."
    result=$(run_with_timeout 15 $ADB shell cmd package install-existing "$pkg" 2>&1 | tr -d '\r') || true

    if $ADB shell pm list packages 2>/dev/null | grep -q "^package:${pkg}$"; then
        ok "Installed via account: ${pkg}"
    else
        warn "Not in account — opening Play Store on TV for: ${pkg}"
        # Use explicit component to reliably open Play Store on Android TV
        $ADB shell am start \
            -n com.android.vending/com.google.android.finsky.tvmainactivity.TvMainActivity \
            -a android.intent.action.VIEW \
            -d "market://details?id=${pkg}" 2>/dev/null \
        || $ADB shell am start \
            -a android.intent.action.VIEW \
            -d "https://play.google.com/store/apps/details?id=${pkg}" 2>/dev/null \
        || warn "Could not open Play Store — install ${pkg} manually on the TV"

        echo ""
        echo -e "  ${YELLOW}App: ${pkg}${RESET}"
        echo -e "  ${YELLOW}→  Check your TV and press Install, then press Enter here to continue...${RESET}"
        read -r

        if $ADB shell pm list packages 2>/dev/null | grep -q "^package:${pkg}$"; then
            ok "Confirmed installed: ${pkg}"
        else
            warn "Still not detected — skipping and continuing (install manually later)"
        fi
    fi
done

# ── Install AT4K ──────────────────────────────────────────────────────────────

header "Installing AT4K Launcher"

if $ADB shell pm list packages 2>/dev/null | grep -q "^package:${AT4K_PKG}$"; then
    ok "AT4K already installed — skipping APK install"
else
    if [[ ! -f "$AT4K_APK" ]]; then
        warn "AT4K not on device and no APK found alongside this script."
        echo ""
        echo -e "  Download the latest APK from APKMirror:"
        echo -e "  ${CYAN}${AT4K_APKMIRROR_URL}${RESET}"
        echo -e "  Save it as ${BOLD}at4k-launcher.apk${RESET} in the same directory as this script."
        echo ""
        read -rp "Press Enter once the APK is in place, or Ctrl+C to abort..."
        [[ -f "$AT4K_APK" ]] || die "APK still not found at: $AT4K_APK"
    fi
    log "Installing AT4K Launcher from APK..."
    $ADB install -r "$AT4K_APK"
    ok "AT4K Launcher installed"
fi

# Brief pause to let the package manager settle
sleep 2

# Set AT4K as default home activity
log "Setting AT4K as default launcher..."
$ADB shell cmd package set-home-activity "${AT4K_PKG}/.MainActivity" 2>/dev/null || true

# ── Disable Stock Launcher ────────────────────────────────────────────────────

header "Disabling Stock Launcher"

log "Disabling ${STOCK_LAUNCHER} ..."
if $ADB shell pm disable-user --user 0 "$STOCK_LAUNCHER" 2>&1 | grep -q "disabled"; then
    ok "Stock launcher disabled"
else
    warn "Could not disable stock launcher via pm — trying uninstall for user..."
    $ADB shell pm uninstall -k --user 0 "$STOCK_LAUNCHER" 2>/dev/null || \
        warn "Could not remove stock launcher — it may already be disabled or absent"
fi

# ── Debloat ───────────────────────────────────────────────────────────────────

header "Debloating"

pass=0; skip=0; fail=0

for pkg in "${DEBLOAT_PACKAGES[@]}"; do
    # Strip inline comments
    pkg="${pkg%% #*}"
    pkg="${pkg%%	#*}"
    pkg="$(echo "$pkg" | xargs)"
    [[ -z "$pkg" ]] && continue

    if ! $ADB shell pm list packages 2>/dev/null | grep -q "^package:${pkg}$"; then
        warn "Not found (skipping): ${pkg}"
        skip=$((skip + 1))
        continue
    fi

    result=$($ADB shell pm uninstall -k --user 0 "$pkg" 2>&1 | tr -d '\r')
    if echo "$result" | grep -q "Success\|DELETE_SUCCEEDED"; then
        ok "Removed: ${pkg}"
        pass=$((pass + 1))
    else
        warn "Could not remove (may already be gone): ${pkg} — ${result}"
        fail=$((fail + 1))
    fi
done

# ── Settings Tweaks ───────────────────────────────────────────────────────────

header "Applying System Settings"

log "Disabling home panel / sponsored content..."
$ADB shell settings put global tv_home_panel_enabled 0 2>/dev/null && ok "tv_home_panel_enabled → 0" || warn "Could not set tv_home_panel_enabled"

log "Disabling background data for Play Store recommendations..."
$ADB shell settings put global always_finish_activities 0 2>/dev/null || true

# Limit background processes to reduce memory pressure on ATV10 hardware
log "Setting background process limit..."
$ADB shell settings put global max_running_processor_size 2 2>/dev/null || true

# ── Reboot ────────────────────────────────────────────────────────────────────

header "Done — Rebooting TV"

echo -e "${GREEN}${BOLD}"
echo "  Debloat summary:"
echo "    Removed : ${pass}"
echo "    Skipped : ${skip}"
echo "    Failed  : ${fail}"
echo -e "${RESET}"

log "Rebooting in 3 seconds..."
sleep 3
$ADB shell reboot

echo ""
ok "TV is rebooting. It will come up directly into AT4K Launcher."
echo ""
echo -e "${YELLOW}POST-BOOT REMINDER:${RESET}"
echo "  • Open AT4K and arrange your apps: Netflix, Prime Video, Apple TV,"
echo "    YouTube, Plex — then hide everything else via long-press → Hide."
echo ""
echo -e "${YELLOW}AFTER ANY OTA UPDATE:${RESET}"
echo "  Re-run this script — Prism+ firmware updates can reinstate"
echo "  the stock launcher and some removed packages."
echo ""