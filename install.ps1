# install.ps1 - Universal bootstrap entry point for Windows.
#
# This file is deliberately ASCII-only so Windows PowerShell 5.1 (the default
# shell on Windows 11) can parse it without a UTF-8 BOM. Non-ASCII content
# would be decoded in the system ANSI codepage and break the parser
# (unterminated-string errors on em-dashes, accents, etc.). All localized /
# accented content lives in bootstrap\windows.ps1, which runs under
# PowerShell 7+ where UTF-8 is the default parser encoding.
#
# Flow:
#   1. If running on PowerShell 7+: invoke bootstrap\windows.ps1 directly.
#   2. If running on PS 5.1:
#        - locate pwsh; install it via winget if missing;
#        - relaunch THIS file under pwsh so everything downstream parses UTF-8.

$ErrorActionPreference = 'Stop'

function Log  { param([string]$msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn { param([string]$msg) Write-Host "!!  $msg" -ForegroundColor Yellow }
function Die  { param([string]$msg) Write-Host "xx  $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not ($PSVersionTable.Platform -eq $null -or $PSVersionTable.Platform -eq 'Win32NT')) {
    Die "install.ps1 is Windows-only. Use install.sh on macOS/Linux."
}

# --- PowerShell 7 enforcement ---------------------------------------------
# Downstream scripts (bootstrap\windows.ps1 and Chezmoi templates) use
# Portuguese messages and other non-ASCII content. PS 5.1 mangles those
# unless the files have a BOM; we prefer to require PS 7 once rather than
# scatter BOMs everywhere.
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

        # winget updated the persistent PATH but not the current process. Refresh.
        $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' +
                    [Environment]::GetEnvironmentVariable('PATH', 'Machine')

        $pwshPath = Find-Pwsh
        if (-not $pwshPath) {
            Die "pwsh installed but not locatable. Open a new terminal and rerun .\install.ps1."
        }
    }

    Log "Relaunching under pwsh: $pwshPath"
    & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path
    exit $LASTEXITCODE
}

# --- Main (runs under PowerShell 7+) --------------------------------------
Log "Detected Windows $([System.Environment]::OSVersion.Version)"
& "$ScriptDir\bootstrap\windows.ps1"

Log "Bootstrap finished. Open a new WezTerm window - you should land in Nushell with the full setup."
