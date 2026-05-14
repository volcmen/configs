local shared = {}

local function shell_quote(command)
	return "'" .. command:gsub("'", "'\\''") .. "'"
end

local function uwsm_cmd(options, command)
	local option_prefix = options and options ~= "" and " " .. options or ""

	return "uwsm-app" .. option_prefix .. " -- " .. command
end

shared.modifiers = {
	main = "SUPER",
	hyper = "SUPER + CTRL + ALT + SHIFT",
}

shared.apps = {
	terminal = "kitty",
	file_manager = "yazi",
	menu = "fuzzel",
	browser = "zen-browser",
}

shared.apps.launcher = shared.apps.menu .. " --launch-prefix='uwsm-app -- '"

shared.commands = {
	file_manager = {
		open = shared.apps.terminal .. " -- " .. shared.apps.file_manager,
	},

		language = {
			switch_next = "hyprctl --quiet switchxkblayout all next",
		},

		media = {
			volume_up = "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+",
			volume_down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-",
			toggle_mute = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
			toggle_mic_mute = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
			next = "playerctl next",
			play_pause = "playerctl play-pause",
			previous = "playerctl previous",
		},

		clipboard = {
			manager = "cliphist list | " .. shared.apps.menu .. " --dmenu --with-nth 2 | cliphist decode | wl-copy",
		},

		screenshot = {
			snip = table.concat({
			'screenshots_dir="${XDG_SCREENSHOTS_DIR:-$HOME/Pictures/Screenshots}"',
			'mkdir -p "$screenshots_dir" || exit 1',
			'geometry="$(slurp)" || exit 0',
			'[ -n "$geometry" ] || exit 0',
			'file="$screenshots_dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"',
			'grim -g "$geometry" "$file" && wl-copy --type image/png < "$file"',
		}, "; "),
	},

	voice = {
		toggle = 'uv run --directory "$HOME/Development/tools/record-whisper" --project "$HOME/Development/tools/record-whisper" --frozen main.py toggle',
	},
}

shared.uwsm = {}

function shared.uwsm.app(command)
	return uwsm_cmd("", command)
end

function shared.uwsm.background(command)
	return uwsm_cmd("-s b", command)
end

function shared.uwsm.shell(command)
	return shared.uwsm.app("sh -c " .. shell_quote(command))
end

return shared
