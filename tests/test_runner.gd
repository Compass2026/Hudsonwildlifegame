extends Node
## Headless checks for the gameplay systems.
##
## The point of this file is architectural, not just QA: every rule that decides
## what the player can conclude runs here with NO window, NO terrain, NO models
## and NO player. If a test in here ever needs a mesh, gameplay has leaked into
## presentation.
##
## Run:  godot --headless --path . res://tests/test_runner.tscn

var _passed := 0
var _failed := 0

func _ready() -> void:
	print("\n=== Hudson Wildlife — system tests ===\n")
	_test_database_loads()
	_test_tracks_discriminate()
	_test_bad_track_is_unreadable()
	_test_weak_case_cannot_confirm_rare_species()
	_test_strong_case_confirms()
	_test_wrong_claim_is_contradicted()
	_test_inconclusive_is_respected()

	print("\n%d passed, %d failed\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Tests ----------------------------------------------------------------

func _test_database_loads() -> void:
	_check("species database loads lynx and bobcat",
		SpeciesDB.has_species(&"canada_lynx") and SpeciesDB.has_species(&"bobcat"))
	_check("investigation loads",
		SpeciesDB.get_investigation(&"ridgeline_report") != null)

func _test_tracks_discriminate() -> void:
	var lynx := SpeciesDB.get_species(&"canada_lynx")
	var bobcat := SpeciesDB.get_species(&"bobcat")
	var big := {"length_cm": 9.5, "width_cm": 9.8, "straddle_cm": 22.0, "toe_count": 4, "claw_marks": false}
	var small := {"length_cm": 4.8, "width_cm": 4.6, "straddle_cm": 13.0, "toe_count": 4, "claw_marks": false}
	_check("a big cat print fits lynx better than bobcat",
		lynx.track.membership(big) > bobcat.track.membership(big))
	_check("a small cat print fits bobcat better than lynx",
		bobcat.track.membership(small) > lynx.track.membership(small))
	_check("registered claws rule out a cat even at the right size",
		lynx.track.membership({"length_cm": 9.0, "toe_count": 4, "claw_marks": true}) < 0.5)
	_check("one measurement alone is weak evidence, not an identification",
		lynx.track.membership({"width_cm": 9.0}) > bobcat.track.membership({"width_cm": 9.0}))

func _test_bad_track_is_unreadable() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var poor := _make_track(&"canada_lynx", 0.12)
	var report := TrackExaminer.examine(poor, rng)
	_check("a barely-registered print yields no toe count",
		not report["observed"].has("toe_count"))
	_check("a barely-registered print is flagged as unreadable",
		report["unreadable"].size() > 0)

func _test_weak_case_cannot_confirm_rare_species() -> void:
	FieldNotebook.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var t := _make_track(&"canada_lynx", 0.9)
	TrackExaminer.examine(t, rng)
	var records := [t]
	var result := IdentificationSystem.evaluate_claim(&"canada_lynx", records, [&"canada_lynx", &"bobcat"])
	_check("one perfect track cannot confirm a lynx",
		result["verdict"] != IdentificationSystem.Verdict.CONFIRMED)
	_check("the game says why it is not enough",
		String(result["assessment"]).length() > 0)

func _test_strong_case_confirms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var records := []
	for i in 3:
		var t := _make_track(&"canada_lynx", 0.92)
		TrackExaminer.examine(t, rng)
		records.append(t)
	records.append(_make_sign(&"canada_lynx", EvidenceKind.Type.SCAT, 0.9))
	records.append(_make_sign(&"canada_lynx", EvidenceKind.Type.HAIR, 0.9))
	records.append(_make_sign(&"canada_lynx", EvidenceKind.Type.DIRECT_SIGHTING, 0.9))
	records.append(_make_photo(&"canada_lynx", 0.85))
	var strength: float = EvidenceSystem.case_strength(records)
	var result := IdentificationSystem.evaluate_claim(&"canada_lynx", records, [&"canada_lynx", &"bobcat"])
	_check("a broad, strong case clears the lynx evidence standard (%.2f)" % strength,
		result["verdict"] == IdentificationSystem.Verdict.CONFIRMED)
	_check("breadth beats repetition",
		strength > EvidenceSystem.case_strength([records[0], records[1], records[2]]))

func _test_wrong_claim_is_contradicted() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var records := []
	for i in 3:
		var t := _make_track(&"bobcat", 0.9)
		TrackExaminer.examine(t, rng)
		records.append(t)
	records.append(_make_photo(&"bobcat", 0.9))
	var result := IdentificationSystem.evaluate_claim(&"canada_lynx", records, [&"canada_lynx", &"bobcat"])
	_check("claiming lynx on bobcat evidence is rejected",
		result["verdict"] in [IdentificationSystem.Verdict.CONTRADICTED,
			IdentificationSystem.Verdict.INSUFFICIENT])

func _test_inconclusive_is_respected() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t := _make_track(&"canada_lynx", 0.25)
	TrackExaminer.examine(t, rng)
	var result := IdentificationSystem.evaluate_claim(&"", [t], [&"canada_lynx", &"bobcat"])
	_check("filing inconclusive on thin evidence is treated as defensible",
		String(result["assessment"]).begins_with("A defensible"))

# --- Helpers --------------------------------------------------------------

func _make_track(species_id: StringName, condition: float) -> EvidenceRecord:
	var species := SpeciesDB.get_species(species_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(condition * 1000.0) + species_id.hash()
	return EvidenceSystem.create(EvidenceKind.Type.TRACK, species_id, Vector3.ZERO,
		condition, species.track.sample_individual(rng))

func _make_sign(species_id: StringName, kind: EvidenceKind.Type, condition: float) -> EvidenceRecord:
	var r := EvidenceSystem.create(kind, species_id, Vector3.ZERO, condition, {})
	r.examined = true
	return r

func _make_photo(species_id: StringName, quality: float) -> EvidenceRecord:
	var cam := FieldCamera.new()
	var ctx := {"subject_visible": true, "distance": 20.0, "screen_fraction": 0.3,
		"occlusion": 0.0, "light_level": 1.0, "camera_motion": 0.0,
		"subject_motion": 0.0, "zoom": 3.0}
	var r := cam.make_record(species_id, Vector3.ZERO, {"quality": quality, "critique": ["test"]}, ctx)
	return EvidenceSystem.add(r)

func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
