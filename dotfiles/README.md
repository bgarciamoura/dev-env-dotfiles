# Dotfiles source

This is the [chezmoi](https://www.chezmoi.io/) source directory. The bootstrap
scripts run `chezmoi init --apply --source ./dotfiles` to materialize files
here into `$HOME`. See the repo-level `README.md` for the high-level layout.

This file is excluded from materialization via `.chezmoiignore` (the
`README.md` entry at the top), so it lives next to the source it documents
without polluting `$HOME`.

## `.chezmoiscripts/` contract

Files matching `run_*.{sh,ps1}.tmpl` execute during `chezmoi apply`. The
prefix encodes when they run:

- `run_once_*` — runs once per machine.
- `run_onchange_*` — runs whenever the script's hash changes.
- `run_onchange_before_*` — same, before file materialization.
- `run_onchange_after_*` — same, after file materialization.

`.chezmoiignore` gates them by OS (e.g. `*.ps1` skipped on non-Windows) and by
profile.

### Heads up: `wezterm-only` profile silently skips ALL scripts

The `wezterm-only` block in `.chezmoiignore` uses a blanket `**` pattern that
matches the target paths of `.chezmoiscripts/*` (see the header comment in
`.chezmoiignore` for how chezmoi computes target paths for scripts — short
version: it strips the `run_<attr>_` prefix and the `.tmpl` suffix). This is
intentional: wezterm-only is the Windows-as-WSL-host profile and doesn't need
XDG env vars, Nushell vendor regen, or the Neovim clone.

**If you add a script that SHOULD run in wezterm-only**, add an un-ignore
exception inside the `wezterm-only` block, e.g.:

```
{{ if eq .profile "wezterm-only" -}}
**
!.config
!.config/wezterm
!.config/wezterm/**
!.chezmoiscripts/30-wezterm-something.sh
{{ end -}}
```

Without that, your script silently does not run in wezterm-only — chezmoi
emits no warning, no diff entry, just nothing.
