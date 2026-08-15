class_name SpeciesData
extends Resource
## Everything the game knows about one species.
##
## Adding a species should mean adding one of these (as JSON in data/species/,
## or as a .tres authored in the editor) plus optional art. No system code.
##
## `visual_scene` is the ONLY link between this data and the art pipeline. If it
## is null the game builds a placeholder body from the primitive fields below,
## which is why gameplay works before any model exists.

enum Rarity { COMMON, UNCOMMON, RARE, VERY_RARE, EXTRAORDINARY }

@export_group("Identity")
@export var id: StringName
@export var common_name := ""
@export var scientific_name := ""
@export var provenance: ContentProvenance.Kind = ContentProvenance.Kind.REAL

@export_group("Science")
@export var conservation_status := ""   ## IUCN category, e.g. "Least Concern"
@export var regional_status := ""       ## status in this game region
@export var rarity: Rarity = Rarity.COMMON
@export_multiline var habitat := ""
@export_multiline var diet := ""
@export_multiline var behavior_notes := ""
@export_multiline var identification_notes := ""
@export_multiline var threats := ""
@export_multiline var historical_notes := ""
@export var sources: PackedStringArray = PackedStringArray()

@export_group("Evidence standard")
## Total evidence strength required before the game will let a claim of this
## species be recorded as CONFIRMED. Extraordinary claims, extraordinary
## evidence: a common species needs little, a possible recolonisation needs a lot.
@export var evidence_standard := 1.0
## Prior probability weight used when ranking hypotheses. Rare species are rare.
@export var encounter_prior := 1.0

@export_group("Simulation")
@export var track: TrackProfile
@export var behavior: BehaviorProfile

@export_group("Presentation (replaceable)")
@export var visual_scene: PackedScene
@export var placeholder_color := Color(0.6, 0.55, 0.45)
@export var body_length_m := 1.0
@export var shoulder_height_m := 0.6

func is_fictional() -> bool:
	return provenance == ContentProvenance.Kind.SPECULATIVE

static func rarity_from_string(s: String) -> Rarity:
	var key := s.to_upper()
	if Rarity.has(key):
		return Rarity[key]
	return Rarity.COMMON

## Build from a plain dictionary (JSON). Kept here so the schema lives in one place.
static func from_dict(d: Dictionary) -> SpeciesData:
	var s := SpeciesData.new()
	s.id = StringName(d.get("id", "unknown"))
	s.common_name = d.get("common_name", "Unknown")
	s.scientific_name = d.get("scientific_name", "")
	s.provenance = ContentProvenance.from_string(d.get("provenance", "real"))
	s.conservation_status = d.get("conservation_status", "")
	s.regional_status = d.get("regional_status", "")
	s.rarity = rarity_from_string(d.get("rarity", "common"))
	s.habitat = d.get("habitat", "")
	s.diet = d.get("diet", "")
	s.behavior_notes = d.get("behavior_notes", "")
	s.identification_notes = d.get("identification_notes", "")
	s.threats = d.get("threats", "")
	s.historical_notes = d.get("historical_notes", "")
	s.sources = PackedStringArray(d.get("sources", []))
	s.evidence_standard = float(d.get("evidence_standard", 1.0))
	s.encounter_prior = float(d.get("encounter_prior", 1.0))

	var t := TrackProfile.new()
	var td: Dictionary = d.get("track", {})
	t.length_cm = _v2(td.get("length_cm", [5, 7]))
	t.width_cm = _v2(td.get("width_cm", [5, 7]))
	t.stride_cm = _v2(td.get("stride_cm", [30, 45]))
	t.straddle_cm = _v2(td.get("straddle_cm", [10, 16]))
	t.toe_count = int(td.get("toe_count", 4))
	t.claw_marks = bool(td.get("claw_marks", false))
	t.gait = td.get("gait", "walk")
	t.clarity_bias = float(td.get("clarity_bias", 0.0))
	t.field_notes = td.get("field_notes", "")
	s.track = t

	var b := BehaviorProfile.new()
	var bd: Dictionary = d.get("behavior", {})
	b.walk_speed = float(bd.get("walk_speed", 1.4))
	b.run_speed = float(bd.get("run_speed", 7.0))
	b.home_range_radius = float(bd.get("home_range_radius", 70.0))
	b.detect_distance = float(bd.get("detect_distance", 40.0))
	b.flush_distance = float(bd.get("flush_distance", 22.0))
	b.wariness = float(bd.get("wariness", 0.8))
	b.turn_rate = float(bd.get("turn_rate", 2.5))
	b.flee_duration = float(bd.get("flee_duration", 8.0))
	b.rest_fraction = float(bd.get("rest_fraction", 0.55))
	b.track_interval_m = float(bd.get("track_interval_m", 0.9))
	b.scat_chance_per_hour = float(bd.get("scat_chance_per_hour", 0.4))
	b.hair_chance_per_hour = float(bd.get("hair_chance_per_hour", 0.25))
	var windows: Array[Vector2] = []
	for w in bd.get("active_windows", [[4, 9], [17, 22]]):
		windows.append(_v2(w))
	b.active_windows = windows
	s.behavior = b

	var p: Dictionary = d.get("presentation", {})
	var c: Array = p.get("placeholder_color", [0.6, 0.55, 0.45])
	s.placeholder_color = Color(float(c[0]), float(c[1]), float(c[2]))
	s.body_length_m = float(p.get("body_length_m", 1.0))
	s.shoulder_height_m = float(p.get("shoulder_height_m", 0.6))
	var scene_path: String = p.get("visual_scene", "")
	if scene_path != "" and ResourceLoader.exists(scene_path):
		s.visual_scene = load(scene_path)
	return s

static func _v2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO
