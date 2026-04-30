#!/usr/bin/env bash
# Universal bootstrap for macOS, Ubuntu, and Debian.
# Delegates to bootstrap/macos.sh or bootstrap/linux.sh based on OS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!!\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31mxx\033[0m %s\n" "$*" >&2; exit 1; }

OS="$(uname -s)"
case "$OS" in
  Darwin)
    log "Detected macOS"
    bash "$SCRIPT_DIR/bootstrap/macos.sh"
    ;;
  Linux)
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      case "$ID" in
        ubuntu|debian)
          log "Detected $PRETTY_NAME"
          bash "$SCRIPT_DIR/bootstrap/linux.sh"
          ;;
        *)
          if [ "${ID_LIKE:-}" = "debian" ] || [[ "${ID_LIKE:-}" == *debian* ]]; then
            log "Detected Debian-like distro ($PRETTY_NAME) — using linux bootstrap"
            bash "$SCRIPT_DIR/bootstrap/linux.sh"
          else
            die "Unsupported Linux distribution: $ID. This setup targets Ubuntu and Debian."
          fi
          ;;
      esac
    else
      die "Cannot detect Linux distribution (no /etc/os-release)."
    fi
    ;;
  *)
    die "Unsupported OS: $OS. Run install.ps1 on Windows."
    ;;
esac

log "Bootstrap finished. Open a new WezTerm window and you should be in Nushell with the full setup."
