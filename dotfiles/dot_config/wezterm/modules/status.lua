local wezterm = require("wezterm")
local M = {}

local colors = {
	bg = "#1e1e2e",
	mode_normal = "#89b4fa",
	mode_leader = "#f9e2af",
	workspace = "#f5c2e7",
	cwd = "#a6e3a1",
	battery = "#fab387",
	clock = "#cba6f7",
	sep = "#6c7086",
}

local function basename(path)
	if not path then
		return ""
	end
	return path:gsub("(.*[/\\])(.*)", "%2")
end

local function segment(text, fg)
	return { { Foreground = { Color = fg } }, { Text = text } }
end

local function concat(...)
	local out = {}
	for _, group in ipairs({ ... }) do
		for _, item in ipairs(group) do
			table.insert(out, item)
		end
	end
	return out
end

function M.apply(config)
	config.status_update_interval = 1000

	wezterm.on("update-status", function(window, pane)
		local key_table = window:active_key_table()
		local mode_label = key_table and ("  " .. key_table:upper() .. " ") or "  NORMAL "
		local mode_color = key_table and colors.mode_leader or colors.mode_normal

		local workspace = window:active_workspace() or "default"

		window:set_left_status(
			wezterm.format(
				concat(
					{ { Attribute = { Intensity = "Bold" } } },
					segment(mode_label, mode_color),
					segment("│ ", colors.sep),
					segment(" " .. workspace .. " ", colors.workspace),
					segment("│", colors.sep)
				)
			)
		)

		local cwd_uri = pane:get_current_working_dir()
		local cwd = ""
		if cwd_uri then
			cwd = type(cwd_uri) == "userdata" and cwd_uri.file_path or cwd_uri
			cwd = basename(cwd)
		end

		local battery = ""
		for _, b in ipairs(wezterm.battery_info()) do
			local pct = math.floor(b.state_of_charge * 100)
			local icon = b.state == "Charging" and "󰂄" or "󰁹"
			battery = string.format(" %s %d%% ", icon, pct)
			break
		end

		local date = wezterm.strftime("  %a %d/%m  %H:%M ")

		local right = {}
		if cwd ~= "" then
			right = concat(right, segment("  " .. cwd .. " ", colors.cwd), segment("│", colors.sep))
		end
		if battery ~= "" then
			right = concat(right, segment(battery, colors.battery), segment("│", colors.sep))
		end
		right = concat(right, segment(date, colors.clock))

		window:set_right_status(wezterm.format(right))
	end)
end

return M
