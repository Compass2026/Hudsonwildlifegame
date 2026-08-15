class_name EvidenceRecord
extends Resource
## One piece of evidence in the world or in the notebook.
##
## `source_species_id` is GROUND TRUTH and must never be shown to the player
## directly. The player only ever sees `observed`, which is what they managed to
## measure, and whatever the identification system infers from it. Keeping truth
## and observation in separate fields is what makes misidentification possible.

@export var uid := 0
@export var kind: EvidenceKind.Type = EvidenceKind.Type.TRACK
@export var source_species_id: StringName = &""
@export var source_animal_uid := 0
@export var position := Vector3.ZERO
@export var heading := 0.0                  ## radians, direction of travel
@export var created_at_hours := 0.0
@export var condition := 0.5                ## 0..1 quality at the moment it was made
@export var persistence := 1.0              ## substrate multiplier on decay
@export var substrate_label := ""
@export var truth: Dictionary = {}          ## real measurements — never shown raw
@export var observed: Dictionary = {}       ## what the player recorded
@export var discovered := false
@export var examined := false
@export var collected := false
@export_multiline var notes := ""
## Set on photographs: how much of the frame the subject filled, occlusion, etc.
@export var capture_context: Dictionary = {}

func age_hours() -> float:
	return maxf(0.0, GameClock.absolute_hours() - created_at_hours)

## Condition after ageing. Falls toward zero; below ~0.05 the sign is gone.
func effective_quality() -> float:
	var half_life := EvidenceKind.half_life_hours(kind) * persistence
	if is_inf(half_life):
		return condition
	if half_life <= 0.0:
		return 0.0
	return condition * pow(0.5, age_hours() / half_life)

func is_expired() -> bool:
	return effective_quality() < 0.05

func type_label() -> String:
	return EvidenceKind.label(kind)

## Human description of age, deliberately vague — the player estimates, they are
## not told a number.
func age_description() -> String:
	var a := age_hours()
	if a < 1.0: return "very fresh — minutes old"
	if a < 4.0: return "fresh — a few hours"
	if a < 12.0: return "made earlier today"
	if a < 30.0: return "roughly a day old"
	if a < 96.0: return "several days old"
	return "old and degraded"
