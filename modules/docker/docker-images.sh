#!/usr/bin/env bash
set -euo pipefail
export TERM=${TERM:-linux}
# Generic Docker image deployer: choose from curated list or provide custom image
LOGFILE="/var/log/omvscript.log"
log(){ echo "$(date --iso-8601=seconds) $*" | tee -a "$LOGFILE"; }

ensure_docker(){
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found. Please run the Docker module first."
    exit 1
  fi
}

# Curated images (shortname|image|default_port|notes)
read -r -d '' CURATED <<'EOF' || true
nginx|nginx:stable|80|Simple web server (nginx)
httpd|httpd:latest|80|Apache HTTP server
postgres|postgres:15|5432|Postgres DB (set POSTGRES_PASSWORD env)
redis|redis:7|6379|Redis in-memory DB
portainer|portainer/portainer-ce:latest|9000|Docker management UI
traefik|traefik:v2.10|80|Reverse proxy (advanced)
gitea|gitea/gitea:latest|3000|Self-hosted Git service
metabase|metabase/metabase:latest|3000|BI dashboard
adminer|adminer:latest|8080|DB admin UI
vaultwarden|vaultwarden/server:latest|8080|Lightweight Bitwarden alternative
EOF

filter_choices(){
  local q="$1"
  # build an array of matching lines "key:display"
  IFS=$'\n' read -r -a lines <<< "$CURATED"
  matches=()
  for line in "${lines[@]}"; do
    if echo "$line" | grep -qi -- "$q"; then
      name=$(echo "$line" | cut -d'|' -f1)
      img=$(echo "$line" | cut -d'|' -f2)
      port=$(echo "$line" | cut -d'|' -f3)
      notes=$(echo "$line" | cut -d'|' -f4)
      matches+=("$name" "$name — $img — port:$port — $notes")
    fi
  done
  echo "${matches[@]:-}"
}

choose_with_whiptail(){
  if command -v whiptail >/dev/null 2>&1 && { [ -t 0 ] || [ -c /dev/tty ]; }; then
    whiptail "$@"
    return $?
  fi
  return 1
}

interactive_search_and_select(){
  # ask for search term
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    q=$(whiptail --inputbox "Search for Docker images (e.g. postgres, nginx, redis). Leave empty to list all." 10 60 "" 3>&1 1>&2 2>&3) || return 1
  else
    read -rp "Search for Docker images (leave empty for all): " q
  fi

  # get matches
  if [ -z "$q" ]; then q=""; fi
  mapfile -t choices_arr < <(filter_choices "$q")
  if [ ${#choices_arr[@]} -eq 0 ]; then
    # no matches: offer full list to pick custom
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
      whiptail --msgbox "No curated matches found for '$q'. You can provide a custom image name or try again." 10 60
    else
      echo "No curated matches for '$q'."
    fi
    return 2
  fi

  # transform into whiptail checklist args
  # whiptail checklist expects: tag label status
  checklist_args=()
  for ((i=0;i<${#choices_arr[@]};i+=2)); do
    tag="${choices_arr[i]}"
    label="${choices_arr[i+1]}"
    checklist_args+=("$tag" "$label" "OFF")
  done

  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    selected=$(whiptail --title "Select images to deploy" --checklist "Choose one or more images" 20 80 12 "${checklist_args[@]}" 3>&1 1>&2 2>&3) || return 1
  else
    # fallback: numbered terminal selection
    echo "Matches:"
    idx=1
    declare -A idx_to_tag
    for ((i=0;i<${#choices_arr[@]};i+=2)); do
      tag="${choices_arr[i]}"
      label="${choices_arr[i+1]}"
      echo "[$idx] $label"
      idx_to_tag[$idx]="$tag"
      ((idx++))
    done
    echo "Enter numbers separated by spaces (e.g. 1 3), or 'c' to cancel:"
    read -ra selnums
    if [ "${selnums[0]}" = "c" ]; then return 1; fi
    seltags=()
    for n in "${selnums[@]}"; do seltags+=("${idx_to_tag[$n]}"); done
    # format as whiptail output: "tag1" "tag2"
    selected=$(printf '"%s" ' "${seltags[@]}")
  fi

   # selected is like: "nginx" "postgres"
   # normalize into array
   eval "sel_arr=($selected)"
   # shellcheck disable=SC2154
   for t in "${sel_arr[@]}"; do deploy_image "$t"; done
}

deploy_image(){
  local short="$1"
  # find full info in CURATED
  IFS=$'\n' read -r -a lines <<< "$CURATED"
  local found=""
  for line in "${lines[@]}"; do
    name=$(echo "$line" | cut -d'|' -f1)
    if [ "$name" = "$short" ]; then
      found="$line"; break
    fi
  done

  if [ -z "$found" ]; then
    # treat as raw image name
    image="$short"
    prompt_custom_deploy "$image"
    return
  fi

  image=$(echo "$found" | cut -d'|' -f2)
  default_port=$(echo "$found" | cut -d'|' -f3)
  notes=$(echo "$found" | cut -d'|' -f4)

  # ask host port (default to default_port)
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    host_port=$(whiptail --inputbox "Choose host port to map for $short ($image). Default: $default_port. Leave empty to skip." 10 60 "$default_port" 3>&1 1>&2 2>&3) || return
  else
    read -rp "Host port to map for $short ($image) [default $default_port, empty=skip]: " host_port
    host_port=${host_port:-$default_port}
  fi

  if [ -z "$host_port" ]; then
    log "Skipping $short (no host port provided)"
    return
  fi

  # data directory
  data_dir="/opt/omvscript/data/$short"
  mkdir -p "$data_dir"
  # check container name uniqueness
  cname="omv_$short"
  if docker ps -a --format '{{.Names}}' | grep -q "^${cname}\$"; then
    log "Container $cname exists — skipping creation. Starting if stopped."
    docker start "$cname" >/dev/null 2>&1 || true
    return
  fi

  log "Pulling image $image..."
  docker pull "$image"

  # special-case images needing env var password
  env_args=()
  if [ "$short" = "postgres" ]; then
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
      pgpass=$(whiptail --passwordbox "Set POSTGRES_PASSWORD for postgres container (required):" 10 60 3>&1 1>&2 2>&3) || return
    else
      read -rsp "Set POSTGRES_PASSWORD (will not echo): " pgpass; echo
    fi
    if [ -z "$pgpass" ]; then
      log "No password provided — skipping postgres."
      return
    fi
    env_args+=("-e" "POSTGRES_PASSWORD=$pgpass")
  fi

  # run container
  log "Running $cname: docker run -d --name $cname -p ${host_port}:${default_port} -v ${data_dir}:/data --restart unless-stopped $image"
  docker run -d --name "$cname" -p "${host_port}:${default_port}" -v "${data_dir}:/data" --restart unless-stopped "${env_args[@]}" "$image"
  log "Deployed $image as container $cname (host port $host_port -> container port $default_port). Data dir: $data_dir"
}

prompt_custom_deploy(){
  image="$1"
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    host_port=$(whiptail --inputbox "Provide host:container port mapping for image $image (format host:container). Example: 8080:80" 10 60 "8080:80" 3>&1 1>&2 2>&3) || return
  else
    read -rp "Provide host:container port mapping for image $image (host:container): " host_port
  fi
  if [[ ! "$host_port" =~ ^[0-9]+:[0-9]+$ ]]; then
    log "Invalid port mapping. Skipping $image"
    return
  fi
  host=$(echo "$host_port" | cut -d: -f1)
  cont=$(echo "$host_port" | cut -d: -f2)
  short=$(echo "$image" | tr '/:' '_' | cut -c1-20)
  data_dir="/opt/omvscript/data/$short"
  mkdir -p "$data_dir"
  cname="omv_$short"
  if docker ps -a --format '{{.Names}}' | grep -q "^${cname}\$"; then
    log "Container $cname exists — skipping creation."
    docker start "$cname" >/dev/null 2>&1 || true
    return
  fi
  log "Pulling $image..."
  docker pull "$image"
  log "Running $cname"
  docker run -d --name "$cname" -p "${host}:${cont}" -v "${data_dir}:/data" --restart unless-stopped "$image"
  log "Deployed custom image $image as $cname"
}

main(){
  ensure_docker
  # keep offering until user cancels
  while true; do
    interactive_search_and_select || break
    if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
      if ! whiptail --yesno "Deploy more images?" 8 50; then break; fi
    else
      read -rp "Deploy more images? [y/N]: " more
      [[ "$more" =~ ^[Yy] ]] || break
    fi
  done
  log "Docker images module finished."
}
main "$@"
