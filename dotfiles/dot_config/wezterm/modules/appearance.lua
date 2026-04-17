local M = {}

function M.apply(config)
	local ok, colors = pcall(require, "colors/base16")
	if ok then
		config.colors = colors
	else
		config.color_scheme = "Catppuccin Mocha"
	end

	config.window_background_opacity = 0.98
	config.window_decorations = "RESIZE"
	config.window_padding = { left = 8, right = 8, top = 6, bottom = 6 }

	config.use_fancy_tab_bar = false
	config.hide_tab_bar_if_only_one_tab = false
	config.tab_max_width = 32

	config.scrollback_lines = 20000
	config.enable_scroll_bar = false

	config.audible_bell = "Disabled"
	config.exit_behavior = "Close"
	config.automatically_reload_config = true

	config.default_cursor_style = "BlinkingBlock"
	config.cursor_blink_rate = 400
	config.cursor_blink_ease_in = { CubicBezier = { 0.42, 0.0, 1.0, 1.0 } }
	config.cursor_blink_ease_out = { CubicBezier = { 0.0, 0.0, 0.58, 1.0 } }
end

return M
