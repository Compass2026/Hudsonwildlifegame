extends Node
## The player's record of the expedition.
##
## It is a pure listener: it subscribes to EventBus and writes things down. No
## other system pushes into it, and it pushes into nothing. That is why the
## notebook UI can be replaced wholesale without touching gameplay.

var entries: Array[EvidenceRecord] = []
var sightings: Array[Dictionary] = []
var filed_reports: Array[Dictionary] = []
var log_lines: Array[String] = []

func _ready() -> void:
	EventBus.evidence_examined.connect(_on_examined)
	EventBus.evidence_recorded.connect(_record)
	EventBus.photo_taken.connect(_on_photo)
	EventBus.animal_sighted.connect(_on_sighted)
	EventBus.investigation_report_filed.connect(_on_report_filed)

func _on_examined(record: EvidenceRecord, report: Dictionary) -> void:
	_record(record)
	_log("%s examined at %s — %s" % [record.type_label(), record.substrate_label, report["age"]])

func _on_photo(record: EvidenceRecord, critique: Array) -> void:
	_record(record)
	var subject := "no identifiable subject"
	if record.source_species_id != &"":
		subject = "subject in frame"
	_log("Photograph taken (%s, quality %d%%)" % [subject, int(record.effective_quality() * 100.0)])

func _on_sighted(species_id: StringName, _uid: int) -> void:
	sightings.append({
		"species_id": species_id,
		"time": GameClock.clock_string(),
		"hours": GameClock.absolute_hours(),
	})
	_log("Visual contact with an animal at %s" % GameClock.clock_string())
	EventBus.notebook_updated.emit()

func _on_report_filed(result: Dictionary) -> void:
	filed_reports.append(result)
	_log("Report filed: %s" % result.get("headline", ""))
	EventBus.notebook_updated.emit()

func _record(r: EvidenceRecord) -> void:
	if r in entries:
		return
	r.collected = true
	entries.append(r)
	EventBus.notebook_updated.emit()

func _log(text: String) -> void:
	log_lines.append("[%s] %s" % [GameClock.clock_string(), text])
	if log_lines.size() > 200:
		log_lines.pop_front()

# --- Queries --------------------------------------------------------------

func case_strength() -> float:
	return EvidenceSystem.case_strength(entries)

func entries_of_kind(kind: EvidenceKind.Type) -> Array[EvidenceRecord]:
	return entries.filter(func(r): return r.kind == kind)

func examined_count() -> int:
	return entries.filter(func(r): return r.examined).size()

func best_photo_quality() -> float:
	var best := 0.0
	for r in entries:
		if r.kind == EvidenceKind.Type.PHOTOGRAPH:
			best = maxf(best, r.effective_quality())
	return best

func clear() -> void:
	entries.clear()
	sightings.clear()
	filed_reports.clear()
	log_lines.clear()
	EventBus.notebook_updated.emit()
