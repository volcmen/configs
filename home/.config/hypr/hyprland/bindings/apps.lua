local shared = require("hyprland/shared")

local apps = shared.apps
local commands = shared.commands
local mainMod = shared.modifiers.main
local hyperMod = shared.modifiers.hyper
local uwsm = shared.uwsm

hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(uwsm.app(apps.launcher)))
hl.bind(hyperMod .. " + T", hl.dsp.exec_cmd(uwsm.app(apps.terminal)))
hl.bind(hyperMod .. " + F", hl.dsp.exec_cmd(uwsm.app(commands.file_manager.open)))
hl.bind(hyperMod .. " + B", hl.dsp.exec_cmd(uwsm.app(apps.browser)))

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + ALT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(hyperMod .. " + Space", hl.dsp.exec_cmd(commands.language.switch_next), {
	description = "Change language",
	locked = true,
})

hl.bind(
	mainMod .. " + SHIFT + S",
	hl.dsp.exec_cmd(uwsm.shell(commands.screenshot.snip)),
	{ description = "Screen snip" }
)

hl.bind(
	mainMod .. " + ALT + D",
	hl.dsp.exec_cmd(uwsm.shell(commands.voice.toggle)),
	{ description = "Toggle Voice record and transcribe to text" }
)
