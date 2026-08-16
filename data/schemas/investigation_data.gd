class_name InvestigationData
extends Resource
## One field investigation: a report to look into, a place, and objectives.
##
## Objectives are declarative. InvestigationSystem knows how to evaluate each
## objective TYPE; it never knows anything about this particular investigation.
## New missions are data.

enum ObjectiveType {
	DISCOVER_EVIDENCE,  ## params: evidence_type (String), count (int)
	EXAMINE_EVIDENCE,   ## params: count (int)
	PHOTOGRAPH,         ## params: min_quality (float)
	PHOTOGRAPH_SPECIES, ## params: species (String), min_quality (float)
	EVIDENCE_STRENGTH,  ## params: min (float)
	RETURN_TO,          ## params: position ([x,y,z]), radius (float)
	FILE_REPORT,        ## params: none
}

@export var id: StringName
@export var title := ""
@export var region := ""
@export var provenance: ContentProvenance.Kind = ContentProvenance.Kind.REAL
@export var historical_date := ""            ## required when provenance is HISTORICAL
@export_multiline var briefing := ""
@export_multiline var reported_by := ""
## Species the player should reasonably consider. Never tells them the answer.
@export var candidate_species: Array[StringName] = []
@export var objectives: Array[Dictionary] = []

func objective_text(i: int) -> String:
	if i < 0 or i >= objectives.size():
		return ""
	return objectives[i].get("text", "Objective %d" % (i + 1))

static func type_from_string(s: String) -> ObjectiveType:
	var key := s.to_upper()
	if ObjectiveType.has(key):
		return ObjectiveType[key]
	return ObjectiveType.DISCOVER_EVIDENCE

static func from_dict(d: Dictionary) -> InvestigationData:
	var inv := InvestigationData.new()
	inv.id = StringName(d.get("id", "unknown"))
	inv.title = d.get("title", "Untitled investigation")
	inv.region = d.get("region", "")
	inv.provenance = ContentProvenance.from_string(d.get("provenance", "real"))
	inv.historical_date = d.get("historical_date", "")
	inv.briefing = d.get("briefing", "")
	inv.reported_by = d.get("reported_by", "")
	var cands: Array[StringName] = []
	for c in d.get("candidate_species", []):
		cands.append(StringName(c))
	inv.candidate_species = cands
	var objs: Array[Dictionary] = []
	for o in d.get("objectives", []):
		var od: Dictionary = o.duplicate()
		od["type"] = type_from_string(str(o.get("type", "discover_evidence")))
		objs.append(od)
	inv.objectives = objs
	return inv
