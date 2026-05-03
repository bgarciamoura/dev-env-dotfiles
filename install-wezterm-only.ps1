# install-wezterm-only.ps1 - Lightweight Windows entry point.
#
# Use this when Windows is just the GUI host for WezTerm and your real dev
# environment lives in WSL (or you simply don't want the full dotfile stack
# materialized on Windows). It installs only WezTerm + Nerd Fonts + chezmoi,
# then applies dotfiles with profile=wezterm-only so the .chezmoiignore prunes
# everything except dot_config/wezterm/.
#
# This file is deliberately ASCII-only so Windows PowerShell 5.1 can parse it
# without a UTF-8 BOM. Localized / accented content lives in
# bootstrap\windows-wezterm-only.ps1, which runs under PS 7+ where UTF-8 is the
# default parser encoding.
#
# Flow mirrors install.ps1:
#   1. If running on PowerShell 7+: invoke bootstrap\windows-wezterm-only.ps1 directly.
#   2. If running on PS 5.1:
#        - locate pwsh; install it via winget if missing;
#        - relaunch THIS file under pwsh so everything downstream parses UTF-8.

$ErrorActionPreference = 'Stop'

function Log  { param([string]$msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn { param([string]$msg) Write-Host "!!  $msg" -ForegroundColor Yellow }
function Die  { param([string]$msg) Write-Host "xx  $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not ($PSVersionTable.Platform -eq $null -or $PSVersionTable.Platform -eq 'Win32NT')) {
    Die "install-wezterm-only.ps1 is Windows-only. Use install.sh on macOS/Linux."
}

# --- PowerShell 7 enforcement ---------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Log "PowerShell $($PSVersionTable.PSVersion) detected; this bootstrap requires 7+."

    function Find-Pwsh {
        $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
        $candidates = @(
            (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'PowerShell\7\pwsh.exe'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell\7\pwsh.exe')
        )
        foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
        return $null
    }

    $pwshPath = Find-Pwsh

    if (-not $pwshPath) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Die "Neither pwsh nor winget found. Install PowerShell 7 manually: https://aka.ms/powershell-release"
        }

        Log "Installing PowerShell 7 via winget (one-time, ~100 MB). UAC prompt may appear."
        winget install --id Microsoft.PowerShell --source winget --silent `
            --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Die "winget install Microsoft.PowerShell failed (exit=$LASTEXITCODE). Install manually: https://aka.ms/powershell-release"
        }

        $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' +
                    [Environment]::GetEnvironmentVariable('PATH', 'Machine')

        $pwshPath = Find-Pwsh
        if (-not $pwshPath) {
            Die "pwsh installed but not locatable. Open a new terminal and rerun .\install-wezterm-only.ps1."
        }
    }

    Log "Relaunching under pwsh: $pwshPath"
    & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit $LASTEXITCODE
}

# --- Main (runs under PowerShell 7+) --------------------------------------
Log "Detected Windows $([System.Environment]::OSVersion.Version)"
& "$ScriptDir\bootstrap\windows-wezterm-only.ps1"

Log "Bootstrap finished. Open a new WezTerm window."
