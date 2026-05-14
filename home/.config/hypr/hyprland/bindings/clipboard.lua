-- Work around Hyprland send_shortcut sometimes leaving synthetic key state stuck/repeating.
-- https://github.com/hyprwm/Hyprland/discussions/14099
local shared = require("hyprland/shared")

local commands = shared.commands
local mainMod = shared.modifiers.main
local uwsm = shared.uwsm

local function send_shortcut_once(mods, key)
	return function()
		hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down", window = "activewindow" }))

		hl.timer(function()
			hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up", window = "activewindow" }))
		end, { timeout = 50, type = "oneshot" })
	end
end

-- Clipboard Copy / Paste
hl.bind(mainMod .. " + C", send_shortcut_once("CTRL", "Insert"), { description = "Universal copy" })
hl.bind(mainMod .. " + V", send_shortcut_once("SHIFT", "Insert"), { description = "Universal paste" })
hl.bind(mainMod .. " + X", send_shortcut_once("CTRL", "X"), { description = "Universal cut" })
hl.bind(
	mainMod .. " + CTRL + V",
	hl.dsp.exec_cmd(uwsm.shell(commands.clipboard.manager)),
	{ description = "Clipboard manager" }
)
