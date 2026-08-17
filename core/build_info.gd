class_name BuildInfo
extends RefCounted
## Which build is actually running.
##
## Shown in the corner of the HUD. The browser build is served under fixed
## filenames, so without this there is no way to tell a refreshed page from a
## cached one — and "did my change deploy?" becomes guesswork.
##
## Bump BUILD whenever you export. It is the one thing in the project that has
## to be updated by hand, and it is worth it.

const BUILD := "m2.1"
const BUILT := "2026-08-17"
const NOTES := "engine upgraded to Godot 4.7.1"

static func label() -> String:
	return "build %s (%s)" % [BUILD, BUILT]
