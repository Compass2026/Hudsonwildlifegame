class_name Substrate
extends RefCounted
## Ground material at a point in the world. Determines whether an animal
## passing through leaves a usable track and how long that track survives.
##
## Tracking is a ground-truth problem: the same animal leaves a textbook print
## in creek mud and nothing at all on ledge rock. That asymmetry is what makes
## reading terrain part of the skill.

enum Kind { ROCK, LEAF_LITTER, GRASS, DUFF, MUD, SAND, SNOW }

var kind: Kind = Kind.LEAF_LITTER
var retention := 0.2      ## 0..1 how clearly a print registers
var persistence := 1.0    ## multiplier on how long the print survives
var label := "leaf litter"

static func make(kind_: Kind) -> Substrate:
	var s := Substrate.new()
	s.kind = kind_
	match kind_:
		Kind.ROCK:
			s.retention = 0.02; s.persistence = 0.3; s.label = "ledge rock"
		Kind.LEAF_LITTER:
			s.retention = 0.22; s.persistence = 0.6; s.label = "leaf litter"
		Kind.GRASS:
			s.retention = 0.15; s.persistence = 0.5; s.label = "grass"
		Kind.DUFF:
			s.retention = 0.40; s.persistence = 0.8; s.label = "forest duff"
		Kind.MUD:
			s.retention = 0.95; s.persistence = 1.6; s.label = "creek mud"
		Kind.SAND:
			s.retention = 0.75; s.persistence = 0.7; s.label = "sand"
		Kind.SNOW:
			s.retention = 0.85; s.persistence = 1.2; s.label = "snow"
	return s
