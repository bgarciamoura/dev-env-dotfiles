#!/usr/bin/env bash
# Ubuntu / Debian bootstrap.
# Strategy: install a minimal system toolchain via apt, then use Homebrew on Linux
# for everything else (Homebrew gives us the same latest versions as macOS, using
# the same Brewfile). Rust tools go through cargo as a fallback.
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

# 1. apt: system-level build tools needed for brew and cargo builds
log "Installing apt prerequisites (sudo required)"
sudo apt-get update -y
sudo apt-get install -y \
  build-essential procps curl file git ca-certificates \
  libssl-dev pkg-config unzip fontconfig

# 2. Homebrew on Linux
if ! command -v brew >/dev/null 2>&1 && ! [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  log "Installing Homebrew on Linux"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Add brew to this session's PATH
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Persist brew on PATH for future bash/zsh sessions (Nushell handles it via env.nu)
BREW_SHELLENV_LINE='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
for profile in "$HOME/.profile" "$HOME/.bashrc"; do
  if [ -f "$profile" ] && ! grep -Fq "$BREW_SHELLENV_LINE" "$profile"; then
    echo "$BREW_SHELLENV_LINE" >> "$profile"
  fi
done

log "Updating Homebrew"
brew update

# 3. Brewfile — same file as macOS uses
log "Installing packages from Brewfile"
brew bundle --file="$REPO_ROOT/packages/Brewfile"

require_nvim_version "$NVIM_MIN_VERSION"

# 4. Cargo (if not installed by brew already, install via rustup for newest stable)
if ! command -v cargo >/dev/null 2>&1; then
  log "Installing rustup (for cargo)"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
  # shellcheck disable=SC1091
  . "$HOME/.cargo/env"
fi

if [ -f "$REPO_ROOT/packages/cargo-tools.txt" ]; then
  log "Installing cargo tools"
  while IFS= read -r crate || [ -n "$crate" ]; do
    [ -z "$crate" ] && continue
    [[ "$crate" =~ ^# ]] && continue
    cargo install --locked "$crate" || warn "cargo install $crate failed (non-fatal)"
  done < "$REPO_ROOT/packages/cargo-tools.txt"
fi

# 5. WezTerm (not available on Linuxbrew — use official repo)
if ! command -v wezterm >/dev/null 2>&1; then
  log "Installing WezTerm from official APT repo"
  curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
  echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | \
    sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y wezterm
fi

# 6. Nerd Fonts (brew's homebrew/cask-fonts does not work on Linux)
log "Installing Nerd Fonts (JetBrainsMono + Maple Mono NF) to ~/.local/share/fonts"
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

install_nerdfont() {
  local name="$1" url="$2" tmp
  if fc-list | grep -qi "$name"; then
    log "Font '$name' already installed, skipping."
    return
  fi
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/font.zip"
  unzip -oq "$tmp/font.zip" -d "$tmp/font"
  find "$tmp/font" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec cp {} "$FONT_DIR/" \;
  rm -rf "$tmp"
}

# JetBrains Mono Nerd Font (from the official nerd-fonts release)
install_nerdfont "JetBrainsMono Nerd Font" \
  "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"

# Maple Mono NF — upstream zip from the Maple-Font releases
install_nerdfont "Maple Mono NF" \
  "https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF.zip" || \
  warn "Maple Mono NF install failed (non-fatal). Install manually if desired."

fc-cache -fv >/dev/null

# 7. Apply dotfiles
log "Applying dotfiles with chezmoi"
# --no-tty força stdin line-buffered nos prompts. Sem isso, chezmoi v2.70+ usa
# huh (Charm) em raw mode e cada keystroke vira "confirma com default" — em
# WSL2 + Windows Terminal o problema é especialmente reproduzível.
if [ ! -d "$HOME/.local/share/chezmoi" ]; then
  chezmoi init --source "$REPO_ROOT/dotfiles" --apply --no-tty
else
  chezmoi apply --source "$REPO_ROOT/dotfiles" --no-tty
fi

# 8. Install language runtimes from ~/.config/mise/config.toml
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

  # Persist mise activation for future bash sessions. Sem isso, `node`/`python`
  # gerenciados pelo mise não aparecem no PATH em shells novos — só em Nushell,
  # que ativa via vendor/autoload/mise.nu. Mesmo padrão idempotente do brew.
  MISE_ACTIVATE_LINE='eval "$(mise activate bash)"'
  if [ -f "$HOME/.bashrc" ] && ! grep -Fq "$MISE_ACTIVATE_LINE" "$HOME/.bashrc"; then
    echo "$MISE_ACTIVATE_LINE" >> "$HOME/.bashrc"
  fi
fi

# 9. Run Neovim install-deps.sh now that mise's Python is available.
# Running this AFTER `mise install` ensures `pip --user` uses mise's Python,
# avoiding PEP 668 errors on Homebrew's externally-managed Python.
NVIM_DEPS="$HOME/.config/nvim/scripts/install-deps.sh"
if [ -f "$NVIM_DEPS" ]; then
  log "Running Neovim install-deps.sh with mise environment"
  if command -v mise >/dev/null 2>&1; then
    mise exec -- bash "$NVIM_DEPS" || warn "install-deps.sh exited non-zero — inspect output above."
  else
    bash "$NVIM_DEPS" || warn "install-deps.sh exited non-zero — inspect output above."
  fi
fi

# 10. Register Nushell as a login shell (optional)
NU_PATH="$(command -v nu || true)"
if [ -n "$NU_PATH" ] && ! grep -Fxq "$NU_PATH" /etc/shells; then
  log "Registering Nushell in /etc/shells (sudo required)"
  echo "$NU_PATH" | sudo tee -a /etc/shells >/dev/null
  warn "Run 'chsh -s $NU_PATH' manually if you want Nushell as login shell."
fi

log "Linux bootstrap complete."
