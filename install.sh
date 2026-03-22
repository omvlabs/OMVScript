#!/usr/bin/env bash
set -euo pipefail
export TERM=${TERM:-xterm-256color}
# OmVScript: bootstrap installer - updated to include searchable app selection
# Usage:
#  curl -fsSL https://raw.githubusercontent.com/omvlabs/OmVScript/main/install.sh -o /tmp/omvscript-install.sh
#  sudo bash /tmp/omvscript-install.sh

REPO_RAW_BASE="https://raw.githubusercontent.com/omvlabs/OmVScript/main"
LOGFILE="/var/log/omvscript.log"
TMPDIR="$(mktemp -d /tmp/omvscript.XXXX)"

log(){ echo "$(date --iso-8601=seconds) $*" | tee -a "$LOGFILE"; }
ensure_root(){
  [ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)"; exit 1; }
}

fetch_module(){
  local path="$1"
  local url="${REPO_RAW_BASE}/${path}"
  local out
  out="${TMPDIR}/$(basename "$path")"
  log "Downloading module: $url" >&2
  if ! curl -fsSL "$url" -o "$out"; then
    log "ERROR: failed to download $url" >&2
    return 1
  fi
  chmod +x "$out"
  echo "$out"
}

run_module(){
  local module_path="$1"
  log "----- MODULE: $(basename "$module_path") -----"
  head -n 50 "$module_path" >> "$LOGFILE" || true
   ( bash "$module_path" ) 2>&1 | tee -a "$LOGFILE"
   return "${PIPESTATUS[0]:-0}"
}

ensure_root

if ! [ -t 0 ] && ! [ -t 2 ]; then
  echo "Error: This script requires an interactive terminal. Please run directly, not via pipe." >&2
  exit 1
fi

if command -v whiptail >/dev/null 2>&1 && ([ -t 0 ] || [ -c /dev/tty ]); then
  choice=$(whiptail --title "OmVScript" --menu "Choose action" 20 80 12 \
    "1" "Ensure Docker is installed (recommended first)" \
    "2" "Install Developer Environment (search & select packages)" \
    "3" "Install Server Apps (search & deploy docker apps)" \
    "4" "Install NAS Apps (search & deploy docker apps / show installers)" \
    "5" "Install Docker Images (generic image deployer)" \
    "6" "Exit" 3>&1 1>&2 2>&3) || exit 0
else
  echo "OmVScript - choose one:"
  echo "1) Ensure Docker"
  echo "2) Developer Environment (search & select)"
  echo "3) Server Apps (search & deploy)"
  echo "4) NAS Apps (search & deploy)"
  echo "5) Docker Images (manual/custom)"
  echo "6) Exit"
  if [ -t 0 ]; then
    read -rp "Enter choice: " choice
  elif [ -c /dev/tty ]; then
    read -rp "Enter choice: " choice </dev/tty
  else
    echo "Error: whiptail not installed and no terminal available. Cannot accept input." >&2
    exit 1
  fi
fi

case "$choice" in
  1)
    m=$(fetch_module "modules/docker-check.sh") || exit 1
    run_module "$m"
    ;;
  2)
    m=$(fetch_module "modules/developer/dev-packages.sh") || exit 1
    run_module "$m"
    ;;
  3)
    m=$(fetch_module "modules/apps/server-apps.sh") || exit 1
    run_module "$m"
    ;;
  4)
    m=$(fetch_module "modules/apps/nas-apps.sh") || exit 1
    run_module "$m"
    ;;
  5)
    m=$(fetch_module "modules/docker/docker-images.sh") || exit 1
    run_module "$m"
    ;;
  6)
    log "Exit chosen"
    ;;
  *)
    log "Unknown choice"
    ;;
esac

rm -rf "$TMPDIR"
log "OmVScript finished."
exit 0
