#!/usr/bin/env bash
# VOPK Update Bootstrap (front-end)
# Downloads the maintenance script (updatescript.sh) and runs it locally as root.
#
# Examples:
#   curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/update-bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/update-bootstrap.sh | bash -s -- -y update
#   wget -qO-  https://raw.githubusercontent.com/gpteamofficial/vopk/main/src/update-bootstrap.sh | bash -s -- repair
set -Eeuo pipefail

# -------------------- config --------------------
REPO="${VOPK_REPO:-gpteamofficial/vopk}"
REF="${VOPK_REF:-main}" # branch/tag/commit
BACKEND_PATH="${VOPK_UPDATE_BACKEND_PATH:-src/updatescript.sh}"

BACKEND_URL="${VOPK_UPDATE_URL:-https://raw.githubusercontent.com/${REPO}/${REF}/${BACKEND_PATH}}"

# Debug knobs:
KEEP="${VOPK_KEEP:-0}"                 # keep downloaded backend file if 1
DOWNLOAD_ONLY="${VOPK_DOWNLOAD_ONLY:-0}" # print path and exit if 1

# -------------------- helpers --------------------
log() { printf '[vopk-update-bootstrap] %s\n' "$*" >&2; }
die() { printf '[vopk-update-bootstrap][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

download_to() {
  local url="$1" out="$2"
  if have curl; then
    curl -fsSL "$url" -o "$out"
  elif have wget; then
    wget -qO "$out" "$url"
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
  tmp="$(mktemp -t vopk-updater.XXXXXX)" || die "mktemp failed"

  cleanup() {
    local ec=$?
    if [[ "$KEEP" == "1" || "$DOWNLOAD_ONLY" == "1" ]]; then
      log "Keeping backend script at: $tmp"
    else
      rm -f "$tmp" 2>/dev/null || true
    fi
    exit "$ec"
  }
  trap cleanup EXIT

  log "Downloading VOPK maintenance script..."
  log "  URL: $BACKEND_URL"

  if ! download_to "$BACKEND_URL" "$tmp"; then
    if ! have curl && ! have wget; then
      die "Neither 'curl' nor 'wget' is installed. Install one of them and retry."
    fi
    die "Failed to download maintenance script."
  fi

  [[ -s "$tmp" ]] || die "Downloaded maintenance script is empty."
  chmod +x "$tmp" || die "Failed to chmod maintenance script."

  if [[ "$DOWNLOAD_ONLY" == "1" ]]; then
    printf '%s\n' "$tmp"
    return 0
  fi

  log "Running VOPK maintenance script as root..."
  # Important: Run it as 'sh' explicitly to match its shebang/compat goal
  run_as_root /usr/bin/env sh "$tmp" "$@"
}

main "$@"
