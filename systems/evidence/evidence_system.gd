extends Node
## Registry of every piece of evidence that exists in the world.
##
## Animals push sign in here as a side effect of living. The player's perception
## component asks it what is nearby. The presentation layer listens for
## discovery and decides how (or whether) to draw anything.
##
## Nothing in here knows what a mesh is.

const MAX_RECORDS := 900        ## ring-buffer style cap so long sessions stay cheap
const PRUNE_INTERVAL := 4.0     ## seconds

var _records: Array[EvidenceRecord] = []
var _by_uid: Dictionary = {}
var _next_uid := 1
var _prune_timer := 0.0

func _process(delta: float) -> void:
	_prune_timer += delta
	if _prune_timer >= PRUNE_INTERVAL:
		_prune_timer = 0.0
		_prune()

# --- Creation -------------------------------------------------------------

func create(kind: EvidenceKind.Type, species_id: StringName, pos: Vector3,
		condition: float, truth: Dictionary = {}, animal_uid := 0,
		heading := 0.0) -> EvidenceRecord:
	var r := EvidenceRecord.new()
	r.uid = _next_uid
	_next_uid += 1
	r.kind = kind
	r.source_species_id = species_id
	r.source_animal_uid = animal_uid
	r.position = pos
	r.heading = heading
	r.condition = clampf(condition, 0.0, 1.0)
	r.created_at_hours = GameClock.absolute_hours()
	r.truth = truth

	var sub := EnvironmentSystem.substrate_at(pos)
	r.substrate_label = sub.label
	r.persistence = sub.persistence

	_records.append(r)
	_by_uid[r.uid] = r
	if _records.size() > MAX_RECORDS:
		_evict_one()
	EventBus.evidence_created.emit(r)
	return r

## Animals lay down far more tracks than anything else, so a plain
## oldest-first cap would quietly throw away the scat and hair that a case
## actually needs. Shed the oldest tracks first and keep the rare sign.
func _evict_one() -> void:
	var victim: EvidenceRecord = null
	for r in _records:
		if r.collected:
			continue
		if r.kind == EvidenceKind.Type.TRACK:
			victim = r
			break
		if victim == null:
			victim = r
	if victim != null:
		_remove(victim)

## Register an already-built record (photographs are constructed by the camera).
func add(r: EvidenceRecord) -> EvidenceRecord:
	r.uid = _next_uid
	_next_uid += 1
	if r.created_at_hours == 0.0:
		r.created_at_hours = GameClock.absolute_hours()
	_records.append(r)
	_by_uid[r.uid] = r
	EventBus.evidence_created.emit(r)
	return r

# --- Queries --------------------------------------------------------------

func get_record(uid: int) -> EvidenceRecord:
	return _by_uid.get(uid, null)

func all_records() -> Array[EvidenceRecord]:
	return _records

func discovered_records() -> Array[EvidenceRecord]:
	return _records.filter(func(r): return r.discovered)

func records_near(pos: Vector3, radius: float, only_undiscovered := false) -> Array[EvidenceRecord]:
	var r2 := radius * radius
	var out: Array[EvidenceRecord] = []
	for r in _records:
		if only_undiscovered and r.discovered:
			continue
		if r.position.distance_squared_to(pos) <= r2:
			out.append(r)
	return out

# --- Player interaction ---------------------------------------------------

func discover(r: EvidenceRecord) -> void:
	if r == null or r.discovered:
		return
	r.discovered = true
	EventBus.evidence_discovered.emit(r)

# --- Weighing a case ------------------------------------------------------

## Total scientific weight of a set of records.
##
## Repeats of the same evidence type give sharply diminishing returns: twenty
## tracks of one animal are not twenty times the proof of one track. Breadth of
## independent evidence types is what actually builds a case.
static func case_strength(records: Array) -> float:
	var counts := {}
	var total := 0.0
	for r in records:
		var w: float = EvidenceKind.reliability(r.kind) * r.effective_quality()
		if r.kind == EvidenceKind.Type.TRACK and not r.examined:
			w *= 0.35    # an unmeasured track barely counts
		var n: int = counts.get(r.kind, 0)
		total += w * pow(0.55, n)
		counts[r.kind] = n + 1
	return total

# --- Internals ------------------------------------------------------------

func _prune() -> void:
	var doomed: Array[EvidenceRecord] = []
	for r in _records:
		# Anything the player has written down stays in the notebook forever;
		# it just stops being findable in the world.
		if r.is_expired() and not r.collected:
			doomed.append(r)
	for r in doomed:
		_remove(r)

func _remove(r: EvidenceRecord) -> void:
	_records.erase(r)
	_by_uid.erase(r.uid)
	EventBus.evidence_expired.emit(r)
