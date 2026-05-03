# new-dev-setup

Reproducible development environment for **Windows 11, macOS, Ubuntu, and Debian**.

## Stack

| Role         | Tool                                        |
|--------------|---------------------------------------------|
| Terminal     | WezTerm (Kitty graphics + Sixel)            |
| Shell        | Nushell (+ Carapace for completions)        |
| Multiplexer  | Zellij                                      |
| Prompt       | Starship                                    |
| Editor       | Neovim (your modular setup)                 |
| Theming      | Chezmoi-driven palette (`.chezmoidata/themes.toml`) |
| Font         | JetBrainsMono Nerd Font / Maple Mono NF     |
| File manager | Yazi                                        |
| History      | Atuin (synced across machines)              |
| Dotfiles     | Chezmoi                                     |

## Architecture

Two layers:

1. **Binaries / tools** — installed by the OS package manager on each platform, pinned to the latest available versions.
2. **Configuration** — managed by Chezmoi from a single Git repository (`dotfiles/` in this repo is the source).

The bootstrap scripts install the package managers, install every tool, install Chezmoi, and run `chezmoi init --apply`. After that, you have a fully configured machine.

## Package manager strategy (latest versions)

| Platform    | Primary                             | Fallback for niche tools  |
|-------------|-------------------------------------|---------------------------|
| Windows 11  | **Scoop** (+ `main`, `extras`, `nerd-fonts` buckets) | `cargo`, `winget` |
| macOS       | **Homebrew**                        | `cargo`                   |
| Ubuntu/Debian | **Homebrew on Linux** (`brew`)    | `cargo`, `apt` (only if required) |

Homebrew on Linux gives you the **same latest versions** as on macOS, using the **same Brewfile**. This is the key trick for uniform latest packages on Unix. Scoop does the equivalent on Windows: it pulls binaries directly from GitHub releases, so versions stay current.

## First-time setup

### Windows 11 (PowerShell as Administrator)

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
irm https://raw.githubusercontent.com/<your-user>/new-dev-setup/main/install.ps1 | iex
```

Or, from a local clone:

```powershell
cd C:\Users\<you>\projects\new-dev-setup
.\install.ps1
```

> **PowerShell 7+ required.** The entry point `install.ps1` is ASCII-only and can be launched from Windows PowerShell 5.1; it auto-installs PowerShell 7 via `winget` on the first run and re-launches itself under `pwsh`. The rest of the bootstrap (which contains Portuguese messages and other UTF-8 content) runs under PS 7 where UTF-8 is the default parser encoding.

### macOS / Ubuntu / Debian

```bash
curl -fsSL https://raw.githubusercontent.com/<your-user>/new-dev-setup/main/install.sh | bash
```

Or, from a local clone:

```bash
cd ~/projects/new-dev-setup
./install.sh
```

The script:

1. Installs the platform package manager (Scoop or Homebrew) if missing.
2. Installs every tool listed in `packages/Brewfile` (Unix) or `packages/scoopfile.json` (Windows).
3. Installs Nerd Fonts.
4. Installs Chezmoi and runs `chezmoi init --apply --source ./dotfiles` so your configs land in `~/.config/...`.
5. Optional: runs `atuin login` if `ATUIN_USERNAME` is set.

### Windows 11 — wezterm-only profile (host for WSL)

Use this when Windows is just the GUI host for WezTerm and your real dev environment lives in WSL. It installs only what's needed for the terminal window to render — no Nushell, Starship, mise, Atuin, Neovim, etc. on the Windows side.

```powershell
cd C:\Users\<you>\projects\new-dev-setup
.\install-wezterm-only.ps1
```

What gets installed on Windows:

- **Scoop** + `extras` and `nerd-fonts` buckets
- **git**, **chezmoi**, **wezterm**
- **JetBrainsMono Nerd Font**, **Maple Mono NF**

What does NOT get installed (compared to the full profile):

- Nushell, Starship, Zellij, Atuin, Yazi, mise, Neovim
- Rust toolchain, cargo tools
- Language runtimes (Node, Python)
- XDG_CONFIG_HOME and other env vars (the `run_onchange_before_00-windows-env-vars` script is skipped)
- Neovim repo clone (`run_onchange_after_20-clone-nvim` script is skipped)

What gets configured by Chezmoi:

- Only `~/.config/wezterm/` (entry point + modules: `appearance`, `font`, `keys`, `shell`, `status`)
- Nothing else under `~/.config/`

During `chezmoi init` you'll be asked an extra question: **`Use WSL as the WezTerm shell on Windows?`** Answer `yes` and provide a distro name (run `wsl -l -q` in PowerShell to see exact names — typically `Ubuntu-24.04`). The generated `shell.lua` will spawn `wsl.exe -d <distro> --cd ~ -- nu --login`, landing you in your Linux home with Nushell as login shell.

To install the full profile inside WSL afterwards:

```bash
# inside WSL
git clone https://github.com/<your-user>/new-dev-setup ~/projects/new-dev-setup
cd ~/projects/new-dev-setup
./install.sh
```

When chezmoi asks for the profile inside WSL, choose `full`. The same dotfiles repo serves both sides: WezTerm config on Windows, everything else on WSL.

#### Switching between profiles on the same machine

The `profile` answer is stored in `~/.config/chezmoi/chezmoi.toml` (or `%APPDATA%\chezmoi\chezmoi.toml` on Windows). To switch:

```powershell
chezmoi edit-config           # change profile = "wezterm-only"  →  "full" (or vice-versa)
chezmoi apply
```

Or re-prompt all answers:

```powershell
chezmoi init --source dotfiles --force
chezmoi apply
```

Note: switching from `full` to `wezterm-only` does NOT uninstall packages — it only stops materializing their config files. Use `scoop uninstall` manually if you want to free disk space.

## Versões: runtimes e mínimos de CLI

Dois pontos de controle de versão, separados por intenção:

**1. Runtimes de linguagem via `mise`** (`dotfiles/dot_config/mise/config.toml`)

Pin exato de Node, Python, etc. Cross-OS. Rodado automaticamente pelo bootstrap via `mise install` após `chezmoi apply`. Edite o `[tools]` e rode `chezmoi apply && mise install` para aplicar mudanças.

```toml
[tools]
node = "22"      # major pinado, patch na mais recente
python = "3.13"
# go = "1.23"    # adicione conforme precisar
```

Sintaxes aceitas: pin exato (`"22.11.0"`), major (`"22"`), `"lts"` (só node), `"latest"`, ou `"system"`.

**2. Mínimos para CLIs instalados via brew/scoop** (`packages/versions.env`)

Brew e Scoop sempre puxam a última versão do package manager — aqui você declara a **versão mínima** aceitável. Se o binário ficar abaixo, o bootstrap aborta com instrução de upgrade.

```
NVIM_MIN_VERSION=0.12.0
NU_MIN_VERSION=0.92.0
```

Para exigir um novo mínimo: aumente o valor no arquivo. Nenhum código de gate muda.

### Troubleshooting do `mise install`

Depois do bootstrap, o script imprime `mise ls` — o estado real dos runtimes. Se algum runtime esperado não aparecer com versão instalada:

1. **Rode manualmente com verbose** para ver a causa:
   ```powershell
   mise install node@22 --verbose
   ```
   ```bash
   mise install node@22 --verbose
   ```

2. **Dependência GPG:** o plugin `node` do mise verifica downloads via GPG. `gpg`/`gnupg` estão declarados no `scoopfile.json` e `Brewfile`, mas se o binário não estiver no PATH, você verá `gpg not found, skipping verification`. Reabra o terminal (ou rode `scoop install gpg` / `brew install gnupg`) e tente de novo.

3. **Warning do Rekor (cosmético):** mensagens do tipo `Cannot parse Rekor public key ... Ecdsa-P256 ... OID: 1.2.840.10045.2.1` vêm de um bug upstream no `sigstore-rs` ([jdx/mise Discussion #8217](https://github.com/jdx/mise/discussions/8217)) — não abortam o install. Desaparecerão quando o mise bumpar a dependência.

4. **Nuclear option:** se GPG + retry manual falharem, pule a verificação só pra esse install:
   ```powershell
   $env:MISE_NODE_VERIFY=$false; mise install node@22
   ```
   ```bash
   MISE_NODE_VERIFY=false mise install node@22
   ```
   Trade-off explícito: você perde a checagem criptográfica do binário.

## Keeping machines in sync

After the first install, any change lives in Git:

```bash
# Edit the source (e.g., the Nushell config)
chezmoi edit ~/.config/nushell/config.nu

# Review diff and apply
chezmoi diff
chezmoi apply

# Push upstream so the other machines can pull it
chezmoi cd
git add -A && git commit -m "tweak nu config" && git push
```

On another machine:

```bash
chezmoi update   # git pull + apply in one go
```

## Customization prompts

The first time you run `chezmoi init`, you'll be asked for:

- **Full name** and **email** (used by `git`, editors, etc.)
- **Machine class**: `personal` / `work`
- **Default font**: `JetBrainsMono Nerd Font` / `Maple Mono NF`
- **Theme**: picks a palette from `dotfiles/.chezmoidata/themes.toml` (default `oasis-lagoon-dark`)

These answers are stored in `~/.config/chezmoi/chezmoi.toml` and drive conditional logic in the templates (e.g., different WezTerm font, different git email per machine, same palette applied to WezTerm + Starship + Zellij).

## Themes

Palettes are catalogued in `dotfiles/.chezmoidata/themes.toml`. The active theme is picked by the `theme` answer stored in `~/.config/chezmoi/chezmoi.toml`, and the templates under `dot_config/` consume that palette so WezTerm, Starship, and Zellij all change together. Works identically on Windows, macOS, and Linux, with no extra runtime.

Default is `oasis-lagoon-dark`, adapted from [uhs-robert/oasis.nvim](https://github.com/uhs-robert/oasis.nvim).

### Switching themes

Three ways, fastest first:

1. **Edit the chezmoi config directly** (no re-prompt of other fields):

   ```bash
   chezmoi edit-config        # opens ~/.config/chezmoi/chezmoi.toml
   # change: theme = "oasis-lagoon-dark"  →  theme = "oasis-desert-dark"
   chezmoi apply
   ```

2. **Re-run the prompts** (asks every question again):

   ```bash
   chezmoi init --source dotfiles --force
   chezmoi apply
   ```

3. **One-off override** (useful for testing without persisting):

   ```bash
   chezmoi apply --source dotfiles --no-tty -D theme=oasis-desert-dark
   ```

After any of the above, reopen WezTerm/shell/Zellij and the new palette is in effect everywhere.

### Adding a new theme

Three files to touch:

**1. Append a palette block to `dotfiles/.chezmoidata/themes.toml`.** All keys are required — the templates reference them by name. Copy an existing block and swap the hex values:

```toml
[themes.oasis-desert-dark]
name    = "Oasis Desert Dark"
variant = "dark"
bg        = "#..."
fg        = "#..."
# ... same keys as oasis-lagoon-dark
accent_user   = "#..."
accent_dir    = "#..."
# ...
```

For Oasis variants, hex values are already published in [`extras/wezterm/themes/dark/`](https://github.com/uhs-robert/oasis.nvim/tree/main/extras/wezterm/themes/dark) and [`extras/starship/themes/dark/`](https://github.com/uhs-robert/oasis.nvim/tree/main/extras/starship/themes/dark) — mechanical mapping.

**2. Add the name to the prompt in `dotfiles/.chezmoi.toml.tmpl`:**

```diff
-{{- $theme := promptChoiceOnce . "theme" "Theme..." (list "oasis-lagoon-dark") "oasis-lagoon-dark" -}}
+{{- $theme := promptChoiceOnce . "theme" "Theme..." (list "oasis-lagoon-dark" "oasis-desert-dark") "oasis-lagoon-dark" -}}
```

**3. Create the matching Zellij theme file at `dotfiles/dot_config/zellij/themes/<name>.kdl`.** Zellij requires one KDL file per variant — WezTerm and Starship read straight from `.chezmoidata/themes.toml`, but Zellij is separate by design of the tool itself.

```kdl
themes {
    oasis-desert-dark {
        fg      "#..."
        bg      "#..."
        black   "#..."
        red     "#..."
        green   "#..."
        yellow  "#..."
        blue    "#..."
        magenta "#..."
        cyan    "#..."
        white   "#..."
        orange  "#..."
    }
}
```

Then apply:

```bash
chezmoi apply
```

## Repository layout

```
new-dev-setup/
├── README.md
├── install.sh                   # Unix entry point (macOS + Linux)
├── install.ps1                  # Windows entry point — full profile
├── install-wezterm-only.ps1     # Windows entry point — wezterm-only profile
├── bootstrap/
│   ├── macos.sh                 # macOS package install
│   ├── linux.sh                 # Ubuntu/Debian package install
│   ├── windows.ps1              # Windows package install (full)
│   └── windows-wezterm-only.ps1 # Windows package install (wezterm-only)
├── packages/
│   ├── Brewfile                 # macOS + Linux packages
│   ├── scoopfile.json           # Windows packages — full
│   ├── scoopfile-wezterm-only.json # Windows packages — wezterm-only subset
│   ├── cargo-tools.txt          # Rust tools (universal fallback)
│   └── versions.env             # Versões mínimas dos CLIs (gates pós-instalação)
└── dotfiles/                    # Chezmoi source directory
    ├── .chezmoiroot
    ├── .chezmoi.toml.tmpl       # Initial prompts
    ├── .chezmoiignore
    ├── .chezmoidata/
    │   └── themes.toml          # Central theme catalogue (consumed by templates)
    ├── .chezmoiscripts/
    │   ├── run_onchange_after_10-post-apply.sh.tmpl
    │   └── run_onchange_before_00-windows-env-vars.ps1.tmpl  # Windows-only
    └── dot_config/
        ├── nushell/
        │   ├── config.nu.tmpl
        │   └── env.nu.tmpl
        ├── wezterm/
        │   ├── wezterm.lua.tmpl
        │   └── modules/
        │       ├── appearance.lua.tmpl  # color scheme driven by .theme
        │       ├── status.lua.tmpl      # status bar colors from theme
        │       ├── font.lua.tmpl
        │       ├── keys.lua
        │       └── shell.lua
        ├── zellij/
        │   ├── config.kdl.tmpl  # theme name comes from .theme
        │   └── themes/
        │       └── oasis-lagoon-dark.kdl
        ├── starship.toml.tmpl   # pastel-powerline layout + themed palette
        ├── atuin/
        │   └── config.toml
        ├── mise/
        │   └── config.toml      # Runtimes pinados (node, python, ...)
        ├── yazi/
        │   └── yazi.toml
        └── carapace/
            └── specs/           # (empty — add custom specs here)
```

## Day-two notes

- **Atuin sync**: after install, run `atuin register` on your first machine, then `atuin login` on the others. History syncs automatically.
- **Neovim config**: provisionada automaticamente. Um script `.chezmoiscripts/run_onchange_after_20-clone-nvim.*` clona [`bgarciamoura/neovim`](https://github.com/bgarciamoura/neovim) em `~/.config/nvim` durante `chezmoi apply` e roda `scripts/install-deps.sh` do próprio repo. Lógica idempotente: se `~/.config/nvim` já for working copy do repo, pula; se existir com outro conteúdo, faz backup em `~/.config/nvim.bak-YYYYMMDD-HHMMSS` antes de clonar. Para sincronizar entre máquinas depois do bootstrap, `cd ~/.config/nvim && git pull` — é um working copy Git normal. Deps externas (ripgrep, Node ≥18, Python ≥3.10, git, Nerd Font) já são cobertas pelo Brewfile/scoopfile + mise.
- **Themes**: see the dedicated [Themes](#themes) section above for how to switch palettes or add new ones.
- **Upgrading everything**: run `./install.sh` (or `install.ps1`) again — it's idempotent.

## Windows: paths resolvidos via env vars

No Windows várias ferramentas da stack ignoram XDG por padrão e procuram config em `%APPDATA%\<tool>\` (Nushell, Atuin, Yazi) ou `%LOCALAPPDATA%\<tool>\` (Mise). Para que `~/.config/*` seja a fonte única de verdade em todos os SOs, o Chezmoi roda um script `.ps1` em Windows que grava variáveis persistentes no escopo **User** do registro (`HKCU\Environment`):

| Variável | Valor |
|---|---|
| `XDG_CONFIG_HOME` | `%USERPROFILE%\.config` |
| `XDG_DATA_HOME` | `%USERPROFILE%\.local\share` |
| `XDG_CACHE_HOME` | `%USERPROFILE%\.cache` |
| `STARSHIP_CONFIG` | `%USERPROFILE%\.config\starship.toml` |
| `ATUIN_CONFIG_DIR` | `%USERPROFILE%\.config\atuin` |
| `MISE_CONFIG_DIR` | `%USERPROFILE%\.config\mise` |
| `YAZI_CONFIG_HOME` | `%USERPROFILE%\.config\yazi` |
| `_ZO_DATA_DIR` | `%USERPROFILE%\.local\share\zoxide` |

O script é idempotente (compara antes de escrever). **Caveat**: `SetEnvironmentVariable('User')` só aparece em processos **novos** — feche e reabra o terminal após o primeiro `install.ps1`. Nushell precisa ser ≥0.92 para honrar `XDG_CONFIG_HOME` no Windows; o bootstrap avisa se a versão for menor.

Carapace e Neovim são cobertos automaticamente por herdarem `XDG_CONFIG_HOME`. WezTerm já reconhece `~/.config/wezterm/wezterm.lua` nativamente. Zellij não roda em Windows nativo (só WSL), então foi ignorado.

## Troubleshooting

- **`chezmoi` says "destination directory is not empty"** — that's fine. Run `chezmoi diff` to see what would change, then `chezmoi apply` when you're happy.
- **Nushell doesn't find Carapace** — run `carapace _carapace nushell | save -f ~/.cache/carapace/init.nu` and make sure your `env.nu` sources it.
- **Fonts not rendering** — on Linux, run `fc-cache -fv` after install. On Windows, restart WezTerm.
- **Homebrew on Linux not on PATH** — add `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` to your shell profile (the installer does this automatically on first run).
- **Windows: Nushell/Atuin/Yazi abrem com config padrão** — o script PowerShell do Chezmoi setou as env vars, mas o terminal atual não as vê. Feche e reabra o terminal. Se persistir, verifique `[Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME','User')`.
