#!/usr/bin/env bash
set -euo pipefail
export TERM=${TERM:-linux}
LOGFILE="/var/log/omvscript.log"
REPO_RAW_BASE="https://raw.githubusercontent.com/omvlabs/OmVScript/main"
log(){ echo "$(date --iso-8601=seconds) $*" | tee -a "$LOGFILE"; }

ensure_docker(){ command -v docker >/dev/null 2>&1 || { log "Docker missing; run Docker module first"; exit 1; } }

read -r -d '' NAS_APPS <<'EOF' || true
openmediavault|OpenMediaVault — Debian-based NAS (recommended: install on a fresh Debian system)
trueNAS|TrueNAS CORE — FreeBSD-based, not Linux; cannot be installed by this script
nextcloud|Nextcloud — File sync/sharing (docker-compose recommended)
minio|MinIO — S3-compatible object storage
duplicati|Duplicati — Backup client/server
syncthing|Syncthing — P2P file sync
EOF

filter_nas(){
  local q="$1"
  IFS=$'\n' read -r -a lines <<< "$NAS_APPS"
  matches=()
  for line in "${lines[@]}"; do
    if echo "$line" | grep -qi -- "$q"; then
      id=$(echo "$line" | cut -d'|' -f1)
      desc=$(echo "$line" | cut -d'|' -f2)
      matches+=("$id" "$desc")
    fi
  done
  echo "${matches[@]:-}"
}

interactive_nas_search(){
  if command -v whiptail >/dev/null 2>&1 && { [ -t 0 ] || [ -c /dev/tty ]; }; then
    q=$(whiptail --inputbox "Search NAS apps (openmediavault, minio...). Leave empty to list all." 10 60 "" 3>&1 1>&2 2>&3) || return 1
  else
    read -rp "Search NAS apps (empty=all): " q
  fi
  mapfile -t arr < <(filter_nas "$q")
  if [ ${#arr[@]} -eq 0 ]; then
    [ -n "$q" ] && { log "No matches for $q"; }
    return 2
  fi

  checklist=()
  for ((i=0;i<${#arr[@]};i+=2)); do
    checklist+=("${arr[i]}" "${arr[i+1]}" "OFF")
  done

  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    sel=$(whiptail --title "Select NAS apps" --checklist "Choose NAS apps to deploy/install" 20 80 12 "${checklist[@]}" 3>&1 1>&2 2>&3) || return 1
  else
    echo "Matches:"
    idx=1; declare -A idx_to_tag
    for ((i=0;i<${#arr[@]};i+=2)); do
      echo "[$idx] ${arr[i+1]}"
      idx_to_tag[$idx]="${arr[i]}"
      ((idx++))
    done
    read -rp "Enter numbers (space separated) or 'c' to cancel: " -a nums
    [ "${nums[0]}" = "c" ] && return 1
    seltags=()
    for n in "${nums[@]}"; do seltags+=("${idx_to_tag[$n]}"); done
    sel=$(printf '"%s" ' "${seltags[@]}")
  fi

   eval "sel_arr=($sel)"
   # shellcheck disable=SC2154
   for item in "${sel_arr[@]}"; do
    case "$item" in
      openmediavault)
        if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
          if whiptail --yesno "OpenMediaVault is best installed on a fresh Debian host. Do you want to view the official instructions?" 12 70; then
            whiptail --msgbox "Official OMV: https://www.openmediavault.org" 8 60
          fi
        else
          echo "OMV: https://www.openmediavault.org"
        fi
        ;;
      trueNAS)
        if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
          whiptail --msgbox "TrueNAS CORE is FreeBSD-based — cannot be installed by OmVScript. Use official TrueNAS installers." 10 60
        else
          echo "TrueNAS is FreeBSD-based; see official site: https://www.truenas.com"
        fi
        ;;
      nextcloud|minio|duplicati|syncthing)
        # delegate to docker-images deployer
        tmp="$(mktemp)"
        curl -fsSL "${REPO_RAW_BASE}/modules/docker/docker-images.sh" -o "$tmp"
        # shellcheck source=/dev/null
        . "$tmp"
        deploy_image "$item" || log "Failed to deploy $item"
        rm -f "$tmp"
        ;;
      *)
        log "Unknown NAS app: $item"
        ;;
    esac
  done
}

main(){
  ensure_docker
  while true; do
    interactive_nas_search || break
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
      whiptail --yesno "Deploy/select more NAS apps?" 8 50 || break
    else
      read -rp "More? [y/N]: " more; [[ "$more" =~ ^[Yy] ]] || break
    fi
  done
  log "NAS apps module finished."
}
main "$@"
