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
# Use this one when Windows is just the GUI host and your dev environment lives
# in WSL.
$ErrorActionPreference = 'Stop'

function Log  { param([string]$msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn { param([string]$msg) Write-Host "!!  $msg" -ForegroundColor Yellow }
function Die  { param([string]$msg) Write-Host "xx  $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

# 1. Scoop
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Log "Installing Scoop"
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-Expression (Invoke-RestMethod -Uri 'https://get.scoop.sh')
}

# 2. Buckets — only the ones we actually need for the minimal set.
# `scoop bucket add` writes to stream 6 (Information) when the bucket already
# exists, which can't be silenced via redirection. We check the filesystem
# instead (same approach used by the full bootstrap).
Log "Configuring Scoop buckets"
$ScoopBucketDir = Join-Path $env:USERPROFILE 'scoop\buckets'
$buckets = @('extras', 'nerd-fonts')
foreach ($b in $buckets) {
    if (-not (Test-Path (Join-Path $ScoopBucketDir $b))) {
        Log "Adding scoop bucket: $b"
        scoop bucket add $b
    }
}

# git is a hard requirement for scoop bucket operations
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log "Installing git (scoop prerequisite)"
    scoop install git
}

Log "Updating Scoop"
scoop update

# 3. Install the wezterm-only package set.
# Font installs may fail with 'Access is denied' when the FontCache service
# holds a handle on a .ttf the installer wants to overwrite. Same repair logic
# as the full bootstrap, scoped to the two fonts we install here.
$ScoopFile = Join-Path $RepoRoot 'packages\scoopfile-wezterm-only.json'

function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Repair-ScoopNerdFont {
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$Bucket,
        [Parameter(Mandatory)][string[]]$FilePatterns
    )
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $regKey  = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $isAdmin = Test-IsAdmin

    Log "Repair: $App — limpando instalação órfã"

    if (-not $isAdmin) {
        Warn "Sessão não-elevada: Stop-Service FontCache será pulado. Se algum .ttf estiver locked pelo FontCache, o repair vai falhar. Para garantir: reabra PowerShell como administrador e rode .\install-wezterm-only.ps1 de novo."
    }

    scoop uninstall $App 2>$null | Out-Null

    $fontCacheRunning = $false
    if ($isAdmin) {
        try {
            $svc = Get-Service -Name FontCache -ErrorAction Stop
            if ($svc.Status -eq 'Running') {
                $fontCacheRunning = $true
                Stop-Service FontCache -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    }

    try {
        if (Test-Path $fontDir) {
            foreach ($pattern in $FilePatterns) {
                Get-ChildItem -Path $fontDir -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    } catch {
                        Warn "Arquivo font '$($_.Name)' ainda locked. Feche apps que usam a fonte (WezTerm, VS Code, terminais) e rode novamente."
                    }
                }
            }
        }
        if (Test-Path $regKey) {
            $props = (Get-Item $regKey).Property
            foreach ($pattern in $FilePatterns) {
                $regPattern = ($pattern -replace '\.(ttf|otf)$', ' (TrueType)')
                $props | Where-Object { $_ -like $regPattern } | ForEach-Object {
                    Remove-ItemProperty -Path $regKey -Name $_ -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } finally {
        if ($fontCacheRunning) {
            Start-Service FontCache -ErrorAction SilentlyContinue
        }
    }

    try {
        scoop install "$Bucket/$App"
        Log "Font '$App' reinstalada com sucesso."
    } catch {
        Warn "Reinstalação de '$App' ainda falhou: $($_.Exception.Message)"
    }
}

if (Test-Path $ScoopFile) {
    Log "Importing packages from scoopfile-wezterm-only.json"
    $importFailed = $false
    try {
        scoop import $ScoopFile
    } catch {
        $importFailed = $true
        Warn "scoop import reportou falha: $($_.Exception.Message)"
        Warn "Tentando remediar fontes nerd-fonts individualmente..."
    }

    if ($importFailed) {
        $fontPatternMap = @{
            'JetBrainsMono-NF' = @('JetBrainsMono*NerdFont*.ttf')
            'Maple-Mono-NF'    = @('MapleMono-NF-*.ttf')
        }
        $scoopJson = Get-Content $ScoopFile -Raw | ConvertFrom-Json
        foreach ($app in ($scoopJson.apps | Where-Object { $_.Source -eq 'nerd-fonts' })) {
            $patterns = $fontPatternMap[$app.Name]
            if (-not $patterns) {
                Warn "Sem padrão de arquivo conhecido para '$($app.Name)' — reparo pulado."
                continue
            }
            Repair-ScoopNerdFont -App $app.Name -Bucket $app.Source -FilePatterns $patterns
        }
    }
} else {
    Die "scoopfile-wezterm-only.json not found at $ScoopFile"
}

# 4. Apply dotfiles (wezterm-only profile).
# We pass --promptString profile=wezterm-only so the chezmoi prompt accepts the
# answer non-interactively. Other prompts (fullName, email, theme, useWsl,
# wslDistro, etc.) still appear interactively on first run — answer them and
# they persist in chezmoi.toml for subsequent applies.
Log "Applying dotfiles with chezmoi (profile=wezterm-only)"
$ChezmoiSource = Join-Path $RepoRoot 'dotfiles'

$chezmoiCfgCandidates = @(
    (Join-Path $env:USERPROFILE '.config\chezmoi\chezmoi.toml'),
    (Join-Path $env:APPDATA 'chezmoi\chezmoi.toml')
)
$chezmoiInitialized = $false
foreach ($p in $chezmoiCfgCandidates) {
    if (Test-Path $p) { $chezmoiInitialized = $true; break }
}

if (-not $chezmoiInitialized) {
    chezmoi init --source $ChezmoiSource --apply --promptString profile=wezterm-only
} else {
    # Already initialized: apply with the same source. If the user previously
    # ran the full bootstrap on this machine, .chezmoi.toml still has
    # profile="full" — they need to either edit it or run
    # `chezmoi init --source $ChezmoiSource --force --promptString profile=wezterm-only`
    # to re-prompt. We don't force here to avoid surprising users.
    Warn "chezmoi already initialized on this machine. To switch profiles, run: chezmoi edit-config (and change profile = `"wezterm-only`")"
    chezmoi apply --source $ChezmoiSource
}

Log "Wezterm-only bootstrap complete."
Log "Open WezTerm — it will spawn the shell you chose during chezmoi init (WSL or local Nushell)."
