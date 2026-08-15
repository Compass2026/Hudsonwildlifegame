class_name ContentProvenance
extends RefCounted
## Every piece of in-game content declares where its claims come from.
##
## This is a hard architectural requirement, not a UI nicety: the game mixes
## real conservation science with invented scenarios, and the player must never
## be unable to tell which is which. Species entries, investigations, briefings
## and report verdicts all carry a Kind and the UI is required to display it.

enum Kind {
	REAL,        ## Factual, sourced. Reflects current real-world science.
	HISTORICAL,  ## Factual for a stated past date. Must show the date.
	SPECULATIVE, ## Invented scenario. Must be labelled FICTIONAL in the UI.
}

static func from_string(s: String) -> Kind:
	match s.to_lower():
		"historical": return Kind.HISTORICAL
		"speculative", "fictional": return Kind.SPECULATIVE
		_: return Kind.REAL

static func label(kind: Kind) -> String:
	match kind:
		Kind.HISTORICAL: return "HISTORICAL RECORD"
		Kind.SPECULATIVE: return "FICTIONAL / SPECULATIVE"
		_: return "REAL-WORLD DATA"

static func color(kind: Kind) -> Color:
	match kind:
		Kind.HISTORICAL: return Color(0.85, 0.72, 0.36)
		Kind.SPECULATIVE: return Color(0.86, 0.45, 0.78)
		_: return Color(0.48, 0.80, 0.55)

## Long-form disclaimer shown alongside any non-real content.
static func disclaimer(kind: Kind) -> String:
	match kind:
		Kind.HISTORICAL:
			return "This scenario is set in the past. It reflects what was known or believed at that time, not the species' status today."
		Kind.SPECULATIVE:
			return "This scenario is fictional. Any discovery made here is part of the game and is NOT a real scientific record."
		_:
			return "Based on published conservation science. See sources in the species entry."
