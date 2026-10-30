
#!/usr/bin/env bash
#
# clean-vietnamese-ime.sh
# Remove selected Vietnamese input methods on Kubuntu / Linux Mint.
# IMPORTANT: Keep the Fcitx5 framework installed.
#

set -Eeuo pipefail

VERSION="1.0.0"
LOG_DIR="${HOME}/.local/state/clean-vietnamese-ime"
LOG_FILE="${LOG_DIR}/clean-$(date +%Y%m%d-%H%M%S).log"

AUTO_YES=0
SCAN_ONLY=0
AUTO_REMOVE=0

TARGET_REGEX='^(ibus-[^[:space:]]*(bamboo|unikey)|fcitx5-[^[:space:]]*(lotus|ngosen|vietfox))(:[^[:space:]]+)?$'

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
error() { echo "[ERROR] $*" >&2; }

for arg in "$@"; do
    case "$arg" in
        --yes|-y) AUTO_YES=1 ;;
        --scan) SCAN_ONLY=1 ;;
        --autoremove) AUTO_REMOVE=1 ;;
        --help|-h)
            cat <<EOF
Clean Vietnamese Input Methods v${VERSION}

Usage:
  $0              Scan and ask before removing
  $0 --scan       Scan only, make no changes
  $0 --yes        Remove without confirmation
  $0 --autoremove Also run apt autoremove --purge
  $0 --help       Show help

The Fcitx5 framework is protected.
EOF
            exit 0
            ;;
        *)
            error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    error "Do not run this script with sudo."
    error "Run as your normal desktop user."
    exit 1
fi

if ! command -v dpkg-query >/dev/null 2>&1; then
    error "This script requires a Debian/Ubuntu-based system."
    exit 1
fi

echo
echo "============================================"
echo "  CLEAN VIETNAMESE INPUT METHODS v${VERSION}"
echo "============================================"
echo

. /etc/os-release
info "Operating system: ${PRETTY_NAME:-Unknown}"
info "User: ${USER}"
info "Fcitx5 framework will be preserved."
echo

# ------------------------------------------------
# 1. Detect installed target packages
# ------------------------------------------------

info "[1/5] Scanning installed packages..."

mapfile -t TARGET_PACKAGES < <(
    dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' 2>/dev/null |
    awk '$2 == "installed" {print $1}' |
    grep -Ei "$TARGET_REGEX" |
    sort -u || true
)

if ((${#TARGET_PACKAGES[@]})); then
    echo
    echo "Packages found:"
    printf '  - %s\n' "${TARGET_PACKAGES[@]}"
else
    info "No target packages found."
fi

# ------------------------------------------------
# 2. Verify Fcitx5 framework
# ------------------------------------------------

info "[2/5] Checking Fcitx5 framework..."

FCITX5_PACKAGES=()

mapfile -t FCITX5_PACKAGES < <(
    dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' 2>/dev/null |
    awk '$2 == "installed" {print $1}' |
    grep -E '^fcitx5(:[^[:space:]]+)?$' || true
)

if ((${#FCITX5_PACKAGES[@]})); then
    info "Fcitx5 framework detected:"
    printf '  - %s\n' "${FCITX5_PACKAGES[@]}"
else
    warn "Base fcitx5 package not detected."
fi

# ------------------------------------------------
# 3. Scan leftover user files
# ------------------------------------------------

info "[3/5] Scanning user configuration leftovers..."

SEARCH_DIRS=(
    "$HOME/.config"
    "$HOME/.local/share"
    "$HOME/.local/bin"
    "$HOME/.cache"
)

LEFTOVERS=()

for dir in "${SEARCH_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue

    while IFS= read -r -d '' path; do
        LEFTOVERS+=("$path")
    done < <(
        find "$dir" -mindepth 1 -maxdepth 6 \
            \( -iname '*bamboo*' \
            -o -iname '*unikey*' \
            -o -iname '*lotus*' \
            -o -iname '*ngosen*' \
            -o -iname '*vietfox*' \) \
            -print0 2>/dev/null
    )
done

if ((${#LEFTOVERS[@]})); then
    echo
    echo "User leftovers found:"
    printf '  - %s\n' "${LEFTOVERS[@]}"
else
    info "No matching user leftovers found."
fi

# ------------------------------------------------
# 4. Scan only mode
# ------------------------------------------------

if [[ "$SCAN_ONLY" -eq 1 ]]; then
    echo
    info "Scan completed. No files or packages were changed."
    info "Log: $LOG_FILE"
    exit 0
fi

# ------------------------------------------------
# 5. Confirm and remove
# ------------------------------------------------

if ((${#TARGET_PACKAGES[@]} == 0 && ${#LEFTOVERS[@]} == 0)); then
    info "Nothing to clean."
    exit 0
fi

echo
echo "============================================"
echo "  CLEANUP SUMMARY"
echo "============================================"

echo "Packages to purge: ${#TARGET_PACKAGES[@]}"
echo "User leftovers:    ${#LEFTOVERS[@]}"
echo
echo "Protected: fcitx5 framework and other desktop components."
echo

if [[ "$AUTO_YES" -ne 1 ]]; then
    read -r -p "Continue cleanup? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || {
        info "Cancelled by user."
        exit 0
    }
fi

# Close input method processes if running.
info "Stopping selected input method processes..."

for process in ibus-daemon fcitx5; do
    if [[ "$process" == "fcitx5" ]]; then
        # Do not stop the active Fcitx5 framework.
        continue
    fi
    pkill -x "$process" 2>/dev/null || true
done

# Purge target packages only.
if ((${#TARGET_PACKAGES[@]})); then
    info "Purging selected packages..."

    if [[ "$AUTO_YES" -eq 1 ]]; then
        sudo apt-get purge -y "${TARGET_PACKAGES[@]}"
    else
        sudo apt-get purge "${TARGET_PACKAGES[@]}"
    fi
else
    info "No packages require purging."
fi

# Remove only explicitly matched user leftovers.
if ((${#LEFTOVERS[@]})); then
    info "Removing matching user configuration leftovers..."

    for path in "${LEFTOVERS[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            rm -rf -- "$path"
            info "Removed: $path"
        fi
    done
fi

# Optional orphan dependency cleanup.
if [[ "$AUTO_REMOVE" -eq 1 ]]; then
    info "Running apt autoremove --purge..."

    if [[ "$AUTO_YES" -eq 1 ]]; then
        sudo apt-get autoremove --purge -y
    else
        sudo apt-get autoremove --purge
    fi
else
    info "Skipping autoremove to protect unrelated packages."
fi

# ------------------------------------------------
# Final verification
# ------------------------------------------------

echo
echo "============================================"
echo "  FINAL VERIFICATION"
echo "============================================"

REMAINING=()

mapfile -t REMAINING < <(
    dpkg-query -W -f='${binary:Package}\t${db:Status-Status}\n' 2>/dev/null |
    awk '$2 == "installed" {print $1}' |
    grep -Ei "$TARGET_REGEX" || true
)

if ((${#REMAINING[@]})); then
    warn "Some target packages remain:"
    printf '  - %s\n' "${REMAINING[@]}"
else
    info "All targeted packages have been removed."
fi

if dpkg-query -W -f='${db:Status-Status}' fcitx5 2>/dev/null | grep -qx installed; then
    info "Fcitx5 framework: STILL INSTALLED."
else
    warn "Fcitx5 base package is not installed or was not detected."
fi

echo
info "Cleanup completed."
info "Log file: $LOG_FILE"
echo
echo "Please log out and log back in to refresh input method settings."
