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
const TREE_COUNT := 260

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
			var c00 := PlaceholderFactory.substrate_color(substrate_at(p00).kind)
			var c10 := PlaceholderFactory.substrate_color(substrate_at(p10).kind)
			var c11 := PlaceholderFactory.substrate_color(substrate_at(p11).kind)
			var c01 := PlaceholderFactory.substrate_color(substrate_at(p01).kind)
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

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var trunk_mat := PlaceholderFactory.material(Color(0.24, 0.18, 0.13))
	var canopy_mat := PlaceholderFactory.material(Color(0.12, 0.22, 0.13))
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
		add_child(_make_tree(Vector3(x, h, z), rng, trunk_mat, canopy_mat))

func _make_tree(pos: Vector3, rng: RandomNumberGenerator,
		trunk_mat: Material, canopy_mat: Material) -> Node3D:
	var height := rng.randf_range(7.0, 15.0)
	var radius := rng.randf_range(0.18, 0.34)

	var body := StaticBody3D.new()
	body.position = pos

	var trunk := CylinderMesh.new()
	trunk.top_radius = radius * 0.7
	trunk.bottom_radius = radius
	trunk.height = height
	body.add_child(PlaceholderFactory.mesh_node(trunk, trunk_mat, Vector3(0, height * 0.5, 0)))

	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.0
	canopy.bottom_radius = rng.randf_range(1.6, 2.8)
	canopy.height = height * 0.85
	body.add_child(PlaceholderFactory.mesh_node(canopy, canopy_mat, Vector3(0, height * 0.62, 0)))

	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	shape.position.y = height * 0.5
	body.add_child(shape)
	return body

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
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.fog_enabled = true
	e.fog_density = 0.0025
	e.fog_light_color = Color(0.62, 0.68, 0.72)
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
