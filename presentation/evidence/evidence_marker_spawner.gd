class_name EvidenceMarkerSpawner
extends Node3D
## Draws physical sign in the world.
##
## Marks appear when the sign is CREATED, not when the player discovers it — a
## print in the mud is there whether or not anyone has noticed it. Noticing is
## the player's job, handled by FieldPerception. That is the difference between
## tracking and following a quest marker.
##
## This node is pure presentation. Deleting it would not change a single
## gameplay outcome, only the player's ability to see.
##
## Tracks are drawn through a MultiMesh: one mesh, one material, one draw call
## for every print in the world. The earlier version created a node and a
## material per track, which at ~900 tracks exhausted WebGL's resources and
## silently killed 3D rendering in the browser. It is also simply the right way
## to draw thousands of near-identical marks, which is where this is heading.

const TRACK_CAPACITY := 1200

## One MultiMesh per print SHAPE. A species whose claws register gets a
## different print, so it gets its own bucket; everything with the same foot
## shares one. Still one draw call each, however many prints there are.
var _track_pools: Dictionary = {}   ## shape key -> {node, free: Array[int]}
var _slot_of: Dictionary = {}       ## evidence uid -> [shape key, instance index]
var _track_material: StandardMaterial3D
var _markers: Dictionary = {}       ## evidence uid -> Node3D, for non-track sign

func _ready() -> void:
	_track_material = PlaceholderFactory.track_material()
	EventBus.evidence_created.connect(_on_created)
	EventBus.evidence_expired.connect(_on_expired)
	EventBus.evidence_discovered.connect(_on_discovered)
	sync_existing()

## Keyed by species: each one's foot is a different shape, so each gets its own
## MultiMesh. Still one draw call per species, however many prints it leaves.
func _shape_key(record: EvidenceRecord) -> String:
	return String(record.source_species_id)

func _pool_for(record: EvidenceRecord) -> Dictionary:
	var key := _shape_key(record)
	if _track_pools.has(key):
		return _track_pools[key]

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var species := SpeciesDB.get_species(record.source_species_id)
	var profile: TrackProfile = species.track if species != null else TrackProfile.new()
	mm.mesh = PlaceholderFactory.track_mesh_for_profile(profile)
	mm.instance_count = TRACK_CAPACITY

	var node := MultiMeshInstance3D.new()
	node.name = "TrackMarks_%s" % key
	node.multimesh = mm
	node.material_override = _track_material
	add_child(node)

	var free: Array[int] = []
	for i in range(TRACK_CAPACITY - 1, -1, -1):
		mm.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))
		free.append(i)

	var pool := {"node": node, "free": free}
	_track_pools[key] = pool
	return pool

## Draw sign that already existed before this node was added — e.g. everything
## laid down while the world's history was fast-forwarded at startup.
func sync_existing() -> void:
	for r in EvidenceSystem.all_records():
		if not _slot_of.has(r.uid) and not _markers.has(r.uid):
			_on_created(r)

func _on_created(r: EvidenceRecord) -> void:
	if not EvidenceKind.is_physical_sign(r.kind):
		return
	if r.kind == EvidenceKind.Type.TRACK:
		_add_track(r)
		return

	var marker: Node3D
	match r.kind:
		EvidenceKind.Type.SCAT:
			marker = PlaceholderFactory.build_scat_marker(r)
		EvidenceKind.Type.HAIR:
			marker = PlaceholderFactory.build_hair_marker(r)
		_:
			return
	marker.position = r.position
	add_child(marker)
	_markers[r.uid] = marker

func _add_track(r: EvidenceRecord) -> void:
	var pool := _pool_for(r)
	var free: Array = pool["free"]
	if free.is_empty():
		return   # more tracks than we can draw; the record still exists in gameplay
	var slot: int = free.pop_back()
	_slot_of[r.uid] = [_shape_key(r), slot]

	var size := PlaceholderFactory.track_instance_size(r)
	# Lie the print ON the ground rather than on a flat plane through it: tilted
	# to the slope, turned to the animal's direction of travel, and mirrored for
	# a left foot so a trail alternates the way a walking animal's does.
	var up := EnvironmentSystem.normal_at(r.position)
	var forward := Vector3(sin(r.heading), 0.0, cos(r.heading))
	var right := forward.cross(up).normalized()
	if right.length_squared() < 0.5:
		right = Vector3.RIGHT
	forward = up.cross(right).normalized()
	var mirror := -1.0 if bool(r.truth.get("left_foot", false)) else 1.0

	var basis := Basis(right * size * mirror, up * size, forward * size)
	var node: MultiMeshInstance3D = pool["node"]
	node.multimesh.set_instance_transform(slot,
		Transform3D(basis, r.position + up * 0.02))
	node.multimesh.set_instance_color(slot, PlaceholderFactory.track_instance_color(r))

func _on_expired(r: EvidenceRecord) -> void:
	if _slot_of.has(r.uid):
		var entry: Array = _slot_of[r.uid]
		var pool: Dictionary = _track_pools[entry[0]]
		var node: MultiMeshInstance3D = pool["node"]
		node.multimesh.set_instance_transform(entry[1], Transform3D().scaled(Vector3.ZERO))
		pool["free"].append(entry[1])
		_slot_of.erase(r.uid)
		return
	var m: Node3D = _markers.get(r.uid, null)
	if m != null:
		m.queue_free()
		_markers.erase(r.uid)

## Accessibility only. With assist off this does nothing at all.
func _on_discovered(r: EvidenceRecord) -> void:
	if not Settings.highlight_discovered_sign():
		return
	var ring := TorusMesh.new()
	ring.inner_radius = 0.14
	ring.outer_radius = 0.17
	var mat := PlaceholderFactory.highlight_material()
	var node := PlaceholderFactory.mesh_node(ring, mat, r.position + Vector3.UP * 0.03)
	add_child(node)
