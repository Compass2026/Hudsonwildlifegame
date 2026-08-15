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

var _tracks: MultiMeshInstance3D
var _slot_of: Dictionary = {}       ## evidence uid -> multimesh instance index
var _free_slots: Array[int] = []
var _markers: Dictionary = {}       ## evidence uid -> Node3D, for non-track sign

func _ready() -> void:
	_build_track_multimesh()
	EventBus.evidence_created.connect(_on_created)
	EventBus.evidence_expired.connect(_on_expired)
	EventBus.evidence_discovered.connect(_on_discovered)
	sync_existing()

func _build_track_multimesh() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = PlaceholderFactory.track_mesh()
	mm.instance_count = TRACK_CAPACITY

	_tracks = MultiMeshInstance3D.new()
	_tracks.name = "TrackMarks"
	_tracks.multimesh = mm
	_tracks.material_override = PlaceholderFactory.track_material()
	add_child(_tracks)

	# Every slot starts collapsed to nothing and is claimed as tracks appear.
	for i in range(TRACK_CAPACITY - 1, -1, -1):
		mm.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))
		_free_slots.append(i)

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
	if _free_slots.is_empty():
		return   # more tracks than we can draw; the record still exists in gameplay
	var slot: int = _free_slots.pop_back()
	_slot_of[r.uid] = slot

	var size := PlaceholderFactory.track_instance_size(r)
	# Lie the quad flat on the ground, turn it to face the animal's direction of
	# travel, and scale it to the real width of the print.
	var basis := Basis.from_euler(Vector3(-PI * 0.5, r.heading, 0.0)).scaled(Vector3(size, size, size))
	_tracks.multimesh.set_instance_transform(slot,
		Transform3D(basis, r.position + Vector3.UP * 0.02))
	_tracks.multimesh.set_instance_color(slot, PlaceholderFactory.track_instance_color(r))

func _on_expired(r: EvidenceRecord) -> void:
	if _slot_of.has(r.uid):
		var slot: int = _slot_of[r.uid]
		_tracks.multimesh.set_instance_transform(slot, Transform3D().scaled(Vector3.ZERO))
		_free_slots.append(slot)
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
