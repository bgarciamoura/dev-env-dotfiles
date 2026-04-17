local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

function M.apply(config)
    config.keys = {
        { key = 'Enter', mods = 'ALT',        action = act.ToggleFullScreen },
        { key = '=',     mods = 'CTRL',       action = act.IncreaseFontSize },
        { key = '-',     mods = 'CTRL',       action = act.DecreaseFontSize },
        { key = '0',     mods = 'CTRL',       action = act.ResetFontSize },
        { key = 'v',     mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
        { key = 'c',     mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
        { key = 'f',     mods = 'CTRL|SHIFT', action = act.Search { CaseInSensitiveString = '' } },
    }
end

return M
