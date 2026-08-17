extends Node
## Boots the real game and saves screenshots, so rendering can be checked from
## a terminal. Headless tests never touch the GPU path, and the three worst bugs
## this project has had were all invisible to them: a HUD laid out at zero size,
## a water surface facing the wrong way, and a web build whose entire 3D pass
## silently stopped drawing.
##
## Run (software GL, no display needed):
##   xvfb-run -a -s "-screen 0 1280x720x24" \
##     env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
##     godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##       res://tests/screenshot.tscn
##
## Images land in the user data dir, which is printed on exit. Swap
## --rendering-driver opengl3 (Compatibility, what the browser runs) for
## vulkan/forward_plus to check the desktop renderer instead.
##
## Rendering under llvmpipe is roughly 3 fps, so each shot takes a few seconds.
## That is normal; it is not a hang. A real hang is almost always an error
## thrown inside _ready(), which aborts this coroutine before quit() is reached.

## Heights are measured from the GROUND under each subject, never from y=0.
## Camp stands on a levelled bench part way up the valley side and the creek bed
## is metres below that, so absolute heights frame one of them underground.
const SHOTS := [
	{"name": "camp", "at": Vector3(-11.0, 2.6, 13.0), "look": Vector3(0.0, 1.2, 0.0),
		"from": "camp"},
	{"name": "creek", "at": Vector3(-8.0, 2.0, 7.0), "look": Vector3(1.0, 0.0, -14.0),
		"from": "creek"},
]

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 8:
		await get_tree().process_frame
	main.ui.notebook.close_panel()

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true

	for shot in SHOTS:
		var at: Vector3 = shot["at"]
		var look: Vector3 = shot["look"]
		match shot.get("from", ""):
			"creek":
				# Measured from the creek's centre line, which meanders, so the
				# framing survives any change to the channel's course.
				var z: float = -50.0
				var cx: float = main.world.creek_x(z)
				var surface: float = main.world._bed_level(cx, z)
				at = Vector3(cx + at.x, surface + at.y, z + at.z)
				look = Vector3(cx + look.x, surface + look.y, z + look.z)
			"camp":
				var ground: float = EnvironmentSystem.height_at(0.0, 0.0)
				at = Vector3(at.x, ground + at.y, at.z)
				look = Vector3(look.x, ground + look.y, look.z)
		cam.global_position = at
		cam.look_at(look, Vector3.UP)
		for i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "user://shot_%s.png" % shot["name"]
		get_viewport().get_texture().get_image().save_png(path)
		print("[shot] %s -> %s" % [shot["name"], ProjectSettings.globalize_path(path)])

	print("[shot] driver=%s" % RenderingServer.get_video_adapter_name())
	get_tree().quit()
