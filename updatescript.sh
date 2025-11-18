#!/usr/bin/env bash
# APKG Installer + Maintenance - GP Team
# Installs APKG and provides Repair / Reinstall / Delete / Delete+Backup / Update menu.

set -euo pipefail

APKG_URL="https://raw.githubusercontent.com/gpteamofficial/apkg/main/apkg.sh"
APKG_DEST="/bin/apkg"
APKG_BAK="/bin/apkg.bak"

PKG_MGR=""
PKG_FAMILY=""

# ------------------ helpers ------------------

log() {
  printf '[apkg-installer] %s\n' "$*" >&2
}

fail() {
  printf '[apkg-installer][ERROR] %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "This script must be run as root. Try: sudo $0"
  fi
}

detect_pkg_mgr() {
  if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
    PKG_FAMILY="arch"
  elif command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt-get"
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

install_curl_if_needed() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi

  detect_pkg_mgr

  if [ -z "${PKG_MGR}" ]; then
    fail "No supported package manager found to install curl (pacman/apt/dnf/yum/zypper/apk). Install curl or wget manually and rerun."
  fi

  log "Neither curl nor wget found. Installing curl using ${PKG_MGR}..."

  case "${PKG_FAMILY}" in
    debian)
      ${PKG_MGR} update -y || ${PKG_MGR} update || true
      ${PKG_MGR} install -y curl
      ;;
    arch)
      pacman -Sy --noconfirm curl
      ;;
    redhat)
      ${PKG_MGR} install -y curl
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
}

download_apkg() {
  tmpfile="$(mktemp /tmp/apkg.XXXXXX.sh)"

  if command -v curl >/dev/null 2>&1; then
    log "Downloading APKG using curl..."
    curl -fsSL "${APKG_URL}" -o "${tmpfile}"
  elif command -v wget >/dev/null 2>&1; then
    log "Downloading APKG using wget..."
    wget -qO "${tmpfile}" "${APKG_URL}"
  else
    fail "Neither curl nor wget available after installation step. Aborting."
  fi

  if [ ! -s "${tmpfile}" ]; then
    rm -f "${tmpfile}"
    fail "Downloaded file is empty. Check network or APKG_URL."
  fi

  echo "${tmpfile}"
}

install_apkg() {
  local src="$1"

  log "Installing APKG to ${APKG_DEST} ..."
  mkdir -p "$(dirname "${APKG_DEST}")"

  # backup old if exists
  if [ -f "${APKG_DEST}" ]; then
    log "Backing up existing APKG to ${APKG_BAK}"
    cp -f "${APKG_DEST}" "${APKG_BAK}" || true
  fi

  mv "${src}" "${APKG_DEST}"
  chmod 0755 "${APKG_DEST}"

  log "APKG installed successfully at: ${APKG_DEST}"
}

print_summary() {
  cat <<EOF

APKG installation completed.

Binary location:
  ${APKG_DEST}

Basic usage:
  apkg help
  apkg update
  apkg full-upgrade
  apkg install <package>
  apkg remove <package>

APKG is a unified package manager interface by GP Team.
EOF
}

# ------------------ operations ------------------

op_install() {
  log "Starting APKG fresh installation ..."
  install_curl_if_needed
  tmpfile="$(download_apkg)"
  install_apkg "${tmpfile}"
  print_summary
}

op_update() {
  if [ ! -f "${APKG_DEST}" ]; then
    log "APKG not found at ${APKG_DEST}. Performing fresh install instead of update."
    op_install
    return
  fi

  log "Updating existing APKG at ${APKG_DEST} ..."
  install_curl_if_needed
  tmpfile="$(download_apkg)"
  install_apkg "${tmpfile}"

  log "Update completed."
}

op_reinstall() {
  log "Reinstalling APKG ..."

  if [ -f "${APKG_DEST}" ]; then
    log "Removing existing APKG at ${APKG_DEST}"
    rm -f "${APKG_DEST}"
  fi

  install_curl_if_needed
  tmpfile="$(download_apkg)"
  install_apkg "${tmpfile}"

  log "Reinstall completed."
}

op_repair() {
  log "Repairing APKG installation ..."

  install_curl_if_needed

  local needs_fix=0

  if [ ! -f "${APKG_DEST}" ]; then
    log "APKG binary missing."
    needs_fix=1
  elif [ ! -s "${APKG_DEST}" ]; then
    log "APKG binary is empty."
    needs_fix=1
  elif [ ! -x "${APKG_DEST}" ]; then
    log "APKG binary is not executable. Fixing permissions..."
    chmod 0755 "${APKG_DEST}" || needs_fix=1
  fi

  # simple integrity check (is it a shell script?)
  if [ -f "${APKG_DEST}" ] && ! head -n1 "${APKG_DEST}" | grep -q "bash"; then
    log "APKG binary does not look like a shell script. Replacing..."
    needs_fix=1
  fi

  if [ "${needs_fix}" -eq 1 ]; then
    log "Re-downloading APKG to repair installation..."
    tmpfile="$(download_apkg)"
    install_apkg "${tmpfile}"
  else
    log "APKG binary looks fine. No reinstall needed."
  fi

  log "Repair step finished."
}

op_delete() {
  log "Deleting APKG ..."

  if [ -f "${APKG_DEST}" ]; then
    rm -f "${APKG_DEST}"
    log "Removed ${APKG_DEST}"
  else
    log "APKG not found at ${APKG_DEST}. Nothing to delete."
  fi

  log "Delete operation completed (backup kept at ${APKG_BAK} if exists)."
}

op_delete_all() {
  log "Deleting APKG and backup ..."

  if [ -f "${APKG_DEST}" ]; then
    rm -f "${APKG_DEST}"
    log "Removed ${APKG_DEST}"
  else
    log "APKG not found at ${APKG_DEST}."
  fi

  if [ -f "${APKG_BAK}" ]; then
    rm -f "${APKG_BAK}"
    log "Removed backup ${APKG_BAK}"
  else
    log "No backup file ${APKG_BAK} found."
  fi

  log "Delete + backup operation completed."
}

# ------------------ menu ------------------

show_menu() {
  cat <<EOF
Choose What You Want To Do:

1) Repair
2) Reinstall 
3) Delete
4) Delete and delete backup
5) Update

0) Exit
[INPUT] ->:
EOF
}

# ------------------ main ------------------

main() {
  require_root

  # subcommands support
  if [ "$#" -ge 1 ]; then
    cmd="$1"
    shift || true
    case "${cmd}" in
      install)
        op_install
        exit 0
        ;;
      update)
        op_update
        exit 0
        ;;
      reinstall)
        op_reinstall
        exit 0
        ;;
      repair)
        op_repair
        exit 0
        ;;
      delete|remove|uninstall)
        op_delete
        exit 0
        ;;
      delete-all|delete_all)
        op_delete_all
        exit 0
        ;;
      menu)
        # fall through to interactive menu
        ;;
      *)
        fail "Unknown command '${cmd}'. Use: install | update | reinstall | repair | delete | delete-all | menu"
        ;;
    esac
  fi

  # interactive menu (default behavior)
  show_menu
  read -r choice

  case "${choice}" in
    1)
      op_repair
      ;;
    2)
      op_reinstall
      ;;
    3)
      op_delete
      ;;
    4)
      op_delete_all
      ;;
    5)
      op_update
      ;;
    0)
      log "Exiting..."
      exit 0
      ;;
    *)
      fail "Invalid choice '${choice}'. Please run again and choose between 0-5."
      ;;
  esac
}

main "$@"
