class_name TrackExaminer
extends RefCounted
## Turns a piece of sign into what the player actually manages to read off it.
##
## This is deliberately lossy. A poor print does not give you a slightly worse
## number — it gives you no number at all for the features that did not
## register, and a wide error bar on the ones that did. That is why a single
## degraded track can never carry an identification on its own.

## Per-feature threshold: below this effective quality the feature is simply
## not readable in the field.
const READABILITY := {
	"length_cm": 0.18,
	"width_cm": 0.15,
	"stride_cm": 0.12,
	"straddle_cm": 0.25,
	"toe_count": 0.45,
	"claw_marks": 0.55,
}

static func examine(record: EvidenceRecord, rng: RandomNumberGenerator) -> Dictionary:
	var q := record.effective_quality()
	var observed := {}
	var unreadable: Array[String] = []

	for key in READABILITY:
		if not record.truth.has(key):
			continue
		if q < READABILITY[key]:
			unreadable.append(key)
			continue
		var truth_value = record.truth[key]
		if truth_value is bool or truth_value is int:
			observed[key] = truth_value
		else:
			# Measurement error grows as the print gets worse.
			var err_frac: float = (1.0 - q) * 0.35
			var noise: float = rng.randfn(0.0, float(truth_value) * err_frac)
			observed[key] = maxf(0.1, float(truth_value) + noise)

	var report := {
		"observed": observed,
		"unreadable": unreadable,
		"quality": q,
		"age": record.age_description(),
		"substrate": record.substrate_label,
		"confidence_note": _confidence_note(q, unreadable.size()),
		"error_margin_pct": int(round((1.0 - q) * 35.0)),
	}
	record.observed = observed
	record.examined = true
	record.collected = true
	EventBus.evidence_examined.emit(record, report)
	return report

static func _confidence_note(q: float, unreadable_count: int) -> String:
	if q >= 0.8 and unreadable_count == 0:
		return "Clean, complete print. Measurements are trustworthy."
	if q >= 0.55:
		return "Readable print, some detail lost. Treat the measurements as approximate."
	if q >= 0.3:
		return "Partial print. Outline only — do not lean on this one alone."
	return "Barely a depression. This tells you something passed, and little else."

## Direction of travel, inferred from a set of tracks from the same trail rather
## than handed over. Needs at least two prints to say anything.
static func infer_direction(records: Array) -> Dictionary:
	var pts: Array[Vector3] = []
	for r in records:
		if r.kind == EvidenceKind.Type.TRACK:
			pts.append(r.position)
	if pts.size() < 2:
		return {"known": false, "text": "One print is not a direction. Find another."}
	# Order by age: oldest first, so the vector points the way the animal went.
	var sorted := records.filter(func(r): return r.kind == EvidenceKind.Type.TRACK)
	sorted.sort_custom(func(a, b): return a.created_at_hours < b.created_at_hours)
	var from: Vector3 = sorted[0].position
	var to: Vector3 = sorted[sorted.size() - 1].position
	var v := to - from
	if v.length() < 1.0:
		return {"known": false, "text": "The prints mill around here. The animal stopped, or fed."}
	var bearing := rad_to_deg(atan2(v.x, -v.z))
	if bearing < 0.0:
		bearing += 360.0
	return {
		"known": true,
		"bearing": bearing,
		"direction": Vector3(v.x, 0.0, v.z).normalized(),
		"text": "Travel bearing roughly %d degrees (%s)." % [int(bearing), compass(bearing)],
	}

static func compass(bearing: float) -> String:
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(bearing / 45.0)) % 8]

## How many animals made this set of tracks, judged by how many distinct
## individuals' measurements are present. The player sees an estimate, not a count.
static func estimate_animal_count(records: Array) -> String:
	var widths: Array[float] = []
	for r in records:
		if r.kind == EvidenceKind.Type.TRACK and r.examined and r.observed.has("width_cm"):
			widths.append(float(r.observed["width_cm"]))
	if widths.size() < 2:
		return "Not enough measured prints to say."
	widths.sort()
	var spread: float = widths[widths.size() - 1] - widths[0]
	var mean: float = 0.0
	for w in widths:
		mean += w
	mean /= float(widths.size())
	if spread / mean > 0.45:
		return "Print sizes differ too much for one animal. At least two animals used this ground."
	return "Print sizes are consistent. Probably a single animal."
