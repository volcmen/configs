-------------------
---- AUTOSTART ----
-------------------

local uwsm = require("hyprland/shared").uwsm

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function()
	-- Autostart necessary processes (like notifications daemons, status bars, etc.)
	hl.exec_cmd(uwsm.background("waybar")) -- Status bar
	hl.exec_cmd(uwsm.background("hypridle"))
	hl.exec_cmd(uwsm.background("hyprpaper")) -- Wallpaper
	hl.exec_cmd(uwsm.background("hyprsunset")) -- Blue light filter
	hl.exec_cmd(uwsm.background("/usr/lib/polkit-kde-authentication-agent-1")) -- Polkit agent, popup for password

	-- Clipboard history
	hl.exec_cmd(uwsm.background("wl-paste --type text --watch cliphist store")) -- Stores only text data
	hl.exec_cmd(uwsm.background("wl-paste --type image --watch cliphist store")) -- Stores only image data
end)

hl.on("hyprland.shutdown", function()
	-- Final Cleanup (Optional but good)
	hl.exec_cmd("uwsm stop")
end)
