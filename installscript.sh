#!/usr/bin/env sh
# APKG Installer - GP Team (modded)
# Installs apkg into /bin/apkg and prepares dependencies per distro.
# - Polite confirmation before doing anything (unless -y)
# - On Arch: temporary 'aurbuild' user to install yay, then cleanup
# - Colored output via printf
# - POSIX sh compatible

set -eu

APKG_URL="https://raw.githubusercontent.com/gpteamofficial/apkg/main/apkg"
APKG_DEST="/bin/apkg"

PKG_MGR=""
PKG_FAMILY=""
AUR_USER_CREATED=0
AUTO_YES=0

# --------------- colors (TTY-safe) ---------------

if [ -t 2 ] && [ "${NO_COLOR:-0}" = "0" ]; then
  C_RESET="$(printf '\033[0m')"
  C_INFO="$(printf '\033[1;34m')"  # blue
  C_WARN="$(printf '\033[1;33m')"  # yellow
  C_ERR="$(printf '\033[1;31m')"   # red
  C_OK="$(printf '\033[1;32m')"    # green
else
  C_RESET=''
  C_INFO=''
  C_WARN=''
  C_ERR=''
  C_OK=''
fi

# --------------- helpers ---------------

log() {
  printf '%s[apkg-installer]%s %s\n' "$C_INFO" "$C_RESET" "$*" >&2
}

warn() {
  printf '%s[apkg-installer][WARN]%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2
}

ok() {
  printf '%s[apkg-installer][OK]%s %s\n' "$C_OK" "$C_RESET" "$*" >&2
}

fail() {
  printf '%s[apkg-installer][ERROR]%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s [OPTIONS]\n' "$0"
  printf '\nOptions:\n'
  printf '  -y, --yes, --assume-yes   Run non-interactively (assume "yes" to prompts)\n'
  printf '  -h, --help                Show this help and exit\n'
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "This installer must be run as root. Try: sudo $0"
  fi
}

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt-get"
    PKG_FAMILY="debian"
  elif command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
    PKG_FAMILY="debian"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    PKG_FAMILY="redhat"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    PKG_FAMILY="redhat"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
    PKG_FAMILY="suse"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_FAMILY="alpine"
  else
    PKG_MGR=""
    PKG_FAMILY=""
  fi
}

ask_confirmation() {
  # $1 = message, $2 = default (Y/N, optional, default N)
  msg=$1
  default=${2:-N}

  # non-interactive mode: always yes
  if [ "$AUTO_YES" -eq 1 ]; then
    log "AUTO_YES enabled; auto-confirming: $msg"
    return 0
  fi

  case "$default" in
    Y|y)
      prompt="[Y/n]"
      def="Y"
      ;;
    *)
      prompt="[y/N]"
      def="N"
      ;;
  esac

  printf '%s[apkg-installer][PROMPT]%s %s %s ' "$C_WARN" "$C_RESET" "$msg" "$prompt" >&2
  if ! read -r ans </dev/tty; then
    return 1
  fi

  if [ -z "$ans" ]; then
    ans="$def"
  fi

  case "$ans" in
    Y|y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr

  if [ -z "$PKG_MGR" ]; then
    fail "No supported package manager found to install curl (pacman/apt/dnf/yum/zypper/apk). Install curl or wget manually and rerun."
  fi

  log "Neither curl nor wget found. Installing curl using ${PKG_MGR}..."

  case "$PKG_FAMILY" in
    debian)
      "$PKG_MGR" update -y 2>/dev/null || "$PKG_MGR" update || true
      "$PKG_MGR" install -y curl
      ;;
    arch)
      pacman -Sy --noconfirm curl
      ;;
    redhat)
      "$PKG_MGR" install -y curl
      ;;
    suse)
      zypper refresh || true
      zypper install -y curl
      ;;
    alpine)
      apk update || true
      apk add curl
      ;;
    *)
      fail "Unsupported package manager family '${PKG_FAMILY}' for installing curl."
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    fail "Failed to install curl. Please install curl or wget manually, then rerun."
  fi

  ok "curl (or wget) is now available."
}

download_apkg() {
  tmpfile="$(mktemp /tmp/apkg.XXXXXX.sh)"

  if command -v curl >/dev/null 2>&1; then
    log "Downloading APKG using curl..."
    if ! curl -fsSL "$APKG_URL" -o "$tmpfile"; then
      rm -f "$tmpfile"
      fail "Failed to download APKG (curl)."
    fi
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading APKG using wget..."
    if ! wget -qO "$tmpfile" "$APKG_URL"; then
      rm -f "$tmpfile"
      fail "Failed to download APKG (wget)."
    fi
  else
    rm -f "$tmpfile"
    fail "Neither curl nor wget available after installation step. Aborting."
  fi

  if [ ! -s "$tmpfile" ]; then
    rm -f "$tmpfile"
    fail "Downloaded file is empty. Check network or APKG_URL."
  fi

  ok "APKG script downloaded to temporary file."
  printf '%s\n' "$tmpfile"
}

install_apkg() {
  src=$1

  log "Installing APKG to ${APKG_DEST} ..."
  mkdir -p "$(dirname "$APKG_DEST")"

  mv "$src" "$APKG_DEST"
  chmod 0755 "$APKG_DEST"

  ok "APKG installed successfully at: ${APKG_DEST}"
}

install_yay_arch() {
  # Only for Arch-like systems with pacman
  if ! command -v pacman >/dev/null 2>&1; then
    return 0
  fi

  if command -v yay >/dev/null 2>&1; then
    ok "Detected 'yay' already installed; skipping AUR helper installation."
    return 0
  fi

  log "Preparing temporary AUR build user 'aurbuild' to install yay..."

  if id -u aurbuild >/dev/null 2>&1; then
    warn "User 'aurbuild' already exists; will reuse it and NOT remove it afterwards."
    AUR_USER_CREATED=0
  else
    useradd -m -r -s /bin/bash aurbuild
    AUR_USER_CREATED=1
    ok "Temporary user 'aurbuild' created."
  fi

  log "Ensuring base-devel and git are installed via pacman..."
  pacman -Sy --needed --noconfirm base-devel git

  log "Switching to 'aurbuild' to build and install yay from AUR..."
  # نستخدم here-doc عشان نخلي الأوامر تشتغل جوّا شيل اليوزر الجديد
  su - aurbuild <<'EOF'
set -eu
workdir="$(mktemp -d /tmp/yay.XXXXXX)"
cd "$workdir"
git clone --depth=1 https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si --noconfirm
EOF

  ok "yay has been installed."

  if [ "$AUR_USER_CREATED" -eq 1 ]; then
    log "Cleaning up temporary user 'aurbuild' and its home directory..."
    if userdel -r aurbuild 2>/dev/null; then
      ok "Temporary user 'aurbuild' removed."
    else
      warn "Failed to remove user 'aurbuild'; please remove it manually if not needed."
    fi
  else
    warn "Not removing existing 'aurbuild' user (it existed before running this script)."
  fi

  ok "Returned from temporary user; continuing as root."
}

print_summary() {
  printf '\n%sAPKG installation completed.%s\n\n' "$C_OK" "$C_RESET"
  printf 'Binary location:\n  %s\n\n' "$APKG_DEST"
  printf 'Basic usage:\n'
  printf '  apkg help\n'
  printf '  apkg update\n'
  printf '  apkg full-upgrade\n'
  printf '  apkg install <package>\n'
  printf '  apkg remove <package>\n\n'
  printf 'APKG is a unified package manager interface by GP Team.\n'
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -y|--yes|--assume-yes)
        AUTO_YES=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        warn "Unknown option: $1"
        ;;
    esac
    shift
  done
}

# --------------- main ---------------

main() {
  parse_args "$@"
  detect_pkg_mgr

  log "Welcome to the APKG installer."

  log "Planned actions:"
  log "  - Ensure curl or wget is installed."
  log "  - Download APKG from: $APKG_URL"
  log "  - Install APKG to:   $APKG_DEST"
  if [ "$PKG_FAMILY" = "arch" ]; then
    log "  - (Arch) Create a temporary user 'aurbuild' to install yay, then clean it up."
  fi

  if ! ask_confirmation "Do you want to continue with these actions?" "N"; then
    warn "Installation aborted by user; nothing was changed."
    exit 0
  fi

  require_root
  install_curl_if_needed

  if [ "$PKG_FAMILY" = "arch" ]; then
    install_yay_arch
  fi

  tmpfile="$(download_apkg)"
  install_apkg "$tmpfile"
  print_summary
}

main "$@"
