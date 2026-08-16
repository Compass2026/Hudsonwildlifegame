class_name PlaceholderFactory
extends RefCounted
## Builds stand-in visuals from primitives.
##
## Everything here is disposable. When a real model arrives, set
## `presentation.visual_scene` in the species JSON and this code stops being
## called for that species. No gameplay system imports this file.

static func material(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m

static func mesh_node(mesh: Mesh, mat: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi

## Ground colour per substrate. This is presentation, but it matters to play:
## the player has to be able to SEE where the ground will hold a print, because
## reading terrain is most of tracking. Gameplay reads Substrate; only this
## table turns it into a colour.
static func substrate_color(kind: Substrate.Kind) -> Color:
	match kind:
		Substrate.Kind.MUD: return Color(0.26, 0.20, 0.14)
		Substrate.Kind.SAND: return Color(0.47, 0.42, 0.31)
		Substrate.Kind.ROCK: return Color(0.35, 0.35, 0.33)
		Substrate.Kind.DUFF: return Color(0.17, 0.16, 0.10)
		Substrate.Kind.GRASS: return Color(0.22, 0.27, 0.13)
		Substrate.Kind.SNOW: return Color(0.90, 0.92, 0.95)
	return Color(0.25, 0.23, 0.13)   # leaf litter

## A stand-in animal whose every distinguishing feature comes from species data,
## so two cats do not look like the same cat at different sizes.
##
## What actually separates a lynx from a bobcat in the field: leg length, foot
## size, ear tufts, tail length and tip, the facial ruff, and coat pattern. All
## of those are data fields, so the placeholder can already be identified by
## eye — which is the skill the game is asking for.
static func build_animal(species: SpeciesData) -> Node3D:
	var root := Node3D.new()
	root.name = "PlaceholderView"
	var coat := material(species.placeholder_color)
	var dark := material(species.placeholder_color.darkened(0.55))
	var tip := material(Color(0.06, 0.05, 0.05))
	var pale := material(species.placeholder_color.lightened(0.25))

	var body_len: float = species.body_length_m
	var height: float = species.shoulder_height_m
	var body_r: float = body_len * 0.16

	var body := CapsuleMesh.new()
	body.radius = body_r
	body.height = body_len
	var body_node := mesh_node(body, coat, Vector3(0, height, 0))
	body_node.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(body_node)

	# Spots, for a patterned coat. A bobcat is spotted; a lynx is not.
	if species.coat_spotted:
		var spot := SphereMesh.new()
		spot.radius = body_r * 0.17
		spot.height = body_r * 0.2
		spot.radial_segments = 5
		spot.rings = 3
		var rng := RandomNumberGenerator.new()
		rng.seed = int(species.id.hash())
		for i in 10:
			var along := rng.randf_range(-0.4, 0.42) * body_len
			var around := rng.randf() * TAU
			root.add_child(mesh_node(spot, dark, Vector3(
				cos(around) * body_r * 0.95, height + sin(around) * body_r * 0.8, along)))

	var head_y := height + body_r * 0.42
	var head_z := body_len * 0.52

	# Facial ruff — the flared cheek fur, big on a lynx.
	if species.face_ruff > 0.01:
		var ruff := SphereMesh.new()
		ruff.radius = body_r * (0.95 + species.face_ruff * 0.5)
		ruff.height = body_r * 1.1
		root.add_child(mesh_node(ruff, pale, Vector3(0, head_y, head_z - body_r * 0.35)))

	var head := SphereMesh.new()
	head.radius = body_r * 0.85
	head.height = body_r * 1.7
	root.add_child(mesh_node(head, coat, Vector3(0, head_y, head_z)))

	# Ear tufts. Long and black on a lynx, stubby on a bobcat.
	for side in [-1.0, 1.0]:
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.0
		tuft.bottom_radius = body_r * 0.15
		tuft.height = maxf(0.01, height * species.ear_tuft_ratio)
		root.add_child(mesh_node(tuft, tip, Vector3(side * body_r * 0.45,
			head_y + body_r * 0.75 + tuft.height * 0.5, head_z - body_r * 0.1)))

	# Legs, and the feet on the end of them. Foot size is the single best field
	# mark between these two species, so the placeholder shows it.
	var leg := CylinderMesh.new()
	leg.top_radius = body_r * 0.22
	leg.bottom_radius = body_r * 0.26
	leg.height = height
	var paw := SphereMesh.new()
	paw.radius = body_r * 0.30 * species.paw_scale
	paw.height = body_r * 0.34 * species.paw_scale
	paw.radial_segments = 6
	paw.rings = 4
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			var foot := Vector3(x * body_r * 0.7, 0.0, z * body_len * 0.32)
			root.add_child(mesh_node(leg, dark, foot + Vector3(0, height * 0.5, 0)))
			root.add_child(mesh_node(paw, dark, foot + Vector3(0, paw.radius * 0.7, 0)))

	# Tail. A lynx tail is a stub with a wholly black tip; a bobcat's is longer.
	var tail_len: float = body_len * species.tail_ratio
	var tail := CapsuleMesh.new()
	tail.radius = body_r * 0.22
	tail.height = tail_len
	var tail_node := mesh_node(tail, coat,
		Vector3(0, height + body_r * 0.3, -body_len * 0.5 - tail_len * 0.35))
	tail_node.rotation_degrees = Vector3(72, 0, 0)
	root.add_child(tail_node)

	var tail_tip := SphereMesh.new()
	tail_tip.radius = body_r * 0.24
	tail_tip.height = body_r * 0.3
	root.add_child(mesh_node(tail_tip, tip,
		Vector3(0, height + body_r * 0.05, -body_len * 0.5 - tail_len * 0.75)))
	return root

## An actual print rather than a smudge, and a DIFFERENT print per species.
##
## Everything about the shape comes from the species' TrackProfile — foot type,
## toe count, how far the toes fan, how big the heel is against them, whether
## claws register, and how soft the edges are. A lynx draws as a huge round pad
## with blurred outlines because its feet are furred; a bobcat draws smaller
## with crisper, better separated toes. Both from data, no special cases.
##
## Built flat in XZ so the ground normal can tilt it. Unit space is roughly
## 1.0 wide; instance scale turns that into the real width of the foot.
static func track_mesh_for_profile(track: TrackProfile) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var soft: float = clampf(track.edge_softness, 0.0, 1.0)

	match track.foot_shape:
		"hoof":
			_build_hoof(st, soft)
		"bird":
			_build_bird(st, track, soft)
		"dog":
			_build_pad_foot(st, track, soft, 0.30, 0.46, true)
		_:
			# Cat: round, heel-dominant, toes tight and asymmetric.
			_build_pad_foot(st, track, soft, 0.34, 0.42, false)

	st.generate_normals()
	return st.commit()

## The common four/five-toed pad foot. Dogs are longer and more symmetrical
## with claws; cats are rounder with the toes set closer to the pad.
static func _build_pad_foot(st: SurfaceTool, track: TrackProfile, soft: float,
		heel_radius: float, toe_reach: float, symmetric: bool) -> void:
	var heel := heel_radius * track.heel_scale
	# Heel pad, with rear lobes — the biggest feature and the last to wash out.
	_add_pad(st, Vector2(0.0, -0.34), Vector2(heel, heel * 0.70), 14, soft)
	_add_pad(st, Vector2(-heel * 0.47, -0.46), Vector2(heel * 0.38, heel * 0.30), 10, soft)
	_add_pad(st, Vector2(heel * 0.47, -0.46), Vector2(heel * 0.38, heel * 0.30), 10, soft)

	var count: int = maxi(track.toe_count, 1)
	var spread := deg_to_rad(track.toe_spread_deg)
	for i in count:
		var t := 0.0 if count == 1 else (float(i) / float(count - 1)) * 2.0 - 1.0
		var angle := t * spread
		var reach := toe_reach - absf(t) * 0.06
		var centre := Vector2(sin(angle) * reach * 1.15, cos(angle) * reach - 0.02)
		if not symmetric:
			centre.x += 0.03      # the offset that makes it a left or a right
		var pad := Vector2(0.15, 0.18) * track.toe_scale * (1.0 - absf(t) * 0.16)
		_add_pad(st, centre, pad, 12, soft)

		if track.claw_marks:
			var claw_at := centre + Vector2(sin(angle), cos(angle)) * (0.16 * track.toe_scale)
			_add_pad(st, claw_at, Vector2(0.05, 0.10) * track.toe_scale, 6, soft * 0.5)

## Two crescent halves — deer, moose, anything cloven.
static func _build_hoof(st: SurfaceTool, soft: float) -> void:
	for side in [-1.0, 1.0]:
		_add_pad(st, Vector2(side * 0.17, 0.06), Vector2(0.17, 0.40), 12, soft)
		_add_pad(st, Vector2(side * 0.20, -0.34), Vector2(0.10, 0.12), 8, soft)

## Three toes forward, one back.
static func _build_bird(st: SurfaceTool, track: TrackProfile, soft: float) -> void:
	_add_pad(st, Vector2(0.0, -0.05), Vector2(0.10, 0.10), 8, soft)
	for a in [-0.7, 0.0, 0.7]:
		for step in 3:
			var d := 0.14 + float(step) * 0.14
			_add_pad(st, Vector2(sin(a) * d, cos(a) * d),
				Vector2(0.055, 0.075) * track.toe_scale, 6, soft)
	for step in 2:
		var d := 0.14 + float(step) * 0.12
		_add_pad(st, Vector2(0.0, -d - 0.05), Vector2(0.05, 0.07), 6, soft)

## A flat elliptical pad, opaque at the centre and fading at the rim. `soft`
## widens the fade, which is how a furred foot reads as indistinct.
static func _add_pad(st: SurfaceTool, centre: Vector2, radius: Vector2,
		segments: int, soft := 0.35) -> void:
	var centre_col := Color(1, 1, 1, 1)
	var rim_col := Color(1, 1, 1, clampf(0.35 - soft * 0.35, 0.0, 0.35))
	var r: Vector2 = radius * (1.0 + soft * 0.22)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := centre + Vector2(cos(a0) * r.x, sin(a0) * r.y)
		var p1 := centre + Vector2(cos(a1) * r.x, sin(a1) * r.y)
		# Wound so the face points up (+Y).
		st.set_color(centre_col)
		st.add_vertex(Vector3(centre.x, 0.0, -centre.y))
		st.set_color(rim_col)
		st.add_vertex(Vector3(p1.x, 0.0, -p1.y))
		st.set_color(rim_col)
		st.add_vertex(Vector3(p0.x, 0.0, -p0.y))

static func track_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true   # instance tint x the pads' soft edges
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Left feet are drawn mirrored, which flips the winding order.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

## How a single print looks: darker and more opaque the better it registered.
## Still low contrast — sign should be found, not flagged — but readable once
## you are standing over it.
static func track_instance_color(record: EvidenceRecord) -> Color:
	var depth: float = record.effective_quality()
	return Color(0.08, 0.065, 0.05, clampf(0.34 + depth * 0.62, 0.24, 0.95))

## Drawn larger than life on purpose.
##
## A lynx foot is 8-11 cm across. At standing eye height that is a few pixels,
## and a print you cannot see is not a puzzle, it is a pixel hunt. The number
## the player MEASURES is always the true one — this scales the drawing only,
## so identification, the field guide ranges and the lynx-vs-bobcat comparison
## are all unaffected.
##
## Turn this down if spotting sign ever starts feeling too easy; it is the one
## dial for that, and it costs nothing to change.
const TRACK_LEGIBILITY := 3.8

static func track_instance_size(record: EvidenceRecord) -> float:
	var width_cm: float = float(record.truth.get("width_cm", 6.0))
	return clampf(width_cm / 100.0, 0.04, 0.16) * TRACK_LEGIBILITY

# Sign types that stay rare get ordinary nodes, but still share one material
# each. Materials are per-kind, never per-instance.
static var _hair_mat: StandardMaterial3D
static var _scat_mat: StandardMaterial3D
static var _highlight_mat: StandardMaterial3D

## Shared, because accessibility highlights can be numerous too.
static func highlight_material() -> StandardMaterial3D:
	if _highlight_mat == null:
		_highlight_mat = material(Color(0.95, 0.85, 0.35))
		_highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _highlight_mat

static func build_hair_marker(_record: EvidenceRecord) -> Node3D:
	if _hair_mat == null:
		_hair_mat = material(Color(0.55, 0.50, 0.44))
	var root := Node3D.new()
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.0
	tuft.bottom_radius = 0.02
	tuft.height = 0.09
	var node := mesh_node(tuft, _hair_mat, Vector3(0, 0.06, 0))
	node.rotation_degrees = Vector3(20, 0, 15)
	root.add_child(node)
	return root

static func build_scat_marker(_record: EvidenceRecord) -> Node3D:
	if _scat_mat == null:
		_scat_mat = material(Color(0.18, 0.14, 0.10))
	var root := Node3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	root.add_child(mesh_node(sphere, _scat_mat, Vector3(0, 0.035, 0)))
	return root
