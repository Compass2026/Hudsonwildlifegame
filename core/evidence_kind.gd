class_name EvidenceKind
extends RefCounted
## Types of evidence and how much scientific weight each one carries.
##
## Reliability here is the *ceiling* for a perfect specimen of that type. The
## actual strength of a record is reliability x condition x age decay, computed
## in EvidenceSystem. A pristine track is still weaker than a clear photograph;
## a single eyewitness report is deliberately near-worthless on its own.

enum Type {
	TRACK,
	SCAT,
	HAIR,
	FEEDING_SIGN,
	SCRAPE,
	KILL_SITE,
	VOCALIZATION,
	PHOTOGRAPH,
	TRAIL_CAM,
	DIRECT_SIGHTING,
	EYEWITNESS_REPORT,
	ENVIRONMENTAL_DNA,
}

const _RELIABILITY := {
	Type.TRACK: 0.45,
	Type.SCAT: 0.50,
	Type.HAIR: 0.55,
	Type.FEEDING_SIGN: 0.30,
	Type.SCRAPE: 0.30,
	Type.KILL_SITE: 0.40,
	Type.VOCALIZATION: 0.35,
	Type.PHOTOGRAPH: 0.95,
	Type.TRAIL_CAM: 0.85,
	Type.DIRECT_SIGHTING: 0.60,
	Type.EYEWITNESS_REPORT: 0.10,
	Type.ENVIRONMENTAL_DNA: 0.90,
}

const _LABEL := {
	Type.TRACK: "Track",
	Type.SCAT: "Scat",
	Type.HAIR: "Hair sample",
	Type.FEEDING_SIGN: "Feeding sign",
	Type.SCRAPE: "Scrape / scent mark",
	Type.KILL_SITE: "Kill site",
	Type.VOCALIZATION: "Vocalisation",
	Type.PHOTOGRAPH: "Photograph",
	Type.TRAIL_CAM: "Trail-camera image",
	Type.DIRECT_SIGHTING: "Direct sighting",
	Type.EYEWITNESS_REPORT: "Eyewitness report",
	Type.ENVIRONMENTAL_DNA: "Environmental DNA",
}

## How fast this evidence loses value, in game hours, on neutral ground.
const _HALF_LIFE_HOURS := {
	Type.TRACK: 30.0,
	Type.SCAT: 240.0,
	Type.HAIR: 400.0,
	Type.FEEDING_SIGN: 120.0,
	Type.SCRAPE: 96.0,
	Type.KILL_SITE: 72.0,
	Type.VOCALIZATION: 0.05,
	Type.PHOTOGRAPH: INF,
	Type.TRAIL_CAM: INF,
	Type.DIRECT_SIGHTING: INF,
	Type.EYEWITNESS_REPORT: INF,
	Type.ENVIRONMENTAL_DNA: 168.0,
}

static func reliability(t: Type) -> float:
	return _RELIABILITY.get(t, 0.3)

static func label(t: Type) -> String:
	return _LABEL.get(t, "Unknown sign")

static func half_life_hours(t: Type) -> float:
	return _HALF_LIFE_HOURS.get(t, 48.0)

static func from_string(s: String) -> Type:
	var key := s.to_upper()
	if Type.has(key):
		return Type[key]
	return Type.TRACK

## Physical sign is left behind by animals; the rest is produced by the player.
static func is_physical_sign(t: Type) -> bool:
	return t in [Type.TRACK, Type.SCAT, Type.HAIR, Type.FEEDING_SIGN,
		Type.SCRAPE, Type.KILL_SITE]
