extends Node
## Weighs evidence against every species in the database and produces ranked
## hypotheses — never a verdict handed to the player for free.
##
## Two separate ideas live here and both matter:
##
##   FIT       — how well does the evidence match this species?
##   STANDARD  — is there enough evidence to claim it at all?
##
## A perfect fit on one blurry track is still not a confirmation of a species
## that has not been recorded in the region for decades. That is the whole point.

enum Verdict { CONFIRMED, PROBABLE, INCONCLUSIVE, CONTRADICTED, INSUFFICIENT }

const VERDICT_LABEL := {
	Verdict.CONFIRMED: "CONFIRMED",
	Verdict.PROBABLE: "PROBABLE — NOT CONFIRMED",
	Verdict.INCONCLUSIVE: "INCONCLUSIVE",
	Verdict.CONTRADICTED: "CONTRADICTED BY EVIDENCE",
	Verdict.INSUFFICIENT: "INSUFFICIENT EVIDENCE",
}

## Rank candidate species by how well they fit the evidence.
## Returns [{species_id, confidence, fit, notes:Array[String]}, ...] descending.
func rank(records: Array, candidates: Array = []) -> Array:
	var species_list: Array[SpeciesData] = []
	if candidates.is_empty():
		species_list = SpeciesDB.all_species()
	else:
		for id in candidates:
			var s := SpeciesDB.get_species(StringName(id))
			if s != null:
				species_list.append(s)

	var results := []
	var total := 0.0
	for s in species_list:
		var entry := _score_species(s, records)
		total += entry["posterior"]
		results.append(entry)

	for e in results:
		e["confidence"] = (e["posterior"] / total) if total > 0.0 else 0.0
	results.sort_custom(func(a, b): return a["confidence"] > b["confidence"])
	return results

func _score_species(s: SpeciesData, records: Array) -> Dictionary:
	var fit := 1.0
	var notes: Array[String] = []
	var informative := 0

	for r in records:
		var m := 0.5
		var weight: float = EvidenceKind.reliability(r.kind) * r.effective_quality()

		match r.kind:
			EvidenceKind.Type.TRACK:
				if not r.examined:
					continue
				m = s.track.membership(r.observed)
				informative += 1
				if m < 0.25:
					notes.append("Track measurements sit outside the known range for this species.")
				elif m > 0.8:
					notes.append("Track measurements fall squarely in range.")
			EvidenceKind.Type.PHOTOGRAPH, EvidenceKind.Type.TRAIL_CAM:
				m = _photo_match(r, s)
				informative += 1
				if r.effective_quality() < 0.35:
					notes.append("Image is too poor to separate similar species.")
			EvidenceKind.Type.DIRECT_SIGHTING:
				m = 0.85 if r.source_species_id == s.id else 0.25
				informative += 1
			EvidenceKind.Type.EYEWITNESS_REPORT:
				m = 0.6 if r.source_species_id == s.id else 0.45
				weight *= 0.5
				notes.append("Eyewitness testimony alone carries almost no weight.")
			_:
				if r.source_species_id != &"" and r.examined:
					m = 0.7 if r.source_species_id == s.id else 0.4
					informative += 1

		# Weak evidence pulls the score toward 'no information' rather than
		# toward a confident answer. Strong evidence applies nearly in full.
		fit *= lerpf(1.0, m, clampf(weight, 0.0, 1.0))

	# Deliberately a product, not an average: independent evidence must be able
	# to accumulate. Averaging would let a rare species' low prior smother any
	# amount of good evidence, which is the opposite of how a case is built.
	var posterior: float = fit * maxf(s.encounter_prior, 0.001)
	return {
		"species_id": s.id,
		"species": s,
		"fit": fit,
		"posterior": posterior,
		"confidence": 0.0,
		"informative": informative,
		"notes": notes,
	}

## How much a photograph discriminates depends on how good it is.
func _photo_match(r: EvidenceRecord, s: SpeciesData) -> float:
	var q := r.effective_quality()
	var is_subject: bool = r.source_species_id == s.id
	if r.source_species_id == &"":
		return 0.5                    # nothing identifiable in frame
	if q >= 0.75:
		return 1.0 if is_subject else 0.02
	if q >= 0.45:
		return 0.9 if is_subject else 0.18
	if q >= 0.25:
		# Enough for a size class, not enough for a species.
		var subject := SpeciesDB.get_species(r.source_species_id)
		if subject == null:
			return 0.5
		var ratio: float = absf(subject.shoulder_height_m - s.shoulder_height_m)
		return clampf(1.0 - ratio * 2.0, 0.35, 0.8)
	return 0.5

# --- Filing a determination ----------------------------------------------

## The player states a conclusion. The game checks it against BOTH the evidence
## standard for that species and the ground truth, and reports honestly.
##
## claim_id may be &"" meaning "I am calling this inconclusive", which is a
## legitimate and sometimes correct answer.
func evaluate_claim(claim_id: StringName, records: Array, candidates: Array = []) -> Dictionary:
	var strength: float = EvidenceSystem.case_strength(records)
	var ranked := rank(records, candidates)
	var top: Dictionary = ranked[0] if not ranked.is_empty() else {}

	# What actually made the sign the player collected.
	var truth_counts := {}
	for r in records:
		if r.source_species_id != &"":
			truth_counts[r.source_species_id] = truth_counts.get(r.source_species_id, 0) + 1

	var result := {
		"claim": claim_id,
		"strength": strength,
		"ranked": ranked,
		"top_species_id": top.get("species_id", &""),
		"top_confidence": top.get("confidence", 0.0),
		"records_count": records.size(),
	}

	if claim_id == &"":
		var was_reasonable: bool = strength < 1.5 or top.get("confidence", 0.0) < 0.7
		result["verdict"] = Verdict.INCONCLUSIVE
		result["headline"] = "Filed as inconclusive."
		result["assessment"] = ("A defensible call — the evidence did not support a species-level determination."
			if was_reasonable else
			"Cautious. The evidence you gathered would probably have supported a determination.")
		result["provenance"] = ContentProvenance.Kind.REAL
		return result

	var claimed := SpeciesDB.get_species(claim_id)
	if claimed == null:
		result["verdict"] = Verdict.INSUFFICIENT
		result["headline"] = "Unknown species claimed."
		result["assessment"] = ""
		return result

	result["provenance"] = claimed.provenance
	var claim_fit: float = 0.0
	for e in ranked:
		if e["species_id"] == claim_id:
			claim_fit = e["confidence"]
			break

	var truth_supports: bool = truth_counts.get(claim_id, 0) > 0
	var standard: float = claimed.evidence_standard

	if claim_fit < 0.35 and not truth_supports:
		result["verdict"] = Verdict.CONTRADICTED
		result["headline"] = "%s — not supported." % claimed.common_name
		result["assessment"] = "Your own evidence points elsewhere. The most consistent candidate is %s." % [
			SpeciesDB.display_name(result["top_species_id"])]
	elif strength < standard * 0.6:
		result["verdict"] = Verdict.INSUFFICIENT
		result["headline"] = "%s — insufficient evidence." % claimed.common_name
		result["assessment"] = "A claim of %s in this region needs a case of at least %.1f. Yours is %.1f. %s" % [
			claimed.common_name, standard, strength,
			"Independent evidence types are worth more than more of the same."]
	elif strength < standard or claim_fit < 0.6:
		result["verdict"] = Verdict.PROBABLE
		result["headline"] = "%s — probable, not confirmed." % claimed.common_name
		result["assessment"] = "The evidence is consistent with %s but falls short of the standard for a confirmed record (%.1f required, %.1f gathered)." % [
			claimed.common_name, standard, strength]
	else:
		result["verdict"] = Verdict.CONFIRMED
		result["headline"] = "%s — confirmed." % claimed.common_name
		result["assessment"] = "Multiple independent lines of evidence support this determination."

	if claimed.is_fictional():
		result["headline"] = "[%s] %s" % [ContentProvenance.label(claimed.provenance), result["headline"]]
		result["assessment"] += "\n\n" + ContentProvenance.disclaimer(claimed.provenance)

	return result

func verdict_label(v: Verdict) -> String:
	return VERDICT_LABEL.get(v, "UNKNOWN")
