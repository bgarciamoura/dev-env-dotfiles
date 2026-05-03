# Windows bootstrap — wezterm-only profile.
#
# Installs the bare minimum to run WezTerm as a Windows GUI host that hands off
# the actual shell to WSL (or to a local Nushell, depending on chezmoi prompts):
#   - Scoop (package manager)
#   - git, chezmoi, wezterm
#   - Two Nerd Fonts (JetBrainsMono-NF, Maple-Mono-NF) — both used by font.lua.tmpl
#
# Everything else (Nushell, Starship, Zellij, mise, Atuin, runtimes, Neovim
# clone, XDG env vars, vendor file regeneration) is intentionally skipped —
# .chezmoiignore + the wezterm-only profile prune them out at apply time.
#
# Counterpart: bootstrap/windows.ps1 (full profile) installs the entire stack.
# Shared helpers (logging, scoop setup, nerd-font repair, chezmoi init detection)
# live in bootstrap/_windows-common.ps1 and are dot-sourced below.
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

. (Join-Path $ScriptDir '_windows-common.ps1')

# 1. Scoop + buckets + git
Install-ScoopIfMissing
# Only the buckets needed for the minimal set; the full profile adds 'versions'.
Add-ScoopBucketsIfMissing -Buckets @('extras', 'nerd-fonts')
Install-GitForScoop

Log "Updating Scoop"
scoop update

# 2. Install the wezterm-only package set.
$ScoopFile = Join-Path $RepoRoot 'packages\scoopfile-wezterm-only.json'
if (Test-Path $ScoopFile) {
    Invoke-ScoopImportWithFontRepair -ScoopFile $ScoopFile -EntryScript 'install-wezterm-only.ps1'
} else {
    Die "scoopfile-wezterm-only.json not found at $ScoopFile"
}

# 3. Apply dotfiles (wezterm-only profile).
# Os flags --promptString/--promptChoice do chezmoi são silenciosamente
# IGNORADOS pelas variantes *Once (twpayne/chezmoi#2945, #3345 — confirmado em
# v2.70.2). Workaround: pré-popular [data] em chezmoi.toml antes do init.
# promptChoiceOnce reusa valores já presentes em .chezmoi.config.data e pula o
# prompt; outros prompts (fullName, email, theme, useWsl, wslDistro, etc.) ainda
# aparecem interativamente.
#
# --no-tty força stdin line-buffered nos prompts. Sem isso, chezmoi v2.70+ usa
# huh (Charm) em raw mode e cada keystroke vira "confirma com default".
Log "Applying dotfiles with chezmoi (profile=wezterm-only)"
$ChezmoiSource = Join-Path $RepoRoot 'dotfiles'

if (-not (Test-ChezmoiInitialized)) {
    # Sem XDG_CONFIG_HOME setado (vem só no profile=full), chezmoi default no
    # Windows é %APPDATA%\chezmoi\. Escrevemos lá pra pre-seedar profile.
    $cmCfgDir = Join-Path $env:APPDATA 'chezmoi'
    $cmCfg    = Join-Path $cmCfgDir 'chezmoi.toml'
    New-Item -ItemType Directory -Path $cmCfgDir -Force | Out-Null
    @'
[data]
    profile = "wezterm-only"
'@ | Set-Content -Path $cmCfg -Encoding UTF8
    chezmoi init --source $ChezmoiSource --apply --no-tty
} else {
    # Already initialized: apply with the same source. If the user previously
    # ran the full bootstrap on this machine, .chezmoi.toml still has
    # profile="full" — they need to either edit it or run
    # `chezmoi init --source $ChezmoiSource --force` after editing [data] to
    # re-prompt. We don't force here to avoid surprising users.
    Warn "chezmoi already initialized on this machine. To switch profiles, run: chezmoi edit-config (and change profile = `"wezterm-only`")"
    chezmoi apply --source $ChezmoiSource --no-tty
}

Log "Wezterm-only bootstrap complete."
Log "Open WezTerm — it will spawn the shell you chose during chezmoi init (WSL or local Nushell)."
