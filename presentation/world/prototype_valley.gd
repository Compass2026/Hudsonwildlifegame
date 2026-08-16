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
const CREEK_OFFSET := 17.0   ## metres east of camp
const CAMP_CENTRE := Vector2(0.0, 0.0)
const CAMP_FLAT_RADIUS := 8.0
const CAMP_BLEND := 9.0
const TREE_COUNT := 650
const SHRUB_COUNT := 1800
const ROCK_COUNT := 260

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _sun: DirectionalLight3D
var _camp_level := 0.0

func _ready() -> void:
	_noise.seed = 20260815
	_noise.frequency = 0.006
	_noise.fractal_octaves = 4
	_detail.seed = 991
	_detail.frequency = 0.05

	# Level for the camp bench, taken from the unflattened terrain so the bench
	# joins the hillside instead of standing proud of it.
	_camp_level = _raw_height(CAMP_CENTRE.x, CAMP_CENTRE.y)

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
##
## Camp sits on a level bench blended into the hillside: nobody pitches a tent
## on a slope, and the terrain has to agree with that or the tent floats.
func height_at(x: float, z: float) -> float:
	var raw := _raw_height(x, z)
	var d := Vector2(x - CAMP_CENTRE.x, z - CAMP_CENTRE.y).length()
	var blend := clampf(1.0 - (d - CAMP_FLAT_RADIUS) / CAMP_BLEND, 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)      # smoothstep, so it eases in
	return lerpf(raw, _camp_level, blend)

func _raw_height(x: float, z: float) -> float:
	var slope := (z + EXTENT) / (EXTENT * 2.0) * 10.0   ## valley climbs to the north
	# A channel with a FLAT BED, not a V. A parabola bottoms out at a point, so
	# water sat in a 25 cm wide sliver and was invisible; a real creek has a bed
	# you can walk, with the print-holding mud along its margins.
	var d := absf(x - creek_x(z))
	var t := clampf((d - BED_HALF_WIDTH) / (BANK_HALF_WIDTH - BED_HALF_WIDTH), 0.0, 1.0)
	var depth := CHANNEL_DEPTH * (1.0 - t * t)
	# The hillside noise is +/-14 m and the channel only 7 m deep, so left alone
	# the noise simply drowned the carve: the true low point wandered several
	# metres off the centre line and a water surface keyed to the centre sat
	# above the ground on one bank and under it on the other. Water cuts its own
	# bed in real ground, so fade the noise out as the bed is approached. Inside
	# BED_HALF_WIDTH it is gone entirely and the bed is genuinely flat and
	# genuinely the lowest ground.
	var smooth := t * t * (3.0 - 2.0 * t)
	var rolling := _noise.get_noise_2d(x, z) * 14.0 * smooth
	return rolling + slope - depth

## The drainage meanders; following it is the point. Offset so it runs PAST
## camp rather than through it — you camp near water, not in it.
func creek_x(z: float) -> float:
	return sin(z * 0.028) * 26.0 + sin(z * 0.011) * 12.0 + CREEK_OFFSET

func creek_distance(pos: Vector3) -> float:
	return absf(pos.x - creek_x(pos.z))

## Sampled from the height field rather than the mesh, so it agrees with
## height_at() exactly.
func normal_at(pos: Vector3) -> Vector3:
	const D := 0.6
	var hx := height_at(pos.x + D, pos.z) - height_at(pos.x - D, pos.z)
	var hz := height_at(pos.x, pos.z + D) - height_at(pos.x, pos.z - D)
	return Vector3(-hx, 2.0 * D, -hz).normalized()

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

const BED_HALF_WIDTH := 3.4    ## flat bed either side of the centre line
const BANK_HALF_WIDTH := 16.0  ## where the channel meets the hillside
const CHANNEL_DEPTH := 7.0
const WATER_HALF_WIDTH := 4.0  ## the quad; terrain hides whatever overhangs
const WATER_DEPTH := 0.30      ## how deep the water stands over the bed

## Actual water in the channel: a surface that follows the lowest line of the
## carved bed, sits below its banks, and is wide enough to be a feature you
## navigate by rather than a painted stripe.
##
## The mud that holds prints is the margin either side of it, so the water is
## also the clearest visual cue for where tracking is worth doing.
func _build_water() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0
	var z := -EXTENT
	while z < EXTENT - step:
		var z2 := z + step
		var xa := creek_x(z)
		var xb := creek_x(z2)
		# Surface height from the deepest point of the bed, not the bank.
		var ya := _bed_level(xa, z)
		var yb := _bed_level(xb, z2)
		var a_l := Vector3(xa - WATER_HALF_WIDTH, ya, z)
		var a_r := Vector3(xa + WATER_HALF_WIDTH, ya, z)
		var b_l := Vector3(xb - WATER_HALF_WIDTH, yb, z2)
		var b_r := Vector3(xb + WATER_HALF_WIDTH, yb, z2)
		# Godot's front face is the CLOCKWISE winding, which is the opposite of
		# what feels natural to write. The first version of this quad wound the
		# other way, so the surface faced the bed and was culled from every angle
		# a player can stand at: the water was in the scene the whole time and
		# never drew a pixel. Same order as the terrain above, which is correct.
		for p in [a_l, a_r, b_r, a_l, b_r, b_l]:
			st.set_uv(Vector2(p.x * 0.25, p.z * 0.25))
			st.add_vertex(p)
		z = z2
	st.generate_normals()
	st.generate_tangents()

	var mi := MeshInstance3D.new()
	mi.name = "Creek"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.29, 0.31, 0.82)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.25
	mat.metallic_specular = 0.9
	# Water is worth seeing from the bank, from the bed, and from a ford, and it
	# is one surface — culling it buys nothing and only risks losing it again.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Shallow, moving water catches the sky at grazing angles.
	mat.rim_enabled = true
	mat.rim = 0.45
	mat.rim_tint = 0.3
	mi.material_override = mat
	add_child(mi)

## Water stands WATER_DEPTH above the bed. The bed is flat across BED_HALF_WIDTH,
## so the surface shows as a band that width plus a little, and disappears under
## the terrain as the banks rise — which is exactly how a creek looks.
func _bed_level(x: float, z: float) -> float:
	return height_at(x, z) + WATER_DEPTH

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
		crown.radial_segments = 6
		crown.rings = 3
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
		if density < -0.45:
			continue          # natural openings, now rarer — this is deep forest
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
		for i in 2:
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
	shrub.radial_segments = 5
	shrub.rings = 2
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

## The camp is its own builder — it is a place, not terrain.
func _build_camp() -> void:
	CampBuilder.build(self, Vector3.ZERO)

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
