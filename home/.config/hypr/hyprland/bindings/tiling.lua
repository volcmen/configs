local mainMod = require("hyprland/shared").modifiers.main

-- Close windows
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Session
hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("loginctl lock-session"), { description = "Lock Session" })

-- Control tiling
hl.bind(mainMod .. " + O", hl.dsp.layout("togglesplit"), { description = "Toggle window split" }) -- dwindle only
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo(), { description = "Pseudo window" })
hl.bind(
	mainMod .. " + T",
	hl.dsp.window.float({ action = "toggle" }),
	{ description = "Toggle window floating/tiling" }
)
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { description = "Full screen" })
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "Full width" })

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Swap active window with the one next to it with mainMod + SHIFT + arrow keys
hl.bind(
	mainMod .. " + SHIFT + LEFT",
	hl.dsp.window.swap({ direction = "l" }),
	{ description = "Swap window to the left" }
)
hl.bind(
	mainMod .. " + SHIFT + RIGHT",
	hl.dsp.window.swap({ direction = "r" }),
	{ description = "Swap window to the right" }
)
hl.bind(mainMod .. " + SHIFT + UP", hl.dsp.window.swap({ direction = "u" }), { description = "Swap window up" })
hl.bind(mainMod .. " + SHIFT + DOWN", hl.dsp.window.swap({ direction = "d" }), { description = "Swap window down" })

-- Resize active window
hl.bind(
	mainMod .. " + minus",
	hl.dsp.window.resize({ x = -100, y = 0, relative = true }),
	{ description = "Expand window left" }
)
hl.bind(
	mainMod .. " + equal",
	hl.dsp.window.resize({ x = 100, y = 0, relative = true }),
	{ description = "Shrink window left" }
)
hl.bind(
	mainMod .. " + SHIFT + minus",
	hl.dsp.window.resize({ x = 0, y = -100, relative = true }),
	{ description = "Shrink window up" }
)
hl.bind(
	mainMod .. " + SHIFT + equal",
	hl.dsp.window.resize({ x = 0, y = 100, relative = true }),
	{ description = "Expand window down" }
)

------------------
---- VIM MODE ----
------------------

-- Move focus with mainMod + hjkl
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }), { description = "Move focus left" })
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }), { description = "Move focus up" })
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }), { description = "Move focus down" })

-- Swap active window with the one next to it with mainMod + SHIFT + hjkl
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.window.swap({ direction = "l" }), { description = "Swap window to the left" })
hl.bind(
	mainMod .. " + SHIFT + L",
	hl.dsp.window.swap({ direction = "r" }),
	{ description = "Swap window to the right" }
)
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.window.swap({ direction = "u" }), { description = "Swap window up" })
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.window.swap({ direction = "d" }), { description = "Swap window down" })

-- Resize active window with mainMod + CTRL + hjkl
hl.bind(
	mainMod .. " + CTRL + H",
	hl.dsp.window.resize({ x = -100, y = 0, relative = true }),
	{ description = "Expand window left" }
)
hl.bind(
	mainMod .. " + CTRL + L",
	hl.dsp.window.resize({ x = 100, y = 0, relative = true }),
	{ description = "Shrink window left" }
)
hl.bind(
	mainMod .. " + CTRL + K",
	hl.dsp.window.resize({ x = 0, y = -100, relative = true }),
	{ description = "Shrink window up" }
)
hl.bind(
	mainMod .. " + CTRL + J",
	hl.dsp.window.resize({ x = 0, y = 100, relative = true }),
	{ description = "Expand window down" }
)
