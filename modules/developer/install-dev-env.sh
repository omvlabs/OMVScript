#!/usr/bin/env bash
set -euo pipefail
log(){ echo "$(date --iso-8601=seconds) $*"; }

PKG=""
if command -v apt-get >/dev/null 2>&1; then PKG="apt"; fi
if command -v dnf >/dev/null 2>&1; then PKG="dnf"; fi
if command -v pacman >/dev/null 2>&1; then PKG="pacman"; fi

install_pkg() {
  case "$PKG" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    pacman)
      pacman -Syu --noconfirm "$@"
      ;;
    *)
      log "Unknown package manager: $PKG"
      return 1
      ;;
  esac
}

# VS Code
if command -v code >/dev/null 2>&1; then
  log "VS Code already installed."
else
  log "Installing VS Code (where supported)..."
  case "$PKG" in
    apt)
      wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg || true
      echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list
      apt-get update -y
      apt-get install -y code || log "Failed to install VS Code via apt."
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
      dnf install -y code || log "Failed to install VS Code via dnf."
      ;;
    pacman)
      log "On Arch, please install VS Code from official repo or AUR (code/code-insiders)."
      ;;
  esac
fi

# Python
install_pkg python3 python3-venv python3-pip || true

# nvm + Node (user level)
if [ -n "${SUDO_USER:-}" ]; then
  RUN_USER="$SUDO_USER"
else
  RUN_USER="$(whoami)"
fi

if su - "$RUN_USER" -c 'command -v nvm >/dev/null 2>&1' ; then
  log "nvm already installed for $RUN_USER."
else
  log "Installing nvm for $RUN_USER..."
  su - "$RUN_USER" -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash' || \
    log "nvm install script failed."
  # shellcheck disable=SC2016
  su - "$RUN_USER" -c 'export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" && nvm install --lts' || true
fi

# Java
if command -v java >/dev/null 2>&1; then
  log "Java already present: $(java -version 2>&1 | head -n 1)"
else
  log "Installing OpenJDK..."
  install_pkg openjdk-11-jdk || install_pkg java-11-openjdk-devel || true
fi

log "Developer environment setup complete."
exit 0
