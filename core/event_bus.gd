extends Node
## Global, decoupled event hub.
##
## Systems NEVER hold direct references to each other. They emit here and listen
## here. This is what lets you replace the UI, the animal models, the terrain or
## the whole presentation layer without touching gameplay logic.
##
## Rule of thumb: signals carry DATA OBJECTS (EvidenceRecord, SpeciesData, ...),
## never Nodes. If a signal payload is a Node, gameplay has leaked into
## presentation.

# --- World / simulation ---------------------------------------------------
signal time_changed(day: int, hour: float)
signal hour_elapsed(day: int, hour: int)

# --- Evidence -------------------------------------------------------------
## An animal (or the world) produced a new piece of evidence. The player does
## not know about it yet.
signal evidence_created(record: EvidenceRecord)
## The player noticed it in the world.
signal evidence_discovered(record: EvidenceRecord)
## The player studied it; report holds the *observed* (noisy) measurements.
signal evidence_examined(record: EvidenceRecord, report: Dictionary)
## Something belongs in the notebook without having been examined — a logged
## sighting, a trail-camera image collected later, a sample sent for analysis.
signal evidence_recorded(record: EvidenceRecord)
## The record decayed past usefulness and was removed from the world.
signal evidence_expired(record: EvidenceRecord)

# --- Observation ----------------------------------------------------------
signal photo_taken(record: EvidenceRecord, critique: Array)
signal animal_sighted(species_id: StringName, animal_uid: int)

# --- Investigation --------------------------------------------------------
signal investigation_started(investigation: InvestigationData)
signal objective_completed(investigation_id: StringName, objective_index: int)
signal investigation_report_filed(result: Dictionary)

# --- Notebook / UI --------------------------------------------------------
signal notebook_updated()
signal notice(text: String, kind: String) ## kind: "info" | "clue" | "success" | "warn"
signal request_examine(record: EvidenceRecord)
signal request_notebook_toggle()
