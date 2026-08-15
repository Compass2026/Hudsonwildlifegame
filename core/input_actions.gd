class_name InputActions
extends RefCounted
## Registers the input map in code so project.godot stays diff-friendly.
## Call InputActions.ensure() once at startup; it is idempotent.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_slow": [KEY_SHIFT],
	"crouch": [KEY_C],
	"interact": [KEY_E],
	"toggle_camera": [KEY_F],
	"toggle_notebook": [KEY_TAB],
	"toggle_mouse": [KEY_ESCAPE],
}

const MOUSE_ACTIONS := {
	"shutter": MOUSE_BUTTON_LEFT,
	"zoom_in": MOUSE_BUTTON_WHEEL_UP,
	"zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
}

static func ensure() -> void:
	for action_name in ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode in ACTIONS[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action_name, ev)

	for action_name in MOUSE_ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_ACTIONS[action_name]
		InputMap.action_add_event(action_name, ev)
