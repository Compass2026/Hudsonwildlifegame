class_name PrototypeValley
extends Node3D
## The first map: a small headwater drainage with a research camp at its mouth.
##
## Two jobs, kept apart on purpose:
##   1. Build visuals (mesh, trees, sky). Throwaway — replace with a sculpted
##      terrain, real trees and a real skybox whenever you like.
##   2. Answer gameplay's questions about the ground, by implementing the
##      EnvironmentSystem provider interface: height_at / substrate_at /
##      world_extent.
##
## Because gameplay only ever calls job 2, all of job 1 can be thrown away.

const EXTENT := 110.0        ## half-width of the playable area, metres
const CELL := 2.0            ## terrain mesh resolution
const CAMP_RADIUS := 14.0
const TREE_COUNT := 300
const SHRUB_COUNT := 1500
const ROCK_COUNT := 260

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _sun: DirectionalLight3D

func _ready() -> void:
	_noise.seed = 20260815
	_noise.frequency = 0.006
	_noise.fractal_octaves = 4
	_detail.seed = 991
	_detail.frequency = 0.05

	EnvironmentSystem.register_provider(self)

	_build_terrain()
	_build_water()
	_build_trees()
	_build_ground_cover()
	_build_camp()
	_build_sky()

	EventBus.time_changed.connect(_on_time_changed)
	_on_time_changed(GameClock.day, GameClock.hour)

# --- Provider interface (this is what gameplay depends on) ----------------

func world_extent() -> float:
	return EXTENT

## Analytic ground height. Gameplay asks this; it never touches the mesh.
func height_at(x: float, z: float) -> float:
	var rolling := _noise.get_noise_2d(x, z) * 14.0
	var slope := (z + EXTENT) / (EXTENT * 2.0) * 10.0   ## valley climbs to the north
	var d := absf(x - creek_x(z))
	var carve := clampf(1.0 - d / 16.0, 0.0, 1.0)
	return rolling + slope - carve * carve * 7.0

## The drainage meanders; following it is the point.
func creek_x(z: float) -> float:
	return sin(z * 0.028) * 26.0 + sin(z * 0.011) * 12.0

func creek_distance(pos: Vector3) -> float:
	return absf(pos.x - creek_x(pos.z))

func substrate_at(pos: Vector3) -> Substrate:
	var d := creek_distance(pos)
	if d < 5.0:
		return Substrate.make(Substrate.Kind.MUD)
	if d < 9.0:
		return Substrate.make(Substrate.Kind.SAND)

	# Steep or high ground is ledge; nothing registers there.
	var h := height_at(pos.x, pos.z)
	var slope := absf(h - height_at(pos.x + 2.0, pos.z)) + absf(h - height_at(pos.x, pos.z + 2.0))
	if slope > 2.6 or h > 16.0:
		return Substrate.make(Substrate.Kind.ROCK)

	if _detail.get_noise_2d(pos.x, pos.z) > 0.18:
		return Substrate.make(Substrate.Kind.DUFF)
	return Substrate.make(Substrate.Kind.LEAF_LITTER)

# --- Visuals (all replaceable) -------------------------------------------

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := int(EXTENT * 2.0 / CELL)
	for iz in range(steps):
		for ix in range(steps):
			var x0 := -EXTENT + float(ix) * CELL
			var z0 := -EXTENT + float(iz) * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			var p00 := Vector3(x0, height_at(x0, z0), z0)
			var p10 := Vector3(x1, height_at(x1, z0), z0)
			var p11 := Vector3(x1, height_at(x1, z1), z1)
			var p01 := Vector3(x0, height_at(x0, z1), z1)
			# Tint the ground by what it is made of, so the player can read the
			# terrain by eye: the mud line along the creek is where prints hold.
			var c00 := _ground_color(p00)
			var c10 := _ground_color(p10)
			var c11 := _ground_color(p11)
			var c01 := _ground_color(p01)
			for pair in [[p00, c00], [p10, c10], [p11, c11],
					[p00, c00], [p11, c11], [p01, c01]]:
				st.set_color(pair[1])
				st.set_uv(Vector2(pair[0].x, pair[0].z) * 0.08)
				st.add_vertex(pair[0])
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "TerrainMesh"
	mi.mesh = mesh
	var terrain_mat := PlaceholderFactory.material(Color.WHITE)
	terrain_mat.vertex_color_use_as_albedo = true
	mi.material_override = terrain_mat
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)

## Substrate decides the base colour; a little noise keeps it from reading as
## flat paint. Gameplay reads the substrate, never the colour.
func _ground_color(p: Vector3) -> Color:
	var base := PlaceholderFactory.substrate_color(substrate_at(p).kind)
	# Vary BRIGHTNESS, and blend toward a dark moss only as a weighted mix.
	# Adding to the green channel directly flipped the hue from forest-floor
	# brown to lawn green, which is why the valley looked like a golf course.
	var v := 1.0 + _detail.get_noise_2d(p.x * 3.0, p.z * 3.0) * 0.22
	var shaded := Color(base.r * v, base.g * v, base.b * v)
	var mossy := maxf(0.0, _noise.get_noise_2d(p.x * 4.0, p.z * 4.0)) * 0.16
	return shaded.lerp(Color(0.16, 0.19, 0.09), mossy)

func _build_water() -> void:
	# A thin ribbon following the creek, purely visual. It marks the mud.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := -EXTENT
	while z < EXTENT - 2.0:
		var z2 := z + 2.0
		var xa := creek_x(z)
		var xb := creek_x(z2)
		var ya := height_at(xa, z) + 0.15
		var yb := height_at(xb, z2) + 0.15
		var quad := [
			Vector3(xa - 1.6, ya, z), Vector3(xa + 1.6, ya, z),
			Vector3(xb + 1.6, yb, z2), Vector3(xb - 1.6, yb, z2)]
		for p in [quad[0], quad[2], quad[1], quad[0], quad[3], quad[2]]:
			st.add_vertex(p)
		z = z2
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Creek"
	mi.mesh = st.commit()
	var mat := PlaceholderFactory.material(Color(0.20, 0.32, 0.36, 0.75), 0.15)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.4
	mi.material_override = mat
	add_child(mi)

## Both the materials AND the meshes are built once and shared by every tree.
##
## This is the rule the browser enforces and the desktop does not: a GPU
## resource per object does not scale. Minting a material per track killed 3D
## rendering outright; minting four meshes per tree did it again at 300 trees.
## Variation comes from node scale and from picking out of a small pool, never
## from a fresh resource per instance.
var _trunk_colors: Array[Color] = []
var _canopy_colors: Array[Color] = []
var _trunk_meshes: Array[Mesh] = []
var _skirt_meshes: Array[Mesh] = []
var _crown_meshes: Array[Mesh] = []

func _build_tree_resources() -> void:
	# Tints, not materials: colour rides on the MultiMesh instance data.
	_trunk_colors = [Color(0.26, 0.20, 0.15), Color(0.20, 0.16, 0.12), Color(0.33, 0.28, 0.23)]
	_canopy_colors = [Color(0.10, 0.18, 0.11), Color(0.07, 0.14, 0.09), Color(0.14, 0.22, 0.12),
			Color(0.19, 0.24, 0.11), Color(0.23, 0.26, 0.13)]

	# Unit-sized meshes: one metre tall, one metre across. Every tree scales
	# these to the size it wants.
	for i in 3:
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.55
		trunk.bottom_radius = 1.0
		trunk.height = 1.0
		trunk.radial_segments = 6 + i
		_trunk_meshes.append(trunk)

		var skirt := CylinderMesh.new()
		skirt.top_radius = 0.0
		skirt.bottom_radius = 1.0
		skirt.height = 1.0
		skirt.radial_segments = 7 + i * 2
		_skirt_meshes.append(skirt)

		var crown := SphereMesh.new()
		crown.radius = 1.0
		crown.height = 1.6 + float(i) * 0.25
		crown.radial_segments = 7
		crown.rings = 4
		_crown_meshes.append(crown)

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_build_tree_resources()

	var placed := 0
	var attempts := 0
	while placed < TREE_COUNT and attempts < TREE_COUNT * 12:
		attempts += 1
		var x := rng.randf_range(-EXTENT + 4.0, EXTENT - 4.0)
		var z := rng.randf_range(-EXTENT + 4.0, EXTENT - 4.0)
		var pos := Vector3(x, 0, z)
		if pos.length() < CAMP_RADIUS:
			continue
		if creek_distance(pos) < 4.0:
			continue          # keep the drainage walkable and readable
		var h := height_at(x, z)
		if h > 18.0:
			continue          # bare ledge above the treeline
		var density := _noise.get_noise_2d(x * 2.0, z * 2.0)
		if density < -0.25:
			continue          # natural openings
		placed += 1
		# Conifer on the higher, colder ground; mixed hardwood lower down.
		var conifer := h > 6.0 or rng.randf() < 0.55
		_add_tree(Vector3(x, h, z), rng, conifer)

	_commit_tree_multimeshes()

## Trees are accumulated into buckets and drawn as MultiMeshes: nine draw calls
## for the whole forest instead of one per trunk and canopy.
##
## Instance COUNT is what the browser could not take — not triangles, not
## unique resources. Three hundred trees at four mesh instances each put ~1200
## draw calls on screen and WebGL stopped drawing the world entirely, while the
## desktop renderer shrugged and carried on.
var _tree_buckets: Dictionary = {}   ## mesh -> {transforms, colors}
var _tree_collision: StaticBody3D

func _bucket(mesh: Mesh, xform: Transform3D, tint: Color) -> void:
	if not _tree_buckets.has(mesh):
		_tree_buckets[mesh] = {"transforms": [], "colors": []}
	_tree_buckets[mesh]["transforms"].append(xform)
	_tree_buckets[mesh]["colors"].append(tint)

func _add_tree(pos: Vector3, rng: RandomNumberGenerator, conifer: bool) -> void:
	var height := rng.randf_range(8.0, 17.0) if conifer else rng.randf_range(6.0, 11.0)
	var radius := rng.randf_range(0.18, 0.36)
	var yaw := rng.randf() * TAU
	var trunk_tint: Color = _trunk_colors[rng.randi() % _trunk_colors.size()]
	var canopy_tint: Color = _canopy_colors[rng.randi() % _canopy_colors.size()]

	_bucket(_trunk_meshes[rng.randi() % 3],
		Transform3D(Basis.from_euler(Vector3(0, yaw, 0))
			.scaled(Vector3(radius, height, radius)), pos + Vector3.UP * height * 0.5),
		trunk_tint)

	if conifer:
		# Three overlapping skirts instead of one cone on a stick — reads as a
		# spruce rather than a lollipop, and the overlap hides the trunk join.
		var base_r := rng.randf_range(1.7, 2.9)
		for i in 3:
			var t := float(i) / 3.0
			var r := base_r * (1.0 - t * 0.45)
			_bucket(_skirt_meshes[rng.randi() % 3],
				Transform3D(Basis.from_euler(Vector3(0, yaw, 0))
					.scaled(Vector3(r, height * 0.45, r)),
					pos + Vector3.UP * height * (0.30 + t * 0.26)),
				canopy_tint)
	else:
		var crown_r := rng.randf_range(2.0, 3.4)
		for i in 3:
			var r := crown_r * rng.randf_range(0.55, 0.8)
			_bucket(_crown_meshes[rng.randi() % 3],
				Transform3D(Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(r, r, r)),
					pos + Vector3(rng.randf_range(-0.6, 0.6) * crown_r,
						height * rng.randf_range(0.72, 0.95),
						rng.randf_range(-0.6, 0.6) * crown_r)),
				canopy_tint)

	# Collision is physics, not graphics, so it stays per-tree — but all of it
	# hangs off a single body rather than 300 of them.
	if _tree_collision == null:
		_tree_collision = StaticBody3D.new()
		_tree_collision.name = "TreeCollision"
		add_child(_tree_collision)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	shape.position = pos + Vector3.UP * height * 0.5
	_tree_collision.add_child(shape)

func _commit_tree_multimeshes() -> void:
	var mat := PlaceholderFactory.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	var index := 0
	for mesh in _tree_buckets:
		var bucket: Dictionary = _tree_buckets[mesh]
		var transforms: Array = bucket["transforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
			mm.set_instance_color(i, bucket["colors"][i])
		var node := MultiMeshInstance3D.new()
		node.name = "TreeParts%d" % index
		index += 1
		node.multimesh = mm
		node.material_override = mat
		add_child(node)
	_tree_buckets.clear()

## Low cover, drawn as two MultiMeshes — one draw call each, however many there
## are. Deliberately kept off the creek margins: the mud is where prints
## register, and burying it in shrubs would make the ground unreadable.
func _build_ground_cover() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9090

	var shrub := SphereMesh.new()
	shrub.radius = 1.0
	shrub.height = 1.4
	shrub.radial_segments = 6
	shrub.rings = 3
	var shrub_mat := PlaceholderFactory.material(Color.WHITE)
	shrub_mat.vertex_color_use_as_albedo = true
	_scatter_multimesh("Undergrowth", shrub, shrub_mat, SHRUB_COUNT, rng,
		func(p: Vector3, r: RandomNumberGenerator) -> Transform3D:
			var s := r.randf_range(0.22, 0.55)
			return Transform3D(Basis().rotated(Vector3.UP, r.randf() * TAU)
				.scaled(Vector3(s, s * r.randf_range(0.7, 1.1), s)),
				p + Vector3.UP * s * 0.35),
		func(r: RandomNumberGenerator) -> Color:
			return Color(0.11, 0.18, 0.09).lerp(Color(0.21, 0.24, 0.12), r.randf()),
		10.0)

	var rock := BoxMesh.new()
	rock.size = Vector3.ONE
	var rock_mat := PlaceholderFactory.material(Color.WHITE)
	rock_mat.vertex_color_use_as_albedo = true
	_scatter_multimesh("Rocks", rock, rock_mat, ROCK_COUNT, rng,
		func(p: Vector3, r: RandomNumberGenerator) -> Transform3D:
			var s := r.randf_range(0.25, 0.9)
			return Transform3D(Basis.from_euler(Vector3(
				r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(-0.4, 0.4))
				).scaled(Vector3(s, s * 0.7, s * r.randf_range(0.7, 1.3))),
				p - Vector3.UP * s * 0.2),
		func(r: RandomNumberGenerator) -> Color:
			return Color(0.25, 0.25, 0.24).lerp(Color(0.40, 0.39, 0.36), r.randf()),
		6.0)

func _scatter_multimesh(node_name: String, mesh: Mesh, mat: Material, count: int,
		rng: RandomNumberGenerator, place: Callable, tint: Callable,
		creek_clearance: float) -> void:
	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var attempts := 0
	while transforms.size() < count and attempts < count * 10:
		attempts += 1
		var x := rng.randf_range(-EXTENT + 2.0, EXTENT - 2.0)
		var z := rng.randf_range(-EXTENT + 2.0, EXTENT - 2.0)
		var pos := Vector3(x, 0, z)
		if pos.length() < CAMP_RADIUS * 0.8:
			continue
		if creek_distance(pos) < creek_clearance:
			continue
		pos.y = height_at(x, z)
		transforms.append(place.call(pos, rng))
		colors.append(tint.call(rng))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = mat
	add_child(node)

func _build_camp() -> void:
	var camp := Node3D.new()
	camp.name = "ResearchCamp"
	camp.position = Vector3(0, height_at(0, 0), 0)
	add_child(camp)

	var tent_mat := PlaceholderFactory.material(Color(0.55, 0.45, 0.25))
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 2.2, 4.0)
	camp.add_child(PlaceholderFactory.mesh_node(box, tent_mat, Vector3(3, 1.1, 0)))

	var table := BoxMesh.new()
	table.size = Vector3(1.4, 0.1, 2.2)
	camp.add_child(PlaceholderFactory.mesh_node(table,
		PlaceholderFactory.material(Color(0.35, 0.3, 0.28)), Vector3(-2.5, 0.9, 0)))

	# A visible marker so the player can find camp again from the ridge.
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.06
	pole.height = 6.0
	camp.add_child(PlaceholderFactory.mesh_node(pole,
		PlaceholderFactory.material(Color(0.85, 0.35, 0.2)), Vector3(0, 3.0, 0)))

func _build_sky() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.34, 0.55)
	sky_mat.sky_horizon_color = Color(0.66, 0.71, 0.74)
	sky_mat.ground_horizon_color = Color(0.42, 0.42, 0.40)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.13)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	e.sky = sky

	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.45

	# The default linear tonemapper made everything look like flat, washed-out
	# paint. ACES gives the highlights somewhere to roll off to. Colour
	# adjustments are deliberately left off — they need a post-process pass that
	# is not dependable on the Compatibility renderer the browser build uses.
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.tonemap_white = 4.0

	e.fog_enabled = true
	e.fog_density = 0.0022
	e.fog_light_color = Color(0.56, 0.62, 0.68)
	env.environment = e
	add_child(env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.light_energy = 1.0
	add_child(_sun)

## Lighting listens to the clock. The clock knows nothing about lighting.
func _on_time_changed(_day: int, hour: float) -> void:
	if _sun == null:
		return
	var t := clampf((hour - 5.0) / 14.0, -0.2, 1.2)
	_sun.rotation_degrees = Vector3(-lerpf(-6.0, 186.0, t), 35.0, 0.0)
	var light := GameClock.light_level()
	_sun.light_energy = lerpf(0.02, 1.15, light)
	_sun.light_color = Color(1.0, lerpf(0.72, 0.97, light), lerpf(0.55, 0.92, light))

## Somewhere sensible to put an animal: near the creek, well upstream of camp.
func suggested_animal_home(rng: RandomNumberGenerator, min_distance_from_camp := 45.0) -> Vector3:
	for _i in 40:
		var z := rng.randf_range(-EXTENT * 0.8, EXTENT * 0.8)
		var x := creek_x(z) + rng.randf_range(-14.0, 14.0)
		var pos := Vector3(x, 0, z)
		if pos.length() >= min_distance_from_camp:
			return Vector3(x, height_at(x, z) + 0.5, z)
	return Vector3(creek_x(60.0), height_at(creek_x(60.0), 60.0) + 0.5, 60.0)
