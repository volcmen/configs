local shared = require("hyprland/shared")

local commands = shared.commands.media
local uwsm = shared.uwsm

-- Media keys
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd(uwsm.app(commands.volume_up)),
	{ description = "Raise volume", locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd(uwsm.app(commands.volume_down)),
	{ description = "Lower volume", locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd(uwsm.app(commands.toggle_mute)),
	{ description = "Toggle audio mute", locked = true, repeating = true }
)
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd(uwsm.app(commands.toggle_mic_mute)),
	{ description = "Toggle microphone mute", locked = true, repeating = true }
)

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(uwsm.app(commands.next)), { description = "Next media", locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(uwsm.app(commands.play_pause)), { description = "Play or pause media", locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(uwsm.app(commands.play_pause)), { description = "Play or pause media", locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(uwsm.app(commands.previous)), { description = "Previous media", locked = true })
