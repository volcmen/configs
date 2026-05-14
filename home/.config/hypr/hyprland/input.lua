----------------
---- INPUT ----
----------------

-- https://wiki.hypr.land/Configuring/Variables/#input
hl.config({
	input = {
		kb_layout = "us,ru",
		kb_variant = "",
		kb_model = "",
		kb_options = "",
		kb_rules = "",

		repeat_rate = 50,
		repeat_delay = 200,
		follow_mouse = 1,
		sensitivity = 0,

		touchpad = {
			natural_scroll = false,
		},
	},
})

-- https://wiki.hypr.land/Configuring/Gestures
hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})
