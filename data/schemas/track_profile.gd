class_name TrackProfile
extends Resource
## Measurable characteristics of a species' tracks.
##
## This is the heart of identification: it can both GENERATE a plausible set of
## measurements (for an individual animal) and SCORE how well a set of observed
## measurements fits the species. Adding a species = filling this in.
##
## Ranges are [min, max] in centimetres.

@export var length_cm := Vector2(5.0, 7.0)
@export var width_cm := Vector2(5.0, 7.0)
@export var stride_cm := Vector2(30.0, 45.0)   ## walking step length
@export var straddle_cm := Vector2(10.0, 16.0) ## width of the trail itself
@export var toe_count := 4
@export var claw_marks := false
@export var gait := "direct register walk"

@export_group("Shape")
## How the foot is built. Drives BOTH the drawn print and, later, anything else
## that cares about foot structure. A new species picks a shape and the right
## print appears — nobody writes a second track renderer.
##   cat    — round, four toes in an arc, retractile claws that rarely show
##   dog    — longer, more symmetrical, claws usually registering
##   hoof   — two crescent halves
##   bird   — three forward toes and a hallux
@export var foot_shape := "cat"
## Relative size of the heel/metatarsal pad against the toes. A lynx is nearly
## all pad; a bobcat's toes take up more of the print.
@export var heel_scale := 1.0
@export var toe_scale := 1.0
## How far the toes fan out, in degrees either side of centre.
@export var toe_spread_deg := 58.0
## 0 = crisp outline, 1 = soft and indistinct. Furred feet blur their own print,
## which is why a lynx track is famously hard to read even in good ground.
@export var edge_softness := 0.35
## Some species' prints are inherently indistinct (heavy foot fur, soft pads).
## Negative values blur the print regardless of ground conditions.
@export var clarity_bias := 0.0
@export_multiline var field_notes := ""

const KEYS := ["length_cm", "width_cm", "stride_cm", "straddle_cm"]

func _range_for(key: String) -> Vector2:
	match key:
		"length_cm": return length_cm
		"width_cm": return width_cm
		"stride_cm": return stride_cm
		"straddle_cm": return straddle_cm
	return Vector2.ZERO

## Produce the true measurements of one individual animal of this species.
func sample_individual(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for key in KEYS:
		var r := _range_for(key)
		out[key] = rng.randf_range(r.x, r.y)
	out["toe_count"] = toe_count
	out["claw_marks"] = claw_marks
	out["gait"] = gait
	return out

## How well do observed measurements fit this species? 0.0 = impossible, 1.0 = textbook.
## Missing keys are simply not evidence either way — they must not penalise.
func membership(observed: Dictionary) -> float:
	var score := 1.0
	var counted := 0
	for key in KEYS:
		if not observed.has(key):
			continue
		counted += 1
		score *= _range_membership(float(observed[key]), _range_for(key))
	# Toe count and claw registration are categorical, not fuzzy. Claws in a
	# print from a species whose claws do not register is close to decisive.
	if observed.has("toe_count"):
		counted += 1
		score *= 1.0 if int(observed["toe_count"]) == toe_count else 0.10
	if observed.has("claw_marks"):
		counted += 1
		score *= 1.0 if bool(observed["claw_marks"]) == claw_marks else 0.08
	if counted == 0:
		return 0.5 # uninformative, not evidence against
	# Geometric mean keeps one bad measurement from annihilating the score.
	return pow(max(score, 0.0001), 1.0 / float(counted))

## Triangular membership with a soft shoulder either side of the known range.
func _range_membership(value: float, r: Vector2) -> float:
	if r.x >= r.y:
		return 0.5
	if value >= r.x and value <= r.y:
		return 1.0
	var span: float = r.y - r.x
	var shoulder: float = maxf(span * 0.9, 0.5)
	var distance: float = (r.x - value) if value < r.x else (value - r.y)
	return clampf(1.0 - distance / shoulder, 0.02, 1.0)
