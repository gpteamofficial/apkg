<<<<<<< HEAD
#!/usr/bin/env bash
# VOPK Bootstrap Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/bootstrap.sh | bash -s -- -y
#   wget -qO-  https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/bootstrap.sh | bash -s -- -y
set -Eeuo pipefail

# -------------------- configuration --------------------
REPO="${VOPK_REPO:-gpteamofficial/vopk}"
REF="${VOPK_REF:-main}"                          # branch/tag/commit
BACKEND_PATH="${VOPK_BACKEND_PATH:-src/installscript.sh}"

BACKEND_URL="${VOPK_BACKEND_URL:-https://raw.githubusercontent.com/${REPO}/${REF}/${BACKEND_PATH}}"

# Keep downloaded backend for debugging:
#   VOPK_KEEP=1 curl ... | bash
KEEP="${VOPK_KEEP:-0}"

# Download only (prints path and exits):
#   VOPK_DOWNLOAD_ONLY=1 curl ... | bash
DOWNLOAD_ONLY="${VOPK_DOWNLOAD_ONLY:-0}"

# -------------------- helpers --------------------
log()  { printf '[vopk-bootstrap] %s\n' "$*" >&2; }
die()  { printf '[vopk-bootstrap][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

download_to() {
  local url="$1" out="$2"
  if have curl; then
    curl -fsSL "$url" -o "$out" || return 1
  elif have wget; then
    wget -qO "$out" "$url" || return 1
  else
    return 2
  fi
}

run_as_root() {
  local script="$1"; shift
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$script" "$@"
  elif have sudo; then
    sudo -E "$script" "$@"
  elif have doas; then
    doas "$script" "$@"
  else
    die "Need root privileges but neither 'sudo' nor 'doas' is available. Re-run as root."
  fi
}

# -------------------- main --------------------
main() {
  local tmp
  tmp="$(mktemp -t vopk-installer.XXXXXX)" || die "mktemp failed"

  cleanup() {
    local ec=$?
    if [[ "$KEEP" == "1" || "$DOWNLOAD_ONLY" == "1" ]]; then
      log "Keeping backend installer at: $tmp"
    else
      rm -f "$tmp" 2>/dev/null || true
    fi
    exit "$ec"
  }
  trap cleanup EXIT

  log "Downloading VOPK backend installer..."
  log "  URL: $BACKEND_URL"

  if ! download_to "$BACKEND_URL" "$tmp"; then
    if ! have curl && ! have wget; then
      die "Neither 'curl' nor 'wget' is installed. Install one of them and retry."
    fi
    die "Failed to download backend installer."
  fi

  [[ -s "$tmp" ]] || die "Downloaded backend installer is empty."
  chmod +x "$tmp" || die "Failed to chmod backend installer."

  if [[ "$DOWNLOAD_ONLY" == "1" ]]; then
    printf '%s\n' "$tmp"
    return 0
  fi

  log "Running VOPK backend installer as root..."
  run_as_root "$tmp" "$@"
}

main "$@"
=======
vopk_tmp="$(mktemp)"; curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/installscript.sh -o "$vopk_tmp" && chmod +x "$vopk_tmp" && sudo -E "$vopk_tmp"; rm -f "$vopk_tmp"
>>>>>>> 21151aa (Major Update: 2.0.0 Xia)
