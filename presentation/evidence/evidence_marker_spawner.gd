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

var _markers: Dictionary = {}   ## evidence uid -> Node3D

func _ready() -> void:
	EventBus.evidence_created.connect(_on_created)
	EventBus.evidence_expired.connect(_on_expired)
	EventBus.evidence_discovered.connect(_on_discovered)
	sync_existing()

## Draw sign that already existed before this node was added — e.g. everything
## laid down while the world's history was fast-forwarded at startup.
func sync_existing() -> void:
	for r in EvidenceSystem.all_records():
		if not _markers.has(r.uid):
			_on_created(r)

func _on_created(r: EvidenceRecord) -> void:
	if not EvidenceKind.is_physical_sign(r.kind):
		return
	var marker: Node3D
	match r.kind:
		EvidenceKind.Type.TRACK:
			marker = PlaceholderFactory.build_track_marker(r)
		EvidenceKind.Type.SCAT:
			marker = PlaceholderFactory.build_scat_marker(r)
		EvidenceKind.Type.HAIR:
			marker = PlaceholderFactory.build_hair_marker(r)
		_:
			return
	marker.position = r.position
	add_child(marker)
	_markers[r.uid] = marker

func _on_expired(r: EvidenceRecord) -> void:
	var m: Node3D = _markers.get(r.uid, null)
	if m != null:
		m.queue_free()
		_markers.erase(r.uid)

## Accessibility only. With assist off this does nothing at all.
func _on_discovered(r: EvidenceRecord) -> void:
	if not Settings.highlight_discovered_sign():
		return
	var m: Node3D = _markers.get(r.uid, null)
	if m == null:
		return
	var ring := TorusMesh.new()
	ring.inner_radius = 0.14
	ring.outer_radius = 0.17
	var mat := PlaceholderFactory.material(Color(0.95, 0.85, 0.35))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.add_child(PlaceholderFactory.mesh_node(ring, mat, Vector3(0, 0.03, 0)))
