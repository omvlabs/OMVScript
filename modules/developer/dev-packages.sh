#!/usr/bin/env bash
set -euo pipefail
export TERM=${TERM:-linux}
LOGFILE="/var/log/omvscript.log"
# REPO_RAW_BASE="https://raw.githubusercontent.com/Omcodes23/OmVScript/main"
log(){ echo "$(date --iso-8601=seconds) $*" | tee -a "$LOGFILE"; }

detect_pkg_manager(){
  if command -v apt-get >/dev/null 2>&1; then echo "apt"
  elif command -v dnf >/dev/null 2>&1; then echo "dnf"
  elif command -v pacman >/dev/null 2>&1; then echo "pacman"
  else echo "unknown"; fi
}

PKG=$(detect_pkg_manager)

install_pkg(){
  case "$PKG" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@";;
    dnf) dnf install -y "$@";;
    pacman) pacman -Syu --noconfirm "$@";;
    *) echo "Unsupported package manager: $PKG"; return 1;;
  esac
}

# curated dev packages: key|description|install_hint
read -r -d '' DEV_PACKS <<'EOF' || true
vscode|Visual Studio Code — popular code editor|package
python|Python 3 + venv — language runtime|package
node|Node (via nvm recommended)|nvm
nvm|NVM — Node version manager (user-level)|script
openjdk|OpenJDK 11 — Java runtime & dev kit|package
docker|Docker — container runtime (ensure via Docker module)|module
git|Git — version control|package
pyenv|pyenv — python version manager (user-level)|script
golang|Go — golang toolchain|package
EOF

filter_dev(){
  local q="$1"
  IFS=$'\n' read -r -a lines <<< "$DEV_PACKS"
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

choose_with_whiptail(){ command -v whiptail >/dev/null 2>&1 && [ -t 0 ] && whiptail "$@" && return $? || return 1; }

interactive_dev_search(){
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    q=$(whiptail --inputbox "Search dev packages (vscode, python, node). Leave empty to list all." 10 60 "" 3>&1 1>&2 2>&3) || return 1
  else
    read -rp "Search dev packages (empty=all): " q
  fi

  mapfile -t arr < <(filter_dev "$q")
  if [ ${#arr[@]} -eq 0 ]; then
    [ -n "$q" ] && log "No matches for $q"
    return 2
  fi

  checklist=()
  for ((i=0;i<${#arr[@]};i+=2)); do
    checklist+=("${arr[i]}" "${arr[i+1]}" "OFF")
  done

  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
    sel=$(whiptail --title "Select dev packages" --checklist "Choose one or more dev packages to install" 20 80 12 "${checklist[@]}" 3>&1 1>&2 2>&3) || return 1
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
      vscode)
        if command -v code >/dev/null 2>&1; then log "VSCode already installed"; else
          case "$PKG" in
            apt)
              wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg || true
              echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
              apt-get update -y
              apt-get install -y code || log "Failed to install code"
              ;;
            dnf)
              rpm --import https://packages.microsoft.com/keys/microsoft.asc || true
              cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[vscode]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
              dnf check-update || true
              dnf install -y code || log "Failed to install code"
              ;;
            pacman)
              log "Install code from repo/AUR on Arch"
              ;;
          esac
        fi
        ;;
      python)
        install_pkg python3 python3-venv python3-pip || true
        ;;
      node)
        if su - "${SUDO_USER:-$USER}" -c 'command -v nvm >/dev/null 2>&1'; then
          log "nvm present"
        else
          log "Installing nvm for user ${SUDO_USER:-$USER}"
          su - "${SUDO_USER:-$USER}" -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash' || log "nvm install failed"
        fi
        ;;
      nvm)
        log "Handled by node selection; nvm is installed for user."
        ;;
      openjdk)
        install_pkg openjdk-11-jdk || install_pkg java-11-openjdk-devel || true
        ;;
      git)
        install_pkg git || true
        ;;
      pyenv)
        if [ -n "${SUDO_USER:-}" ]; then
          run_user="$SUDO_USER"
        else
          run_user="$(whoami)"
        fi
        su - "$run_user" -c 'curl https://pyenv.run | bash' || log "pyenv install may have failed"
        ;;
      golang)
        install_pkg golang || true
        ;;
      *)
        log "Unknown dev package: $item"
        ;;
    esac
  done
}

# helper to install packages for apt/dnf/pacman
install_pkg(){
  case "$PKG" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get update -y && apt-get install -y --no-install-recommends "$@";;
    dnf) dnf install -y "$@";;
    pacman) pacman -Syu --noconfirm "$@";;
    *) log "Cannot install packages: unknown pkg manager"; return 1;;
  esac
}

main(){
  while true; do
    interactive_dev_search || break
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ]; then
      whiptail --yesno "Install more dev packages?" 8 50 || break
    else
      read -rp "Install more? [y/N]: " more; [[ "$more" =~ ^[Yy] ]] || break
    fi
  done
  log "Developer packages module finished."
}
main "$@"
