# Windows 11 bootstrap: Scoop + buckets + scoopfile.json + cargo + chezmoi apply.
# Strategy: Scoop gives us bleeding-edge versions of dev tools straight from GitHub.
# We add the 'main', 'extras', 'nerd-fonts', and 'versions' buckets and run `scoop import`.
#
# Shared Windows helpers (logging, scoop setup, nerd-font repair, chezmoi init
# detection) live in bootstrap/_windows-common.ps1 and are dot-sourced below.
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

. (Join-Path $ScriptDir '_windows-common.ps1')

# Lê packages/versions.env (formato KEY=VALUE) para um hashtable. Mantemos um
# parser local em vez de exigir um módulo porque queremos zero dependências no
# primeiro boot (e a wezterm-only profile não precisa disso).
function Read-VersionsEnv {
    param([Parameter(Mandatory)][string]$Path)
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($line in (Get-Content $Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $map
}

$Versions = Read-VersionsEnv (Join-Path $RepoRoot 'packages\versions.env')
if (-not $Versions.ContainsKey('NVIM_MIN_VERSION')) { Die "versions.env não define NVIM_MIN_VERSION" }
if (-not $Versions.ContainsKey('NU_MIN_VERSION'))   { Die "versions.env não define NU_MIN_VERSION" }
$NvimMinVersion = [version]$Versions['NVIM_MIN_VERSION']
$NuMinVersion   = [version]$Versions['NU_MIN_VERSION']

# 1. Scoop + buckets + git
Install-ScoopIfMissing
Add-ScoopBucketsIfMissing -Buckets @('extras', 'nerd-fonts', 'versions')
Install-GitForScoop

Log "Updating Scoop and all installed packages"
scoop update

# 2. Install packages from scoopfile.json
$ScoopFile = Join-Path $RepoRoot 'packages\scoopfile.json'
if (Test-Path $ScoopFile) {
    Invoke-ScoopImportWithFontRepair -ScoopFile $ScoopFile -EntryScript 'install.ps1'
} else {
    Warn "scoopfile.json not found at $ScoopFile — skipping bulk install"
}

# 3. Rust toolchain + cargo tools
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Log "Installing rustup"
    scoop install rustup
    # Refresh PATH from registry so rustup shim (just added by Scoop) is callable
    # in the current session. Without this, 'rustup default stable' may fail.
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'User') + ';' +
                [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        rustup default stable
    } else {
        Warn "rustup instalado mas não está no PATH desta sessão. Reabra o terminal e rode 'rustup default stable'."
    }
}

$CargoFile = Join-Path $RepoRoot 'packages\cargo-tools.txt'
if (Test-Path $CargoFile) {
    # Materializar lista de crates ativos antes de logar/avisar. Se só tem
    # comentário (estado atual), pular o bloco inteiro em silêncio — evita
    # 'link.exe não encontrado' como falso alarme quando não há compilação.
    $crates = @(
        Get-Content $CargoFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') }
    )
    if ($crates.Count -gt 0) {
        Log "Installing cargo tools"

        # cargo install compila código nativo; no toolchain MSVC (padrão do rustup
        # no Windows) isso exige link.exe das Build Tools do Visual Studio. Aviso
        # upfront é melhor que deixar cada crate falhar com a mesma mensagem.
        if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
            Warn "link.exe (MSVC linker) não encontrado. Crates que compilam código nativo vão falhar."
            Warn "Opções: (a) 'winget install Microsoft.VisualStudio.2022.BuildTools --override \"--wait --passive --add Microsoft.VisualStudio.Workload.VCTools\"', OU (b) trocar para toolchain GNU: 'rustup toolchain install stable-gnu; rustup default stable-gnu' (requer MinGW)."
        }

        # cargo é um executável externo, não PS cmdlet — try/catch NÃO captura
        # seus exit codes. Precisa checar $LASTEXITCODE pra detectar falha.
        foreach ($crate in $crates) {
            cargo install --locked $crate
            if ($LASTEXITCODE -ne 0) {
                Warn "cargo install $crate falhou (exit=$LASTEXITCODE). Se for 'linker link.exe not found', veja o aviso acima sobre Build Tools."
            }
        }
    }
}

# 4. Neovim version gate — exige >= NVIM_MIN_VERSION. Mesma técnica do Nushell
# logo abaixo: strip de suffix pre-release antes do [version]::TryParse porque
# builds nightly (ex: '0.12.0-dev+g1234abc') fariam o parse retornar $null e o
# comparador virar.
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    # 'nvim --version' linha 1: 'NVIM v0.12.1'
    $nvRaw = ((nvim --version 2>$null | Select-Object -First 1) -replace '^NVIM\s+v?', '').Trim()
    $nvClean = ($nvRaw -split '[-+ ]')[0]
    $nvVer = $null
    [void][version]::TryParse($nvClean, [ref]$nvVer)
    if ($null -eq $nvVer) {
        Warn "Não consegui parsear versão do Neovim ('$nvRaw'). Validação pulada."
    } elseif ($nvVer -lt $NvimMinVersion) {
        Die "Neovim $nvRaw instalado, mas versão mínima exigida é $NvimMinVersion. Rode 'scoop update neovim'."
    } else {
        Log "Neovim $nvRaw detectado (>=$NvimMinVersion)."
    }
} else {
    Die "Neovim não encontrado no PATH após a instalação."
}

# 5. Nushell version gate — XDG_CONFIG_HOME only honored on Windows from 0.92+.
# Nightly builds emit '0.113.0-nightly.abc1234'; strip suffix before parsing
# so [version]::TryParse doesn't silently return $null.
if (Get-Command nu -ErrorAction SilentlyContinue) {
    $nuRaw = (nu --version 2>$null | Select-Object -First 1).Trim()
    $nuClean = ($nuRaw -split '[-+ ]')[0]
    $nuVer = $null
    [void][version]::TryParse($nuClean, [ref]$nuVer)
    if ($null -eq $nuVer) {
        Warn "Não consegui parsear versão do Nushell ('$nuRaw'). Validação pulada."
    } elseif ($nuVer -lt $NuMinVersion) {
        Warn "Nushell $nuRaw não respeita XDG_CONFIG_HOME no Windows (min exigido $NuMinVersion). Rode 'scoop update nu'."
    } else {
        Log "Nushell $nuRaw detectado (>=$NuMinVersion, XDG_CONFIG_HOME suportado)."
    }
}

# 6. Apply dotfiles (also runs the Windows env-var chezmoi script)
# --no-tty força stdin line-buffered nos prompts. Sem isso, chezmoi v2.70+ usa
# huh (Charm) em raw mode e cada keystroke vira "confirma com default".
Log "Applying dotfiles with chezmoi"
$ChezmoiSource = Join-Path $RepoRoot 'dotfiles'
if (-not (Test-ChezmoiInitialized)) {
    chezmoi init --source $ChezmoiSource --apply --no-tty
} else {
    chezmoi apply --source $ChezmoiSource --no-tty
}

# 7. Install language runtimes from ~/.config/mise/config.toml
#
# mise install retorna exit 0 mesmo quando um runtime individual falha
# silenciosamente (ex: 'gpg not found, skipping verification' para node, ou o
# warn Rekor do sigstore-rs que não aborta mas pode mascarar falha real).
# Rodar 'mise ls' depois expõe o estado real e serve de diagnóstico visual.
if (Get-Command mise -ErrorAction SilentlyContinue) {
    Log "Installing language runtimes via mise"
    mise install
    if ($LASTEXITCODE -ne 0) {
        Warn "mise install retornou exit=$LASTEXITCODE. Veja 'mise ls' abaixo para diagnóstico."
    }
    Log "Estado atual dos runtimes gerenciados por mise:"
    mise ls
    if ($LASTEXITCODE -ne 0) {
        Warn "'mise ls' retornou exit=$LASTEXITCODE (não-fatal)."
    }
}

# 8. Refresh font cache (Windows needs user to log out for new fonts in some apps, but WezTerm sees them immediately)
Log "Fonts installed via Scoop's nerd-fonts bucket should be available to WezTerm on next launch."

Log "Windows bootstrap complete."
Warn "Se o chezmoi escreveu env vars novas (XDG_CONFIG_HOME etc.), feche e reabra o terminal antes de usar nu/atuin/yazi — processos ativos só enxergam valores antigos."
