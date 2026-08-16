extends Node
## Boots the real game scene headless and checks that the world actually works:
## terrain answers gameplay queries, animals exist and have been leaving sign,
## and the investigation started.
##
## Run:  godot --headless --path . res://tests/smoke_test.tscn

var _passed := 0
var _failed := 0

func _ready() -> void:
	print("\n=== Hudson Wildlife — smoke test ===\n")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	# Let a couple of seconds of real simulation run on top of the fast-forward.
	for i in 120:
		await get_tree().process_frame

	_check("terrain registered itself as the environment provider",
		EnvironmentSystem.has_provider())
	_check("ground height varies across the map",
		absf(EnvironmentSystem.height_at(0, 0) - EnvironmentSystem.height_at(40, 80)) > 1.0)
	var creek_point := Vector3(main.world.creek_x(-20.0), 0.0, -20.0)
	_check("the creek bed is mud",
		EnvironmentSystem.substrate_at(creek_point).kind == Substrate.Kind.MUD)
	_check("camp is not pitched in the creek",
		EnvironmentSystem.substrate_at(Vector3.ZERO).kind != Substrate.Kind.MUD)
	_check("camp sits on level ground",
		absf(EnvironmentSystem.height_at(-4.0, 3.0)
			- EnvironmentSystem.height_at(4.0, -3.0)) < 0.35)

	# --- There is water in the creek, and it can be seen ---------------------
	# Two independent things have to hold, and only the first is obvious.
	#
	# 1. The surface must stand above the bed across its whole width. The bed
	#    used to be carved by a term half the size of the terrain noise, so the
	#    real low point wandered metres off the centre line and the water sat
	#    above ground on one bank and under it on the other.
	# 2. The surface must FACE UP. Godot's front face is the clockwise winding,
	#    and the first version wound the other way: the mesh was in the scene
	#    with a correct AABB and never drew a pixel from any angle a player can
	#    stand at. Geometry checks all passed while the creek was bone dry.
	var creek: MeshInstance3D = main.world.get_node_or_null("Creek")
	_check("the creek has a water surface", creek != null and creek.mesh != null)

	var submerged := 0
	var stations := 0
	for wz in [-80.0, -50.0, -18.0, 10.0, 30.0, 70.0]:
		var wcx: float = main.world.creek_x(wz)
		var surface: float = main.world._bed_level(wcx, wz)
		for off in [-3.5, -2.0, 0.0, 2.0, 3.5]:
			stations += 1
			if EnvironmentSystem.height_at(wcx + off, wz) < surface:
				submerged += 1
	_check("the bed lies under the water across the channel (%d/%d)"
		% [submerged, stations], submerged == stations)

	_check("the water surface faces the same way as the ground it sits in",
		creek != null and _mean_normal_y(creek.mesh)
			* _mean_normal_y(main.world.get_node("TerrainMesh").mesh) > 0.0)

	var animals := get_tree().get_nodes_in_group(&"animal")
	_check("three animals were placed", animals.size() == 3)

	var records := EvidenceSystem.all_records()
	_check("animals left sign behind them (%d records)" % records.size(), records.size() > 50)

	var species_seen := {}
	var kinds_seen := {}
	for r in records:
		species_seen[r.source_species_id] = true
		kinds_seen[r.kind] = true
	_check("both species left sign — the false leads are real",
		species_seen.has(&"canada_lynx") and species_seen.has(&"bobcat"))
	_check("more than one kind of sign was produced", kinds_seen.size() > 1)

	var aged := 0
	for r in records:
		if r.age_hours() > 0.1:
			aged += 1
	_check("sign carries an age gradient, so travel direction is readable", aged > 10)

	_check("the investigation started", InvestigationSystem.active != null)

	# --- HUD occupies the screen --------------------------------------------
	# Regression: the HUD Control sat at zero size under its CanvasLayer, so
	# everything anchored to the screen centre was laid out around the origin.
	# The crosshair went off-screen, the field notes drew above the top edge,
	# and the camera viewfinder appeared as a stray white box in the corner.
	var viewport_size := get_viewport().get_visible_rect().size
	var hud: HUD = main.ui.hud
	_check("the HUD fills the viewport (%s vs %s)" % [hud.size, viewport_size],
		hud.size.x >= viewport_size.x - 1.0 and hud.size.y >= viewport_size.y - 1.0)

	main.player.camera_mode = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check("raising the camera hides the crosshair", not hud._crosshair.visible)
	_check("the viewfinder is on screen, not in the corner",
		hud._viewfinder.size.x >= viewport_size.x - 1.0)
	# --- The camera actually photographs an animal --------------------------
	# The player has to be able to complete the loop, not just see a viewfinder.
	var animals2 := get_tree().get_nodes_in_group(&"animal")
	if not animals2.is_empty():
		# Bring the animal to open ground in front of the player rather than
		# chasing it across the map: a live animal keeps walking, and a tree or
		# a rise between the two makes this test flap for reasons that have
		# nothing to do with the camera.
		var target: AnimalController = animals2[0]
		target.set_physics_process(false)
		var player: PlayerController = main.player
		player.rotation.y = 0.0
		var cam: Camera3D = player.get_node("EyeCamera")
		cam.rotation.x = 0.0
		var spot := player.global_position + Vector3(0.0, 0.0, -6.0)   # -Z is forward
		target.global_position = Vector3(
			spot.x, EnvironmentSystem.height_at(spot.x, spot.z) + 0.2, spot.z)
		for i in 4:
			await get_tree().process_frame
		_check("the raised camera sees an animal in front of it",
			not player._best_subject_in_frame().is_empty())

		var before := FieldNotebook.entries.size()
		main.player.take_photograph()
		await get_tree().process_frame
		var photos := FieldNotebook.entries_of_kind(EvidenceKind.Type.PHOTOGRAPH)
		_check("the shutter files a photograph in the notebook",
			FieldNotebook.entries.size() > before and not photos.is_empty())
		if not photos.is_empty():
			_check("a clear close shot is worth something (%d%%)"
				% int(photos[0].effective_quality() * 100.0),
				photos[0].effective_quality() > 0.0)

		# The rare-animal objective must not be satisfiable by the common one.
		var lynx_photo := false
		for r in FieldNotebook.entries_of_kind(EvidenceKind.Type.PHOTOGRAPH):
			if r.source_species_id == &"canada_lynx" and r.effective_quality() >= 0.45:
				lynx_photo = true
		var obj_done: bool = InvestigationSystem.objective_index > 2
		_check("photographing the wrong cat does not finish the rare-animal objective",
			lynx_photo or not obj_done)

	main.player.camera_mode = false

	# Each species draws a different print.
	var lynx_mesh := PlaceholderFactory.track_mesh_for_profile(
		SpeciesDB.get_species(&"canada_lynx").track)
	var bobcat_mesh := PlaceholderFactory.track_mesh_for_profile(
		SpeciesDB.get_species(&"bobcat").track)
	_check("lynx and bobcat prints are different shapes",
		lynx_mesh.get_faces().size() != bobcat_mesh.get_faces().size()
			or lynx_mesh.get_aabb().size != bobcat_mesh.get_aabb().size)

	# --- GPU budget ---------------------------------------------------------
	# Browsers give up where the desktop shrugs, and they do it silently: the
	# whole 3D pass stops drawing with no error. Three separate times this
	# killed the web build — a material per track, then a mesh per tree part,
	# then simply too many MeshInstance3D nodes (~1200 was fatal, 2015 was
	# fine on desktop).
	#
	# Draw calls are the metric that actually bit. Anything numerous belongs in
	# a MultiMesh, with its variation in instance transforms and colours.
	var meshes := {}
	var materials := {}
	var instances := [0]
	_count_gpu_resources(main, meshes, materials, instances)
	_check("mesh instances stay bounded (%d draw calls)" % instances[0], instances[0] <= 400)
	_check("unique meshes stay bounded (%d)" % meshes.size(), meshes.size() <= 150)
	_check("unique materials stay bounded (%d)" % materials.size(), materials.size() <= 60)

	# --- The notebook must always be closable -------------------------------
	# Regression: Tab is also Godot's ui_focus_next. Once a tab button had
	# focus it swallowed Tab, the notebook could not be closed, and because
	# movement was disabled behind it the player was soft-locked.
	var notebook: NotebookUI = main.ui.notebook
	_check("the notebook opens on the briefing", notebook.visible)
	_check("the player cannot walk while reading", main.player._ui_modal_open)

	var button := _find_button(notebook)
	_check("the notebook has a visible way out", button != null)
	if button != null:
		button.grab_focus()
		await get_tree().process_frame

	var tab_key := InputEventKey.new()
	tab_key.physical_keycode = KEY_TAB
	tab_key.pressed = true
	Input.parse_input_event(tab_key)
	await get_tree().process_frame
	await get_tree().process_frame

	_check("Tab closes the notebook even with a button focused", not notebook.visible)
	_check("the player can walk again once it is closed", not main.player._ui_modal_open)
	_check("no sign has been discovered before the player looks for it",
		EvidenceSystem.discovered_records().is_empty()
			or Settings.tracking_assist != Settings.TrackingAssist.OFF)

	print("\n%d passed, %d failed\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

## Average Y of a surface's vertex normals. generate_normals() derives them from
## the triangle winding, so this reports which way the faces point — comparing
## the creek against the ground catches a flipped surface without needing to
## know Godot's winding convention by heart.
func _mean_normal_y(mesh: Mesh) -> float:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0.0
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	if normals.is_empty():
		return 0.0
	var total := 0.0
	for n in normals:
		total += n.y
	return total / float(normals.size())

func _count_gpu_resources(node: Node, meshes: Dictionary, materials: Dictionary,
		instances: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		meshes[node.mesh.get_instance_id()] = true
		instances[0] += 1          # one draw call each — this is the costly one
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		meshes[node.multimesh.mesh.get_instance_id()] = true
		instances[0] += 1          # one draw call for every instance it holds
	if node is GeometryInstance3D and node.material_override != null:
		materials[node.material_override.get_instance_id()] = true
	for child in node.get_children():
		_count_gpu_resources(child, meshes, materials, instances)

func _find_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var found := _find_button(child)
		if found != null:
			return found
	return null

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
