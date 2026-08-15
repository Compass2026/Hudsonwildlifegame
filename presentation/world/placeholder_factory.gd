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
		Substrate.Kind.SAND: return Color(0.58, 0.52, 0.38)
		Substrate.Kind.ROCK: return Color(0.46, 0.46, 0.44)
		Substrate.Kind.DUFF: return Color(0.24, 0.25, 0.14)
		Substrate.Kind.GRASS: return Color(0.30, 0.37, 0.19)
		Substrate.Kind.SNOW: return Color(0.90, 0.92, 0.95)
	return Color(0.33, 0.34, 0.19)   # leaf litter

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

## A track mark on the ground. Intentionally low-contrast: sign should be found,
## not flagged. Size follows the real measurement so a big print looks big.
static func build_track_marker(record: EvidenceRecord) -> Node3D:
	var root := Node3D.new()
	var width_cm: float = float(record.truth.get("width_cm", 6.0))
	var size: float = clampf(width_cm / 100.0, 0.04, 0.16)

	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * 1.15)

	var mat := StandardMaterial3D.new()
	var depth: float = record.effective_quality()
	mat.albedo_color = Color(0.10, 0.08, 0.06, clampf(0.20 + depth * 0.55, 0.12, 0.8))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false

	var mi := mesh_node(quad, mat, Vector3(0, 0.02, 0))
	mi.rotation_degrees = Vector3(-90, rad_to_deg(record.heading), 0)
	root.add_child(mi)
	return root

static func build_hair_marker(_record: EvidenceRecord) -> Node3D:
	var root := Node3D.new()
	var tuft := CylinderMesh.new()
	tuft.top_radius = 0.0
	tuft.bottom_radius = 0.02
	tuft.height = 0.09
	var node := mesh_node(tuft, material(Color(0.55, 0.50, 0.44)), Vector3(0, 0.06, 0))
	node.rotation_degrees = Vector3(20, 0, 15)
	root.add_child(node)
	return root

static func build_scat_marker(record: EvidenceRecord) -> Node3D:
	var root := Node3D.new()
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.07
	root.add_child(mesh_node(s, material(Color(0.18, 0.14, 0.10)), Vector3(0, 0.035, 0)))
	return root
