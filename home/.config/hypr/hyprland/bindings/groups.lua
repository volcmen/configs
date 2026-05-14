local mainMod = require("hyprland/shared").modifiers.main

-- Toggle groups
hl.bind(mainMod .. " + G", hl.dsp.group.toggle(), { description = "Toggle window grouping" })
hl.bind(
	mainMod .. " + ALT + G",
	hl.dsp.window.move({ out_of_group = true }),
	{ description = "Move active window out of group" }
)

-- Join groups
hl.bind(
	mainMod .. " + ALT + LEFT",
	hl.dsp.window.move({ into_group = "l" }),
	{ description = "Move window to group on left" }
)
hl.bind(
	mainMod .. " + ALT + RIGHT",
	hl.dsp.window.move({ into_group = "r" }),
	{ description = "Move window to group on right" }
)
hl.bind(
	mainMod .. " + ALT + UP",
	hl.dsp.window.move({ into_group = "u" }),
	{ description = "Move window to group on top" }
)
hl.bind(
	mainMod .. " + ALT + DOWN",
	hl.dsp.window.move({ into_group = "d" }),
	{ description = "Move window to group on bottom" }
)

-- Navigate a single set of grouped windows
hl.bind(mainMod .. " + ALT + TAB", hl.dsp.group.next(), { description = "Next window in group" })
hl.bind(mainMod .. " + ALT + SHIFT + TAB", hl.dsp.group.prev(), { description = "Previous window in group" })

hl.bind(mainMod .. " + CTRL + LEFT", hl.dsp.group.prev(), { description = "Move grouped window focus left" })
hl.bind(mainMod .. " + CTRL + RIGHT", hl.dsp.group.next(), { description = "Move grouped window focus right" })
