# Shared functions for the Windows bootstraps (windows.ps1, windows-wezterm-only.ps1).
#
# This file is dot-sourced by both entry-point bootstraps, so all functions and
# script-level variables defined here become available in the caller's scope.
# Keep behavior identical to what the original duplicated blocks did — when a
# divergence exists between the two profiles, expose it as a parameter rather
# than branching internally.
#
# Assumes PowerShell 7+ (install.ps1 / install-wezterm-only.ps1 enforce that
# before invoking us). Do not add PS 5.1 compatibility shims here.
#
# The caller is expected to set $ErrorActionPreference = 'Stop' so failures in
# these helpers propagate. Strings with non-ASCII content are intentional and
# safe under PS 7's UTF-8 default parser encoding.

# --- Logging helpers ------------------------------------------------------
function Log  { param([string]$msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn { param([string]$msg) Write-Host "!!  $msg" -ForegroundColor Yellow }
function Die  { param([string]$msg) Write-Host "xx  $msg" -ForegroundColor Red; exit 1 }

# --- Privilege detection --------------------------------------------------
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Scoop installation + bucket setup -----------------------------------
function Install-ScoopIfMissing {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Log "Installing Scoop"
        # TLS 1.2 needed for legacy Windows builds.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-Expression (Invoke-RestMethod -Uri 'https://get.scoop.sh')
    }
}

function Add-ScoopBucketsIfMissing {
    # `scoop bucket add` writes to stream 6 (Information) when the bucket
    # already exists, which can't be silenced via redirection. We check the
    # filesystem instead.
    param([Parameter(Mandatory)][string[]]$Buckets)
    Log "Configuring Scoop buckets"
    $bucketDir = Join-Path $env:USERPROFILE 'scoop\buckets'
    foreach ($b in $Buckets) {
        if (-not (Test-Path (Join-Path $bucketDir $b))) {
            Log "Adding scoop bucket: $b"
            scoop bucket add $b
        }
    }
}

function Install-GitForScoop {
    # git is a hard requirement for scoop bucket operations.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Log "Installing git (scoop prerequisite)"
        scoop install git
    }
}

# --- Nerd Font repair ----------------------------------------------------
# Scoop's nerd-fonts installs fail with 'Access is denied' when the FontCache
# service has a handle on a .ttf the installer wants to overwrite. The fix is
# to stop FontCache, remove the orphan .ttf and its HKCU\...\Fonts entries,
# restart FontCache, and reinstall.
function Repair-ScoopNerdFont {
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$Bucket,
        [Parameter(Mandatory)][string[]]$FilePatterns,
        # Bootstrap entry script name (so the elevation hint matches the
        # script the user actually invoked).
        [string]$EntryScript = 'install.ps1'
    )
    $fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $regKey  = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    $isAdmin = Test-IsAdmin

    Log "Repair: $App — limpando instalação órfã"

    if (-not $isAdmin) {
        Warn "Sessão não-elevada: Stop-Service FontCache será pulado. Se algum .ttf estiver locked pelo FontCache, o repair vai falhar. Para garantir: reabra PowerShell como administrador e rode .\$EntryScript de novo."
    }

    # scoop uninstall is best-effort: silent failure if app isn't installed
    # or the uninstaller hit the same lock. Either way we proceed.
    scoop uninstall $App 2>$null | Out-Null

    # Stopping FontCache releases the handles it holds on .ttf files. Admin only.
    $fontCacheRunning = $false
    if ($isAdmin) {
        try {
            $svc = Get-Service -Name FontCache -ErrorAction Stop
            if ($svc.Status -eq 'Running') {
                $fontCacheRunning = $true
                Stop-Service FontCache -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Service may not exist on minimal Windows editions — ignore.
        }
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
                # Installer writes as '<basename> (TrueType)' — convert file
                # pattern to registry-value pattern.
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
        Warn "Workarounds: (a) reabra o PowerShell como administrador e rode o bootstrap de novo, (b) feche TODOS os terminais/editores que usam a fonte e tente, ou (c) instale global com 'sudo scoop install -g $Bucket/$App'."
    }
}

# --- Scoop import + nerd-font repair fallback ---------------------------
function Invoke-ScoopImportWithFontRepair {
    # Imports the given scoopfile.json. If `scoop import` errors (typically a
    # FontCache lock on a nerd-font .ttf), iterates over each nerd-fonts entry
    # and runs Repair-ScoopNerdFont individually.
    param(
        [Parameter(Mandatory)][string]$ScoopFile,
        [string]$EntryScript = 'install.ps1'
    )

    # Confirmados em 04/2026 nos manifests do matthewjberger/scoop-nerd-fonts.
    # JetBrainsMono-NF usa filter '*NerdFont-*' — família inclui variantes NL
    # (No Ligatures), Mono e Propo; padrão DEVE ter wildcard entre
    # 'JetBrainsMono' e 'NerdFont' para pegar 'JetBrainsMonoNLNerdFont*'.
    $fontPatternMap = @{
        'JetBrainsMono-NF' = @('JetBrainsMono*NerdFont*.ttf')
        'Maple-Mono-NF'    = @('MapleMono-NF-*.ttf')
    }

    Log "Importing packages from $(Split-Path -Leaf $ScoopFile)"
    $importFailed = $false
    try {
        scoop import $ScoopFile
    } catch {
        $importFailed = $true
        Warn "scoop import reportou falha: $($_.Exception.Message)"
        Warn "Tentando remediar fontes nerd-fonts individualmente..."
    }

    if ($importFailed) {
        $scoopJson = Get-Content $ScoopFile -Raw | ConvertFrom-Json
        foreach ($app in ($scoopJson.apps | Where-Object { $_.Source -eq 'nerd-fonts' })) {
            $patterns = $fontPatternMap[$app.Name]
            if (-not $patterns) {
                Warn "Sem padrão de arquivo conhecido para '$($app.Name)' — reparo pulado."
                continue
            }
            Repair-ScoopNerdFont -App $app.Name -Bucket $app.Source -FilePatterns $patterns -EntryScript $EntryScript
        }
    }
}

# --- chezmoi initialization detection -----------------------------------
function Test-ChezmoiInitialized {
    # chezmoi writes its config.toml to $XDG_CONFIG_HOME\chezmoi\ when XDG is
    # set; otherwise it falls back to %APPDATA%\chezmoi\. On a fresh Windows
    # machine XDG_CONFIG_HOME hasn't been persisted yet, so the actual path
    # could be either. Returning $true as soon as we find one prevents
    # promptStringOnce from re-running on subsequent applies.
    $candidates = @(
        (Join-Path $env:USERPROFILE '.config\chezmoi\chezmoi.toml'),
        (Join-Path $env:APPDATA 'chezmoi\chezmoi.toml')
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $true }
    }
    return $false
}
