class_name CampBuilder
extends RefCounted
## The research camp: a wall tent, a field table with the notebook open on it,
## and a fire ring.
##
## Pure presentation. Camp is where the investigation starts and ends, so it has
## to read as somewhere a person actually works — but nothing here is gameplay.
## The "return to camp" objective is a coordinate and a radius; it does not know
## a tent exists.
##
## Everything is placed against EnvironmentSystem.height_at(), so the camp sits
## on the ground whatever the terrain does, and materials are shared per
## material — never one per object.

const FIRE_STONES := 9

static var _mats: Dictionary = {}

static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D
	match key:
		"canvas":     m = PlaceholderFactory.material(Color(0.38, 0.35, 0.28))
		"canvas_dark":m = PlaceholderFactory.material(Color(0.16, 0.14, 0.11))
		"wood":       m = PlaceholderFactory.material(Color(0.40, 0.29, 0.18))
		"wood_pale":  m = PlaceholderFactory.material(Color(0.46, 0.36, 0.23))
		"char":       m = PlaceholderFactory.material(Color(0.10, 0.09, 0.08))
		"stone":      m = PlaceholderFactory.material(Color(0.30, 0.28, 0.25))
		"ash":        m = PlaceholderFactory.material(Color(0.29, 0.27, 0.245))
		"paper":      m = PlaceholderFactory.material(Color(0.88, 0.86, 0.78))
		"metal":      m = PlaceholderFactory.material(Color(0.34, 0.35, 0.36), 0.4)
		"ember":      m = PlaceholderFactory.material(Color(0.95, 0.42, 0.12))
		_:            m = PlaceholderFactory.material(Color(0.6, 0.6, 0.6))
	if key == "ember":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m

## Ground height at a camp-local offset, so nothing floats or sinks.
static func _ground(origin: Vector3, offset: Vector3) -> Vector3:
	var x := origin.x + offset.x
	var z := origin.z + offset.z
	return Vector3(x, EnvironmentSystem.height_at(x, z) + offset.y, z)

static func _put(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot := Vector3.ZERO, scale_ := Vector3.ONE) -> MeshInstance3D:
	var mi := PlaceholderFactory.mesh_node(mesh, mat, pos)
	mi.rotation = rot
	mi.scale = scale_
	parent.add_child(mi)
	return mi

static func build(parent: Node3D, origin: Vector3) -> Node3D:
	var camp := Node3D.new()
	camp.name = "ResearchCamp"
	parent.add_child(camp)

	var rng := RandomNumberGenerator.new()
	rng.seed = 606

	_build_tent(camp, origin, Vector3(4.6, 0.0, -2.2), -1.12)
	_build_fire(camp, origin, Vector3.ZERO, rng)
	_build_table(camp, origin, Vector3(-3.9, 0.0, 0.8), 0.5)
	_build_seating(camp, origin, rng)
	_build_marker(camp, origin, Vector3(1.6, 0.0, -6.5))
	return camp

# --- Tent -----------------------------------------------------------------

## A canvas wall tent: ridge roof, a dark doorway, a ridge pole out both ends,
## and guy lines to pegs. The doorway faces the fire.
static func _build_tent(camp: Node3D, origin: Vector3, at: Vector3, yaw: float) -> void:
	var base := _ground(origin, at)

	var body := PrismMesh.new()
	body.size = Vector3(2.6, 1.75, 3.2)
	_put(camp, body, _mat("canvas"), base + Vector3(0, 0.875, 0), Vector3(0, yaw, 0))

	# Doorway: a dark panel set just proud of the front face.
	var door := PrismMesh.new()
	door.size = Vector3(1.0, 1.15, 0.06)
	var forward: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	_put(camp, door, _mat("canvas_dark"),
		base + Vector3(0, 0.575, 0) + forward * 1.62, Vector3(0, yaw, 0))

	# Ridge pole, protruding at both ends the way a real one does.
	var pole := CylinderMesh.new()
	pole.top_radius = 0.045
	pole.bottom_radius = 0.045
	pole.height = 3.9
	_put(camp, pole, _mat("wood_pale"), base + Vector3(0, 1.78, 0),
		Vector3(PI * 0.5, yaw, 0))

	# Guy lines out to pegs.
	var line := CylinderMesh.new()
	line.top_radius = 0.012
	line.bottom_radius = 0.012
	line.height = 1.0
	line.radial_segments = 4
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var anchor: Vector3 = base + Vector3(0, 1.7, 0) + forward * (end * 1.75)
			var peg_local := Vector3(side * 1.5, 0.0, end * 2.5).rotated(Vector3.UP, yaw)
			var peg := _ground(origin, at + peg_local)
			var mid: Vector3 = (anchor + peg) * 0.5
			var span: Vector3 = peg - anchor
			var mi := PlaceholderFactory.mesh_node(line, _mat("wood_pale"), mid)
			camp.add_child(mi)
			# Aim first, THEN stretch. look_at rewrites the whole basis, so a
			# scale set beforehand is silently thrown away — which left the guy
			# lines one metre long and floating clear of the tent.
			mi.look_at_from_position(mid, mid + span, Vector3.UP)
			mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			mi.scale = Vector3(1.0, span.length(), 1.0)

# --- Fire -----------------------------------------------------------------

## Stone ring, ash bed, burnt log ends, and a tripod with a pot over it. The
## embers only glow when the light is low, which is the clock system doing its
## job without the fire knowing the clock exists.
static func _build_fire(camp: Node3D, origin: Vector3, at: Vector3,
		rng: RandomNumberGenerator) -> void:
	var base := _ground(origin, at)

	var ash := CylinderMesh.new()
	ash.top_radius = 0.52
	ash.bottom_radius = 0.58
	ash.height = 0.07
	ash.radial_segments = 12
	_put(camp, ash, _mat("ash"), base + Vector3(0, 0.035, 0))

	var stone := SphereMesh.new()
	stone.radius = 1.0
	stone.height = 1.5
	stone.radial_segments = 6
	stone.rings = 3
	for i in FIRE_STONES:
		var a := TAU * float(i) / float(FIRE_STONES) + rng.randf_range(-0.1, 0.1)
		var r := 0.68 + rng.randf_range(-0.04, 0.04)
		var s := rng.randf_range(0.10, 0.17)
		var p := _ground(origin, at + Vector3(cos(a) * r, 0.0, sin(a) * r))
		_put(camp, stone, _mat("stone"), p + Vector3(0, s * 0.45, 0),
			Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)),
			Vector3(s, s * 0.75, s * rng.randf_range(0.8, 1.2)))

	# Half-burnt logs, laid across each other rather than stacked neatly.
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = 0.06
	log_mesh.bottom_radius = 0.075
	log_mesh.height = 0.85
	log_mesh.radial_segments = 6
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		_put(camp, log_mesh, _mat("char"),
			base + Vector3(cos(a) * 0.1, 0.12, sin(a) * 0.1),
			Vector3(PI * 0.5 + rng.randf_range(-0.12, 0.12), a, 0.0))

	# Embers, and a light that only matters at dusk.
	var ember := SphereMesh.new()
	ember.radius = 0.16
	ember.height = 0.1
	ember.radial_segments = 6
	ember.rings = 3
	_put(camp, ember, _mat("ember"), base + Vector3(0, 0.08, 0))

	var glow := OmniLight3D.new()
	glow.name = "EmberGlow"
	glow.position = base + Vector3(0, 0.35, 0)
	glow.light_color = Color(1.0, 0.62, 0.28)
	glow.omni_range = 7.0
	glow.light_energy = 0.0
	camp.add_child(glow)
	# Presentation listening to the clock; the clock knows nothing about fires.
	EventBus.time_changed.connect(func(_d, _h):
		glow.light_energy = lerpf(2.2, 0.0, clampf(GameClock.light_level() * 1.6, 0.0, 1.0)))

	# Tripod over the fire with a pot hanging from it.
	var stick := CylinderMesh.new()
	stick.top_radius = 0.018
	stick.bottom_radius = 0.028
	stick.height = 1.15
	stick.radial_segments = 5
	for i in 3:
		var a := TAU * float(i) / 3.0
		# Lean each leg outward: tilt about the axis at right angles to the
		# direction it leans. Euler angles get this subtly wrong.
		var mi := _put(camp, stick, _mat("wood_pale"),
			base + Vector3(cos(a) * 0.24, 0.55, sin(a) * 0.24))
		mi.basis = Basis(Vector3(-sin(a), 0.0, cos(a)), 0.34)
	var pot := CylinderMesh.new()
	pot.top_radius = 0.13
	pot.bottom_radius = 0.11
	pot.height = 0.2
	pot.radial_segments = 8
	_put(camp, pot, _mat("metal"), base + Vector3(0, 0.48, 0))

# --- Field table ----------------------------------------------------------

## The table the notebook lives on: the investigation's desk. Notebook open,
## pencil across it, a specimen jar and a lantern.
static func _build_table(camp: Node3D, origin: Vector3, at: Vector3, yaw: float) -> void:
	var base := _ground(origin, at)
	var top_y := 0.78

	var top := BoxMesh.new()
	top.size = Vector3(1.5, 0.05, 0.85)
	_put(camp, top, _mat("wood_pale"), base + Vector3(0, top_y, 0), Vector3(0, yaw, 0))

	var leg := CylinderMesh.new()
	leg.top_radius = 0.035
	leg.bottom_radius = 0.04
	leg.height = top_y
	leg.radial_segments = 5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var off := Vector3(sx * 0.66, 0.0, sz * 0.34).rotated(Vector3.UP, yaw)
			_put(camp, leg, _mat("wood"), _ground(origin, at + off) + Vector3(0, top_y * 0.5, 0))

	var surface := base + Vector3(0, top_y + 0.03, 0)

	# The notebook, open, with two leaves tilted up off the spine.
	var leaf := BoxMesh.new()
	leaf.size = Vector3(0.21, 0.008, 0.28)
	for side in [-1.0, 1.0]:
		var off := Vector3(side * 0.108, 0.0, 0.0).rotated(Vector3.UP, yaw)
		_put(camp, leaf, _mat("paper"), surface + off + Vector3(0, 0.012, 0),
			Vector3(0, yaw, side * -0.06))
	var cover := BoxMesh.new()
	cover.size = Vector3(0.44, 0.012, 0.3)
	_put(camp, cover, _mat("canvas_dark"), surface, Vector3(0, yaw, 0))

	var pencil := CylinderMesh.new()
	pencil.top_radius = 0.005
	pencil.bottom_radius = 0.006
	pencil.height = 0.17
	pencil.radial_segments = 5
	_put(camp, pencil, _mat("wood"), surface + Vector3(0.02, 0.022, 0.16),
		Vector3(PI * 0.5, yaw + 0.5, 0))

	# Specimen jar: something collected is waiting to be written up.
	var jar := CylinderMesh.new()
	jar.top_radius = 0.045
	jar.bottom_radius = 0.05
	jar.height = 0.13
	jar.radial_segments = 8
	var jar_off := Vector3(0.52, 0.0, -0.16).rotated(Vector3.UP, yaw)
	_put(camp, jar, _mat("metal"), surface + jar_off + Vector3(0, 0.065, 0))

	# Lantern, hooded, on the far corner.
	var lantern_off := Vector3(-0.55, 0.0, -0.2).rotated(Vector3.UP, yaw)
	var lantern_base := surface + lantern_off
	var body := BoxMesh.new()
	body.size = Vector3(0.12, 0.17, 0.12)
	_put(camp, body, _mat("metal"), lantern_base + Vector3(0, 0.085, 0), Vector3(0, yaw, 0))
	var flame := BoxMesh.new()
	flame.size = Vector3(0.07, 0.09, 0.07)
	_put(camp, flame, _mat("ember"), lantern_base + Vector3(0, 0.085, 0), Vector3(0, yaw, 0))

# --- Seating --------------------------------------------------------------

static func _build_seating(camp: Node3D, origin: Vector3, rng: RandomNumberGenerator) -> void:
	var seat := CylinderMesh.new()
	seat.top_radius = 0.19
	seat.bottom_radius = 0.21
	seat.height = 1.5
	seat.radial_segments = 7
	for a in [2.3, 5.1]:
		var off := Vector3(cos(a) * 1.7, 0.0, sin(a) * 1.7)
		var p := _ground(origin, off)
		_put(camp, seat, _mat("wood"), p + Vector3(0, 0.19, 0),
			Vector3(PI * 0.5, a + rng.randf_range(-0.3, 0.3), 0.0))

# --- Navigation marker ----------------------------------------------------

## Tall and orange on purpose: you have to be able to find camp again from the
## ridge, and the game should not need a compass arrow to make that possible.
static func _build_marker(camp: Node3D, origin: Vector3, at: Vector3) -> void:
	var base := _ground(origin, at)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.07
	pole.height = 6.0
	pole.radial_segments = 6
	_put(camp, pole, _mat("wood_pale"), base + Vector3(0, 3.0, 0))

	var flag := BoxMesh.new()
	flag.size = Vector3(0.5, 0.34, 0.02)
	_put(camp, flag, PlaceholderFactory.material(Color(0.85, 0.35, 0.18)),
		base + Vector3(0.27, 5.6, 0))
