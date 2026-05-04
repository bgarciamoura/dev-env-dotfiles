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
| Windows 11  | **Scoop** (+ `main`, `extras`, `nerd-fonts` buckets) | `winget` |
| macOS       | **Homebrew**                        | —                         |
| Ubuntu/Debian | **Homebrew on Linux** (`brew`)    | `apt` (only if required) |

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

> **PowerShell 7+ required.** The entry point `install.ps1` is ASCII-only and can be launched from Windows PowerShell 5.1; it auto-installs PowerShell 7 via `winget` on the first run and re-launches itself under `pwsh`. The rest of the bootstrap (which contains non-ASCII content like em-dashes and accented characters) runs under PS 7 where UTF-8 is the default parser encoding.

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
- Language runtimes (Node, Python)
- XDG_CONFIG_HOME and other env vars (the `run_onchange_before_00-windows-env-vars` script is skipped)
- Neovim repo clone (`run_onchange_after_20-clone-nvim` script is skipped)

What gets configured by Chezmoi:

- Only `~/.config/wezterm/` (entry point + modules: `appearance`, `font`, `keys`, `shell`, `status`, `which_key`)
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

## Versions: runtimes and CLI minimums

Two version control points, separated by intent:

**1. Language runtimes via `mise`** (`dotfiles/dot_config/mise/config.toml`)

Exact pin for Node, Python, etc. Cross-OS. Run automatically by the bootstrap via `mise install` after `chezmoi apply`. Edit `[tools]` and run `chezmoi apply && mise install` to apply changes.

```toml
[tools]
node = "22"      # major pinned, latest patch
python = "3.13"
# go = "1.23"    # add as needed
```

Accepted syntaxes: exact pin (`"22.11.0"`), major (`"22"`), `"lts"` (node only), `"latest"`, or `"system"`.

**2. Minimums for CLIs installed via brew/scoop** (`packages/versions.env`)

Brew and Scoop always pull the latest version from the package manager — here you declare the **minimum acceptable version**. If the installed binary falls below it, the bootstrap aborts with an upgrade instruction.

```
NVIM_MIN_VERSION=0.12.0
NU_MIN_VERSION=0.92.0
```

To require a new minimum: bump the value in the file. No gating code changes.

### Troubleshooting `mise install`

After the bootstrap, the script prints `mise ls` — the actual state of the runtimes. If a runtime you expect doesn't show up as installed:

1. **Re-run manually with verbose** to see the cause:
   ```powershell
   mise install node@22 --verbose
   ```
   ```bash
   mise install node@22 --verbose
   ```

2. **GPG dependency:** mise's `node` plugin verifies downloads via GPG. `gpg`/`gnupg` are declared in `scoopfile.json` and `Brewfile`, but if the binary is not on PATH you'll see `gpg not found, skipping verification`. Reopen your terminal (or run `scoop install gpg` / `brew install gnupg`) and retry.

3. **Rekor warning (cosmetic):** messages like `Cannot parse Rekor public key ... Ecdsa-P256 ... OID: 1.2.840.10045.2.1` come from an upstream bug in `sigstore-rs` ([jdx/mise Discussion #8217](https://github.com/jdx/mise/discussions/8217)) — they don't abort the install. They'll go away when mise bumps the dependency.

4. **Nuclear option:** if GPG + manual retry both fail, skip verification just for this install:
   ```powershell
   $env:MISE_NODE_VERIFY=$false; mise install node@22
   ```
   ```bash
   MISE_NODE_VERIFY=false mise install node@22
   ```
   Explicit trade-off: you lose cryptographic verification of the binary.

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
│   └── versions.env             # Minimum CLI versions (post-install gates)
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
        │       ├── shell.lua
        │       └── which_key.lua        # which-key cheat-sheet plugin loader
        ├── zellij/
        │   ├── config.kdl.tmpl  # theme name comes from .theme
        │   └── themes/
        │       └── oasis-lagoon-dark.kdl
        ├── starship.toml.tmpl   # pastel-powerline layout + themed palette
        ├── atuin/
        │   └── config.toml
        ├── mise/
        │   └── config.toml      # Pinned runtimes (node, python, ...)
        ├── yazi/
        │   └── yazi.toml
        └── carapace/
            └── specs/           # (empty — add custom specs here)
```

## Day-two notes

- **Atuin sync**: after install, run `atuin register` on your first machine, then `atuin login` on the others. History syncs automatically.
- **Neovim config**: provisioned automatically. A `.chezmoiscripts/run_onchange_after_20-clone-nvim.*` script clones [`bgarciamoura/neovim`](https://github.com/bgarciamoura/neovim) into `~/.config/nvim` during `chezmoi apply` and runs the repo's own `scripts/install-deps.sh`. Idempotent logic: if `~/.config/nvim` is already a working copy of the repo, skip; if it exists with different content, back up to `~/.config/nvim.bak-YYYYMMDD-HHMMSS` before cloning. To sync between machines after the bootstrap, `cd ~/.config/nvim && git pull` — it's a normal Git working copy. External deps (ripgrep, Node ≥18, Python ≥3.10, git, Nerd Font) are already covered by Brewfile/scoopfile + mise.
- **Themes**: see the dedicated [Themes](#themes) section above for how to switch palettes or add new ones.
- **Upgrading everything**: run `./install.sh` (or `install.ps1`) again — it's idempotent.

## Windows: paths resolved via env vars

On Windows, several tools in the stack ignore XDG by default and look for config in `%APPDATA%\<tool>\` (Nushell, Atuin, Yazi) or `%LOCALAPPDATA%\<tool>\` (Mise). For `~/.config/*` to be the single source of truth across all OSes, Chezmoi runs a `.ps1` script on Windows that writes persistent variables in the **User** scope of the registry (`HKCU\Environment`):

| Variable | Value |
|---|---|
| `XDG_CONFIG_HOME` | `%USERPROFILE%\.config` |
| `XDG_DATA_HOME` | `%USERPROFILE%\.local\share` |
| `XDG_CACHE_HOME` | `%USERPROFILE%\.cache` |
| `STARSHIP_CONFIG` | `%USERPROFILE%\.config\starship.toml` |
| `ATUIN_CONFIG_DIR` | `%USERPROFILE%\.config\atuin` |
| `MISE_CONFIG_DIR` | `%USERPROFILE%\.config\mise` |
| `YAZI_CONFIG_HOME` | `%USERPROFILE%\.config\yazi` |
| `_ZO_DATA_DIR` | `%USERPROFILE%\.local\share\zoxide` |

The script is idempotent (compares before writing). **Caveat**: `SetEnvironmentVariable('User')` only takes effect in **new** processes — close and reopen the terminal after the first `install.ps1`. Nushell must be ≥0.92 to honor `XDG_CONFIG_HOME` on Windows; the bootstrap warns if the installed version is older.

Carapace and Neovim are covered automatically since they inherit `XDG_CONFIG_HOME`. WezTerm already recognizes `~/.config/wezterm/wezterm.lua` natively. Zellij doesn't run on native Windows (WSL only), so it was skipped.

## Troubleshooting

- **`chezmoi` says "destination directory is not empty"** — that's fine. Run `chezmoi diff` to see what would change, then `chezmoi apply` when you're happy.
- **Nushell doesn't find Carapace** — run `carapace _carapace nushell | save -f ~/.cache/carapace/init.nu` and make sure your `env.nu` sources it.
- **Fonts not rendering** — on Linux, run `fc-cache -fv` after install. On Windows, restart WezTerm.
- **Homebrew on Linux not on PATH** — add `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` to your shell profile (the installer does this automatically on first run).
- **Windows: Nushell/Atuin/Yazi open with default config** — the Chezmoi PowerShell script set the env vars, but the current terminal doesn't see them. Close and reopen the terminal. If it persists, check `[Environment]::GetEnvironmentVariable('XDG_CONFIG_HOME','User')`.
