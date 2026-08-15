extends Node
## The wildlife database. Loads every species definition it can find and hands
## out SpeciesData objects by id.
##
## Two authoring formats are supported so you are never blocked:
##   data/species/*.json  — hand or tool authored, diff-friendly in git
##   data/species/*.tres  — authored in the Godot inspector
## Both produce the same SpeciesData object; nothing downstream can tell.

const SPECIES_DIR := "res://data/species"
const INVESTIGATION_DIR := "res://data/investigations"

var _species: Dictionary = {}        ## StringName -> SpeciesData
var _investigations: Dictionary = {} ## StringName -> InvestigationData

func _ready() -> void:
	_load_species()
	_load_investigations()

func _load_species() -> void:
	for path in _files_in(SPECIES_DIR):
		var s: SpeciesData = null
		if path.ends_with(".json"):
			var d := _read_json(path)
			if not d.is_empty():
				s = SpeciesData.from_dict(d)
		elif path.ends_with(".tres") or path.ends_with(".res"):
			s = load(path) as SpeciesData
		if s != null and s.id != &"":
			_species[s.id] = s
	print("[SpeciesDB] loaded %d species: %s" % [_species.size(), str(_species.keys())])

func _load_investigations() -> void:
	for path in _files_in(INVESTIGATION_DIR):
		var inv: InvestigationData = null
		if path.ends_with(".json"):
			var d := _read_json(path)
			if not d.is_empty():
				inv = InvestigationData.from_dict(d)
		elif path.ends_with(".tres") or path.ends_with(".res"):
			inv = load(path) as InvestigationData
		if inv != null and inv.id != &"":
			_investigations[inv.id] = inv

func _files_in(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[SpeciesDB] cannot open %s" % dir_path)
		return out
	for f in dir.get_files():
		# Exported projects rename .json imports; .remap handling keeps this safe.
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".json") or fname.ends_with(".tres") or fname.ends_with(".res"):
			out.append(dir_path.path_join(fname))
	return out

func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("[SpeciesDB] empty or unreadable: %s" % path)
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[SpeciesDB] invalid JSON in %s" % path)
		return {}
	return parsed

# --- Queries --------------------------------------------------------------

func get_species(id: StringName) -> SpeciesData:
	return _species.get(id, null)

func has_species(id: StringName) -> bool:
	return _species.has(id)

func all_species() -> Array[SpeciesData]:
	var out: Array[SpeciesData] = []
	for k in _species:
		out.append(_species[k])
	return out

func species_ids() -> Array:
	return _species.keys()

func get_investigation(id: StringName) -> InvestigationData:
	return _investigations.get(id, null)

func all_investigations() -> Array:
	return _investigations.values()

## Display name that is safe to show even for an unknown id.
func display_name(id: StringName) -> String:
	var s := get_species(id)
	return s.common_name if s != null else "Unidentified"
