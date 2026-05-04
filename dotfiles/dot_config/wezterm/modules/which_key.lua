-- Which-key style cheat-sheet panel.
-- Plugin source: https://github.com/bgarciamoura/wezterm-which-key
-- Loaded via wezterm.plugin.require, which clones the repo on first launch
-- (libgit2 under the hood). Works in both full and wezterm-only profiles
-- because git is provisioned by all bootstraps.

local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

function M.apply(config)
    local which_key = wezterm.plugin.require('https://github.com/bgarciamoura/wezterm-which-key')

    which_key.apply_to_config(config, {
        leader = { key = 'b', mods = 'CTRL', timeout_milliseconds = 2000 },
        activator = { key = 'Space' },
        panel = { position = 'right', size = { Percent = 40 } },
        show_defaults = false,
        mappings = {
            { key = 'f', desc = 'Find',         action = act.Search { CaseInSensitiveString = '' } },
            { key = 'v', desc = 'Split right',  action = act.SplitPane { direction = 'Right' } },
            { key = 's', desc = 'Split below',  action = act.SplitPane { direction = 'Down' } },
            { key = 'q', desc = 'Close pane',   action = act.CloseCurrentPane { confirm = true } },
            { key = 'z', desc = 'Zoom pane',    action = act.TogglePaneZoomState },
            { key = 'h', desc = 'Focus left',   action = act.ActivatePaneDirection 'Left' },
            { key = 'j', desc = 'Focus down',   action = act.ActivatePaneDirection 'Down' },
            { key = 'k', desc = 'Focus up',     action = act.ActivatePaneDirection 'Up' },
            { key = 'l', desc = 'Focus right',  action = act.ActivatePaneDirection 'Right' },
            { key = 't', desc = 'New tab',      action = act.SpawnTab 'CurrentPaneDomain' },
            { key = 'x', desc = 'Close tab',    action = act.CloseCurrentTab { confirm = true } },
        },
    })
end

return M
