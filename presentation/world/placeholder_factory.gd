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

## A crude quadruped whose proportions come from the species data, so a lynx
## reads as long-legged and big-footed next to a bobcat even in placeholder form.
static func build_animal(species: SpeciesData) -> Node3D:
	var root := Node3D.new()
	root.name = "PlaceholderView"
	var mat := material(species.placeholder_color)
	var dark := material(species.placeholder_color.darkened(0.55))

	var body_len: float = species.body_length_m
	var height: float = species.shoulder_height_m
	var body_r: float = body_len * 0.16

	var body := CapsuleMesh.new()
	body.radius = body_r
	body.height = body_len
	var body_node := mesh_node(body, mat, Vector3(0, height, 0))
	body_node.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(body_node)

	var head := SphereMesh.new()
	head.radius = body_r * 0.85
	head.height = body_r * 1.7
	root.add_child(mesh_node(head, mat, Vector3(0, height + body_r * 0.4, body_len * 0.52)))

	# Ear tufts — the field mark, scaled off the species' own proportions.
	for side in [-1.0, 1.0]:
		var tuft := CylinderMesh.new()
		tuft.top_radius = 0.0
		tuft.bottom_radius = body_r * 0.16
		tuft.height = height * 0.16
		root.add_child(mesh_node(tuft, dark, Vector3(side * body_r * 0.45,
			height + body_r * 1.15, body_len * 0.5)))

	# Legs. Leg length is where lynx and bobcat visibly differ.
	var leg := CylinderMesh.new()
	leg.top_radius = body_r * 0.22
	leg.bottom_radius = body_r * 0.26
	leg.height = height
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			root.add_child(mesh_node(leg, dark, Vector3(
				x * body_r * 0.7, height * 0.5, z * body_len * 0.32)))

	var tail := CapsuleMesh.new()
	tail.radius = body_r * 0.22
	tail.height = body_len * 0.28
	var tail_node := mesh_node(tail, dark, Vector3(0, height + body_r * 0.3, -body_len * 0.55))
	tail_node.rotation_degrees = Vector3(70, 0, 0)
	root.add_child(tail_node)
	return root

## Track marks are drawn in bulk by a MultiMesh, so the factory supplies the
## shared mesh and material rather than per-track nodes. One material for every
## track in the world: creating one per track exhausts WebGL resources and
## silently kills 3D rendering in the browser.
##
## Per-track variation rides on the MultiMesh instance data instead — size and
## heading in the transform, print clarity in the instance colour.
## An actual print rather than a smudge: a heel pad with toe pads arranged
## ahead of it, built flat in XZ so the ground normal can tilt it.
##
## The shape is generated from the same data the identification system reads —
## toe count and whether claws register — so a species whose claws show gets a
## print with claw marks without anyone writing a second track renderer. Pads
## fade at their edges, which is what stops a print reading as a sticker.
##
## Unit space: roughly 1.0 wide by 1.3 long. Instance scale turns that into the
## real width of the animal's foot.
static func track_mesh_for(toe_count: int, claws: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Heel pad. Wide, set back, slightly lobed at the rear — the biggest single
	# feature of a cat print and the one that survives poor ground longest.
	_add_pad(st, Vector2(0.0, -0.34), Vector2(0.34, 0.24), 14)
	_add_pad(st, Vector2(-0.16, -0.46), Vector2(0.13, 0.10), 10)
	_add_pad(st, Vector2(0.16, -0.46), Vector2(0.13, 0.10), 10)

	# Toes, fanned ahead of the heel. Real prints are asymmetric; the leading
	# toe sits proud of the others, which is how you tell left from right.
	var count: int = maxi(toe_count, 1)
	var spread := deg_to_rad(58.0)
	for i in count:
		var t := 0.0 if count == 1 else (float(i) / float(count - 1)) * 2.0 - 1.0
		var angle := t * spread
		var reach := 0.42 - absf(t) * 0.06
		var centre := Vector2(sin(angle) * reach * 1.15, cos(angle) * reach - 0.02)
		centre.x += 0.03            # the asymmetry that makes it a left or a right
		var pad := Vector2(0.15, 0.18) * (1.0 - absf(t) * 0.16)
		_add_pad(st, centre, pad, 12)

		if claws:
			var claw_at := centre + Vector2(sin(angle), cos(angle)) * 0.17
			_add_pad(st, claw_at, Vector2(0.045, 0.09), 6)

	st.generate_normals()
	return st.commit()

## A flat elliptical pad, opaque at the centre and fading out at the rim, so
## pads blend into the ground instead of ending on a hard edge.
static func _add_pad(st: SurfaceTool, centre: Vector2, radius: Vector2, segments: int) -> void:
	var centre_col := Color(1, 1, 1, 1)
	var rim_col := Color(1, 1, 1, 0.0)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := centre + Vector2(cos(a0) * radius.x, sin(a0) * radius.y)
		var p1 := centre + Vector2(cos(a1) * radius.x, sin(a1) * radius.y)
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
## Intentionally low contrast — sign should be found, not flagged.
static func track_instance_color(record: EvidenceRecord) -> Color:
	var depth: float = record.effective_quality()
	return Color(0.10, 0.08, 0.06, clampf(0.20 + depth * 0.55, 0.12, 0.8))

static func track_instance_size(record: EvidenceRecord) -> float:
	var width_cm: float = float(record.truth.get("width_cm", 6.0))
	return clampf(width_cm / 100.0, 0.04, 0.16)

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
