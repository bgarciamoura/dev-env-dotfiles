#!/usr/bin/env bash
# macOS bootstrap: Homebrew + Brewfile + fonts + chezmoi apply.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$REPO_ROOT/packages/versions.env"

log()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m!!\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31mxx\033[0m %s\n" "$*" >&2; exit 1; }

require_nvim_version() {
  local min="$1" raw clean lowest
  if ! command -v nvim >/dev/null 2>&1; then
    die "Neovim não encontrado no PATH após a instalação."
  fi
  raw="$(nvim --version | head -n1 | awk '{print $2}')"
  clean="${raw#v}"
  clean="${clean%%-*}"
  lowest="$(printf '%s\n%s\n' "$clean" "$min" | sort -V | head -n1)"
  if [ "$lowest" != "$min" ]; then
    die "Neovim $raw instalado, mas versão mínima exigida é $min. Rode 'brew upgrade neovim'."
  fi
  log "Neovim $raw detectado (>=$min)."
}

# 1. Command Line Tools for Xcode (required by Homebrew)
if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (prompt will appear)"
  xcode-select --install || true
  warn "Wait for the CLT install to finish, then re-run this script."
  exit 0
fi

# 2. Homebrew
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Add brew to PATH for this session (Apple Silicon vs Intel)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

log "Updating Homebrew"
brew update

# 3. Install everything in Brewfile (+ Mac-only casks)
log "Installing packages from Brewfile"
brew bundle --file="$REPO_ROOT/packages/Brewfile"
log "Installing Mac-only casks (WezTerm, fonts)"
brew bundle --file="$REPO_ROOT/packages/Brewfile.mac"

require_nvim_version "$NVIM_MIN_VERSION"

# 4. Cargo tools (anything not in brew, or newer than brew's)
if command -v cargo >/dev/null 2>&1 && [ -f "$REPO_ROOT/packages/cargo-tools.txt" ]; then
  log "Installing cargo tools"
  while IFS= read -r crate || [ -n "$crate" ]; do
    [ -z "$crate" ] && continue
    [[ "$crate" =~ ^# ]] && continue
    cargo install --locked "$crate" || warn "cargo install $crate failed (non-fatal)"
  done < "$REPO_ROOT/packages/cargo-tools.txt"
fi

# 5. Apply dotfiles
log "Applying dotfiles with chezmoi"
if [ ! -d "$HOME/.local/share/chezmoi" ]; then
  chezmoi init --source "$REPO_ROOT/dotfiles" --apply
else
  chezmoi apply --source "$REPO_ROOT/dotfiles"
fi

# 6. Install language runtimes from ~/.config/mise/config.toml
#
# `mise install` retorna exit 0 mesmo quando um runtime individual falha
# silenciosamente (a verificação GPG requer gpg no PATH — cobrimos isso no
# Brewfile, mas dependências de rede ou mudanças upstream ainda podem quebrar
# tools pontuais). `mise ls` depois imprime o estado real para diagnóstico.
if command -v mise >/dev/null 2>&1; then
  log "Installing language runtimes via mise"
  mise install || warn "mise install teve falhas (non-fatal). Veja 'mise ls' abaixo."
  log "Estado atual dos runtimes gerenciados por mise:"
  mise ls || true
fi

# 7. Register Nushell as a login shell (optional)
NU_PATH="$(command -v nu || true)"
if [ -n "$NU_PATH" ] && ! grep -Fxq "$NU_PATH" /etc/shells; then
  log "Registering Nushell in /etc/shells (sudo required)"
  echo "$NU_PATH" | sudo tee -a /etc/shells >/dev/null
  warn "Run 'chsh -s $NU_PATH' manually if you want Nushell as login shell."
fi

log "macOS bootstrap complete."
