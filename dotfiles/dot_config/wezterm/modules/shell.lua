local wezterm = require 'wezterm'

local M = {}

local function is_windows()
    return wezterm.target_triple:find('windows') ~= nil
end

function M.apply(config)
    config.enable_kitty_graphics = true
    config.enable_kitty_keyboard = true

    if is_windows() then
        config.default_prog = { 'nu.exe' }
    else
        config.default_prog = { 'nu', '--login' }
    end
end

return M
