#!/usr/bin/env bash
set -euo pipefail
export TERM=${TERM:-linux}
# Server apps module — curated set of server applications; deploy via docker-images module
LOGFILE="/var/log/omvscript.log"
REPO_RAW_BASE="https://raw.githubusercontent.com/Omcodes23/OmVScript/main"
log(){ echo "$(date --iso-8601=seconds) $*" | tee -a "$LOGFILE"; }

ensure_docker(){
  command -v docker >/dev/null 2>&1 || { log "Docker missing; run Docker module first"; exit 1; }
}

# curated server stacks (id|desc)
read -r -d '' SERVER_APPS <<'EOF' || true
casaos|CasaOS — Home server GUI (Docker-based) (note: official installer recommended)
homeassistant|Home Assistant — Home automation (advanced; prefers supervised/install)
nextcloud|Nextcloud — Self-hosted file sync & sharing (complex; docker-compose recommended)
gitea|Gitea — Self-hosted Git service (via docker)
gitlab|GitLab CE — Full GitLab (heavy; consider official OmV or VM)
portainer|Portainer — Docker management UI
traefik|Traefik — Reverse proxy (advanced)
unifi|UniFi Controller — network device controller (image-based)
EOF

filter_server(){
  local q="$1"
  IFS=$'\n' read -r -a lines <<< "$SERVER_APPS"
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

choose_with_whiptail(){
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    whiptail "$@"
    return $?
  fi
  return 1
}

interactive_server_search(){
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    q=$(whiptail --inputbox "Search server apps (e.g., nextcloud, gitea). Leave empty to list all." 10 60 "" 3>&1 1>&2 2>&3) || return 1
  else
    read -rp "Search server apps (empty=all): " q
  fi
  mapfile -t arr < <(filter_server "$q")
  if [ ${#arr[@]} -eq 0 ]; then
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
      whiptail --msgbox "No matches found for '$q'." 8 50
    else
      echo "No matches for '$q'."
    fi
    return 2
  fi

  # prepare checklist
  checklist=()
  for ((i=0;i<${#arr[@]};i+=2)); do
    tag="${arr[i]}"
    label="${arr[i+1]}"
    checklist+=("$tag" "$label" "OFF")
  done

  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    sel=$(whiptail --title "Select server apps" --checklist "Select one or more server apps to deploy (will call docker-images module)" 20 80 12 "${checklist[@]}" 3>&1 1>&2 2>&3) || return 1
  else
    echo "Matches:"
    idx=1
    declare -A idx_to_tag
    for ((i=0;i<${#arr[@]};i+=2)); do
      tag="${arr[i]}"; label="${arr[i+1]}"
      echo "[$idx] $label"
      idx_to_tag[$idx]="$tag"
      ((idx++))
    done
    read -rp "Enter numbers separated by spaces (or 'c' to cancel): " -a nums
    if [ "${nums[0]}" = "c" ]; then return 1; fi
    seltags=()
    for n in "${nums[@]}"; do seltags+=("${idx_to_tag[$n]}"); done
    sel=$(printf '"%s" ' "${seltags[@]}")
  fi

  # call docker-images module for each selection
  eval "sel_arr=($sel)"
  for item in "${sel_arr[@]}"; do
    case "$item" in
      casaos)
        # CasaOS has its official installer; we'll offer a safe automated docker-based approach
        if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
          if whiptail --yesno "CasaOS official installer may perform advanced actions. Do you want OmVScript to attempt a Docker-based CasaOS install?" 12 80; then
            # CasaOS docker-compose quick deploy (lightweight)
            bash -c "curl -fsSL https://raw.githubusercontent.com/IceWhaleTech/CasaOS/main/install.sh | bash" || log "CasaOS install failed or user aborted."
          else
            log "User skipped CasaOS automated install."
          fi
        else
          echo "CasaOS installer requires user interaction. Visit https://github.com/IceWhaleTech/CasaOS"
        fi
        ;;
      homeassistant)
        log "Home Assistant is advanced; recommending official install: https://www.home-assistant.io/installation/"
        if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
          whiptail --msgbox "Home Assistant recommended installation: https://www.home-assistant.io/installation/" 12 80
        else
          echo "See https://www.home-assistant.io/installation/"
        fi
        ;;
      nextcloud)
        log "Nextcloud is complex. You can deploy it via docker-compose (not auto-installed by OmVScript)."
        if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
          whiptail --msgbox "Nextcloud installation is complex — consider using the official docker-compose instructions: https://nextcloud.com/install/#instructions-server" 12 80
        else
          echo "See Nextcloud official docs."
        fi
        ;;
      *)
        # for simpler server apps, call docker images module with the short name
        # fetch docker-images module temporarily and call deploy_image with short name
        tmp="$(mktemp)"
        curl -fsSL "${REPO_RAW_BASE}/modules/docker/docker-images.sh" -o "$tmp"
        bash "$tmp" <<< "" >/dev/null 2>&1 || true
        # invoke deploy via docker-images by sourcing it
        . "$tmp"
        deploy_image "$item" || log "Failed to deploy $item"
        rm -f "$tmp"
        ;;
    esac
  done
}

main(){
  ensure_docker
  while true; do
    interactive_server_search || break
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
      if ! whiptail --yesno "Select more server apps?" 8 50; then break; fi
    else
      read -rp "Select more? [y/N]: " more
      [[ "$more" =~ ^[Yy] ]] || break
    fi
  done
  log "Server apps module finished."
}
main "$@"
