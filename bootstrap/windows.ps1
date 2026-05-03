# Windows 11 bootstrap: Scoop + buckets + scoopfile.json + cargo + chezmoi apply.
# Strategy: Scoop gives us bleeding-edge versions of dev tools straight from GitHub.
# We add the 'main', 'extras', and 'nerd-fonts' buckets and then run `scoop import`.
$ErrorActionPreference = 'Stop'

function Log  { param([string]$msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn { param([string]$msg) Write-Host "!!  $msg" -ForegroundColor Yellow }
function Die  { param([string]$msg) Write-Host "xx  $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

# Lê packages/versions.env (formato KEY=VALUE) para um hashtable. Mantemos um
# parser local em vez de exigir um módulo porque PS 5.1 não tem helper nativo
# e queremos zero dependências no primeiro boot.
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

# 1. Scoop
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Log "Installing Scoop"
    # Ensure TLS 1.2 for legacy Windows builds
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Invoke-Expression (Invoke-RestMethod -Uri 'https://get.scoop.sh')
}

# 2. Essential buckets
# `scoop bucket add` imprime WARN via Write-Host (stream 6) quando o bucket
# já existe — redirecionamento de stderr não suprime. Mais simples: checar
# diretamente no filesystem se o bucket já está clonado em ~\scoop\buckets\.
Log "Configuring Scoop buckets"
$ScoopBucketDir = Join-Path $env:USERPROFILE 'scoop\buckets'
$buckets = @('extras', 'nerd-fonts', 'versions')
foreach ($b in $buckets) {
    if (-not (Test-Path (Join-Path $ScoopBucketDir $b))) {
        Log "Adding scoop bucket: $b"
        scoop bucket add $b
    }
}

# `git` is a hard requirement for scoop buckets
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log "Installing git (scoop prerequisite)"
    scoop install git
}

Log "Updating Scoop and all installed packages"
scoop update

# 3. Install packages from scoopfile.json
# Instalação de nerd-fonts no Scoop falha com 'Access is denied' quando o
# serviço FontCache do Windows está com handle aberto num .ttf que o installer
# script quer sobrescrever (typical após tentativa anterior ou com terminal
# usando a fonte em outra janela). O fix canônico é parar FontCache, remover
# os .ttf e suas entradas em HKCU\...\Fonts, reiniciar FontCache e reinstalar.
$ScoopFile = Join-Path $RepoRoot 'packages\scoopfile.json'

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
        Warn "Sessão não-elevada: Stop-Service FontCache será pulado. Se algum .ttf estiver locked pelo FontCache, o repair vai falhar. Para garantir: reabra PowerShell como administrador e rode .\\install.ps1 de novo."
    }

    # scoop uninstall é best-effort: falha silenciosa se app não está instalado
    # ou se o uninstaller script também bateu no lock. Ok — seguimos.
    scoop uninstall $App 2>$null | Out-Null

    # Parar FontCache libera os handles que ele segura nos .ttf. Requer admin.
    $fontCacheRunning = $false
    if ($isAdmin) {
        try {
            $svc = Get-Service -Name FontCache -ErrorAction Stop
            if ($svc.Status -eq 'Running') {
                $fontCacheRunning = $true
                Stop-Service FontCache -Force -ErrorAction SilentlyContinue
            }
        } catch {
            # Serviço pode não existir em edições mínimas do Windows — ignora.
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
                # Installer grava como '<basename> (TrueType)' — converter padrão de arquivo pro padrão do valor de registro.
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

if (Test-Path $ScoopFile) {
    Log "Importing packages from scoopfile.json"
    $importFailed = $false
    try {
        scoop import $ScoopFile
    } catch {
        $importFailed = $true
        Warn "scoop import reportou falha: $($_.Exception.Message)"
        Warn "Tentando remediar fontes nerd-fonts individualmente..."
    }

    if ($importFailed) {
        # Padrões dos arquivos que cada installer script copia para Fonts/.
        # Confirmados em 04/2026 nos manifests do matthewjberger/scoop-nerd-fonts.
        # JetBrainsMono-NF usa filter '*NerdFont-*' — família inclui variantes
        # NL (No Ligatures), Mono e Propo; padrão DEVE ter wildcard entre
        # 'JetBrainsMono' e 'NerdFont' para pegar 'JetBrainsMonoNLNerdFont*'.
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
    Warn "scoopfile.json not found at $ScoopFile — skipping bulk install"
}

# 4. Rust toolchain + cargo tools
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

# 5. Neovim version gate — exige >= 0.12.0. Mesma técnica do Nushell logo abaixo:
# strip de suffix pre-release antes do [version]::TryParse porque builds nightly
# (ex: '0.12.0-dev+g1234abc') fariam o parse retornar $null e o comparador virar.
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

# 6. Nushell version gate — XDG_CONFIG_HOME only honored on Windows from 0.92+.
# Nightly builds emit '0.113.0-nightly.abc1234'; strip suffix before parsing
# so [version]::TryParse doesn't silently return $null (PS 5.1 treats $null -lt
# version as $true, flipping the check).
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

# 7. Apply dotfiles (also runs the Windows env-var chezmoi script)
Log "Applying dotfiles with chezmoi"
$ChezmoiSource = Join-Path $RepoRoot 'dotfiles'

# chezmoi grava seu config.toml em $XDG_CONFIG_HOME\chezmoi\ quando a var está
# setada; senão cai no default Windows de $APPDATA\chezmoi\. Na primeira execução
# o XDG_CONFIG_HOME ainda não foi persistido pelo script de env vars, então o
# arquivo real pode estar em qualquer um dos dois. Checar ambos evita re-prompt
# desnecessário (promptStringOnce) em execuções subsequentes.
$chezmoiCfgCandidates = @(
    (Join-Path $env:USERPROFILE '.config\chezmoi\chezmoi.toml'),
    (Join-Path $env:APPDATA 'chezmoi\chezmoi.toml')
)
$chezmoiInitialized = $false
foreach ($p in $chezmoiCfgCandidates) {
    if (Test-Path $p) { $chezmoiInitialized = $true; break }
}

# --no-tty força stdin line-buffered nos prompts. Sem isso, chezmoi v2.70+ usa
# huh (Charm) em raw mode e cada keystroke vira "confirma com default".
if (-not $chezmoiInitialized) {
    chezmoi init --source $ChezmoiSource --apply --no-tty
} else {
    chezmoi apply --source $ChezmoiSource --no-tty
}

# 8. Install language runtimes from ~/.config/mise/config.toml
#
# mise install retorna exit 0 mesmo quando um runtime individual falha
# silenciosamente (ex: 'gpg not found, skipping verification' para node,
# ou o warn Rekor do sigstore-rs que não aborta mas pode mascarar falha real).
# Rodar 'mise ls' depois expõe o estado real e serve de diagnóstico visual
# sem precisar parsear o output da instalação.
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

# 9. Refresh font cache (Windows needs user to log out for new fonts in some apps, but WezTerm sees them immediately)
Log "Fonts installed via Scoop's nerd-fonts bucket should be available to WezTerm on next launch."

Log "Windows bootstrap complete."
Warn "Se o chezmoi escreveu env vars novas (XDG_CONFIG_HOME etc.), feche e reabra o terminal antes de usar nu/atuin/yazi — processos ativos só enxergam valores antigos."
