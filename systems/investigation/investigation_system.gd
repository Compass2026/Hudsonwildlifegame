extends Node
## Runs the active investigation and evaluates its objectives.
##
## It understands objective TYPES, never specific missions. A new investigation
## is a JSON file. If a future mission needs a new kind of goal, that is one new
## branch in _evaluate() plus a new enum entry — not a new system.

signal state_changed()

var active: InvestigationData = null
var objective_index := 0
var completed := false

var _player_position := Vector3.ZERO

func _ready() -> void:
	EventBus.evidence_discovered.connect(func(_r): _evaluate())
	EventBus.evidence_examined.connect(func(_r, _rep): _evaluate())
	EventBus.photo_taken.connect(func(_r, _c): _evaluate())
	EventBus.notebook_updated.connect(_evaluate)

func start(investigation: InvestigationData) -> void:
	active = investigation
	objective_index = 0
	completed = false
	EventBus.investigation_started.emit(investigation)
	state_changed.emit()
	_evaluate()

func start_by_id(id: StringName) -> void:
	var inv := SpeciesDB.get_investigation(id)
	if inv == null:
		push_error("[InvestigationSystem] no investigation '%s'" % id)
		return
	start(inv)

## Player position is pushed in as plain data so this system never holds a node.
func report_player_position(pos: Vector3) -> void:
	_player_position = pos
	if active != null and not completed:
		var obj := current_objective()
		if not obj.is_empty() and obj["type"] == InvestigationData.ObjectiveType.RETURN_TO:
			_evaluate()

func current_objective() -> Dictionary:
	if active == null or objective_index >= active.objectives.size():
		return {}
	return active.objectives[objective_index]

func current_text() -> String:
	var o := current_objective()
	if o.is_empty():
		return "Investigation complete." if completed else "No active investigation."
	return o.get("text", "")

func progress_string() -> String:
	if active == null:
		return ""
	return "%d / %d" % [objective_index, active.objectives.size()]

## Called by the UI when the player commits to a determination.
func file_report(claim_id: StringName) -> Dictionary:
	if active == null:
		return {}
	var obj := current_objective()
	if obj.is_empty() or obj["type"] != InvestigationData.ObjectiveType.FILE_REPORT:
		var msg := "You can file from camp, once the field work is done."
		EventBus.notice.emit(msg, "warn")
		return {"blocked": true, "headline": msg}
	var result := IdentificationSystem.evaluate_claim(
		claim_id, FieldNotebook.entries, active.candidate_species)
	result["investigation_id"] = active.id
	result["investigation_title"] = active.title
	result["scenario_provenance"] = active.provenance
	EventBus.investigation_report_filed.emit(result)
	_advance_if(true)
	return result

# --- Objective evaluation -------------------------------------------------

func _evaluate() -> void:
	if active == null or completed:
		return
	# Objectives can complete in a chain (finding sign may satisfy two at once).
	var guard := 0
	while not completed and guard < 16:
		guard += 1
		var o := current_objective()
		if o.is_empty():
			break
		if not _is_satisfied(o):
			break
		_advance_if(true)

func _is_satisfied(o: Dictionary) -> bool:
	match o["type"]:
		InvestigationData.ObjectiveType.DISCOVER_EVIDENCE:
			var kind := EvidenceKind.from_string(str(o.get("evidence_type", "track")))
			var need := int(o.get("count", 1))
			var found := 0
			for r in EvidenceSystem.all_records():
				if r.discovered and r.kind == kind:
					found += 1
			return found >= need

		InvestigationData.ObjectiveType.EXAMINE_EVIDENCE:
			return FieldNotebook.examined_count() >= int(o.get("count", 1))

		InvestigationData.ObjectiveType.PHOTOGRAPH:
			return FieldNotebook.best_photo_quality() >= float(o.get("min_quality", 0.5))

		InvestigationData.ObjectiveType.EVIDENCE_STRENGTH:
			return FieldNotebook.case_strength() >= float(o.get("min", 1.0))

		InvestigationData.ObjectiveType.RETURN_TO:
			var p: Array = o.get("position", [0, 0, 0])
			var target := Vector3(float(p[0]), float(p[1]), float(p[2]))
			var radius := float(o.get("radius", 10.0))
			return Vector2(_player_position.x - target.x, _player_position.z - target.z).length() <= radius

		InvestigationData.ObjectiveType.FILE_REPORT:
			return false  # only completed explicitly by file_report()

	return false

func _advance_if(_ok: bool) -> void:
	if active == null:
		return
	EventBus.objective_completed.emit(active.id, objective_index)
	var text := active.objective_text(objective_index)
	objective_index += 1
	if objective_index >= active.objectives.size():
		completed = true
		EventBus.notice.emit("Investigation complete.", "success")
	else:
		EventBus.notice.emit("Objective complete: %s" % text, "success")
	state_changed.emit()
