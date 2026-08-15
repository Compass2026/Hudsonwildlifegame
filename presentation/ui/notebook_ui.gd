class_name NotebookUI
extends PanelContainer
## The field notebook: briefing, collected evidence, field guide, determination.
##
## Everything here is read out of the systems on open. The notebook UI holds no
## state of its own, so replacing it with a nicer one is a drop-in change.

var _tabs: TabContainer
var _briefing: RichTextLabel
var _evidence: RichTextLabel
var _guide: RichTextLabel
var _determination: VBoxContainer
var _verdict: RichTextLabel

func _ready() -> void:
	# Anchored to the centre with explicit offsets so it stays centred at any
	# window size. Presets alone leave the offsets wherever they were.
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -440
	offset_top = -310
	offset_right = 440
	offset_bottom = 310
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.08, 0.97)
	style.border_color = Color(0.5, 0.48, 0.38)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)

	_tabs = TabContainer.new()
	add_child(_tabs)

	_briefing = _make_text("Briefing")
	_evidence = _make_text("Evidence")
	_guide = _make_text("Field guide")

	_determination = VBoxContainer.new()
	_determination.name = "Determination"
	_tabs.add_child(_determination)

	EventBus.request_notebook_toggle.connect(toggle)
	EventBus.notebook_updated.connect(_on_notebook_updated)

func _on_notebook_updated() -> void:
	if visible:
		refresh()

func _make_text(tab_name: String) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.name = tab_name
	rt.bbcode_enabled = true
	rt.scroll_active = true
	rt.custom_minimum_size = Vector2(840, 540)
	_tabs.add_child(rt)
	return rt

func toggle() -> void:
	visible = not visible
	if visible:
		refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func refresh() -> void:
	_refresh_briefing()
	_refresh_evidence()
	_refresh_guide()
	_refresh_determination()

# --- Briefing -------------------------------------------------------------

func _refresh_briefing() -> void:
	var inv := InvestigationSystem.active
	if inv == null:
		_briefing.text = "No active investigation."
		return
	var tag := ContentProvenance.label(inv.provenance)
	var color := ContentProvenance.color(inv.provenance).to_html(false)
	var out := "[b]%s[/b]\n[i]%s[/i]\n" % [inv.title, inv.region]
	out += "[color=#%s]%s[/color]\n" % [color, tag]
	if inv.provenance == ContentProvenance.Kind.HISTORICAL and inv.historical_date != "":
		out += "[color=#%s]Setting: %s[/color]\n" % [color, inv.historical_date]
	out += "\nReported by: %s\n\n%s\n\n" % [inv.reported_by, inv.briefing]
	out += "[b]Objectives[/b]\n"
	for i in inv.objectives.size():
		var mark := "[x]" if i < InvestigationSystem.objective_index else "[ ]"
		out += "  %s %s\n" % [mark, inv.objective_text(i)]
	_briefing.text = out

# --- Evidence -------------------------------------------------------------

func _refresh_evidence() -> void:
	var out := "[b]Case strength: %.2f[/b]\n" % FieldNotebook.case_strength()
	out += "[color=#8a9]Independent kinds of evidence are worth far more than repeats of one kind.[/color]\n\n"

	if FieldNotebook.entries.is_empty():
		out += "Nothing collected yet.\n"
	for r in FieldNotebook.entries:
		out += "[b]%s[/b] — %s, %s\n" % [r.type_label(), r.substrate_label, r.age_description()]
		out += "   quality %d%%" % int(r.effective_quality() * 100.0)
		if r.kind == EvidenceKind.Type.PHOTOGRAPH:
			out += "   distance %.1f m" % float(r.capture_context.get("distance_m", 0.0))
		out += "\n"
		for key in r.observed:
			out += "   %s: %s\n" % [key, str(r.observed[key])]
		if r.notes != "":
			out += "   [i]%s[/i]\n" % r.notes.replace("\n", " / ")
		out += "\n"

	out += "\n[b]Log[/b]\n"
	for line in FieldNotebook.log_lines:
		out += "%s\n" % line
	_evidence.text = out

# --- Field guide ----------------------------------------------------------

func _refresh_guide() -> void:
	var out := ""
	var inv := InvestigationSystem.active
	var ids: Array = inv.candidate_species if inv != null else SpeciesDB.species_ids()
	for id in ids:
		var s := SpeciesDB.get_species(StringName(id))
		if s == null:
			continue
		var color := ContentProvenance.color(s.provenance).to_html(false)
		out += "[b]%s[/b]  [i]%s[/i]\n" % [s.common_name, s.scientific_name]
		out += "[color=#%s]%s[/color]\n" % [color, ContentProvenance.label(s.provenance)]
		out += "Status: %s\n" % s.conservation_status
		out += "Regionally: %s\n\n" % s.regional_status
		out += "[b]Tracks[/b] length %.1f–%.1f cm, width %.1f–%.1f cm, straddle %.0f–%.0f cm, %d toes, claws %s\n" % [
			s.track.length_cm.x, s.track.length_cm.y, s.track.width_cm.x, s.track.width_cm.y,
			s.track.straddle_cm.x, s.track.straddle_cm.y, s.track.toe_count,
			"usually visible" if s.track.claw_marks else "not normally registering"]
		out += "[i]%s[/i]\n\n" % s.track.field_notes
		out += "[b]Identification[/b] %s\n\n" % s.identification_notes
		out += "[b]Habitat[/b] %s\n\n" % s.habitat
		out += "[b]Diet[/b] %s\n\n" % s.diet
		out += "[b]Behaviour[/b] %s\n\n" % s.behavior_notes
		if s.historical_notes != "":
			out += "[b]History[/b] %s\n\n" % s.historical_notes
		if s.threats != "":
			out += "[b]Threats[/b] %s\n\n" % s.threats
		out += "[b]Evidence standard[/b] a confirmed record here requires a case of %.1f.\n" % s.evidence_standard
		if not s.sources.is_empty():
			out += "[color=#889]Sources: %s[/color]\n" % ", ".join(s.sources)
		out += "\n────────────────────────────────\n\n"
	_guide.text = out

# --- Determination --------------------------------------------------------

func _refresh_determination() -> void:
	for c in _determination.get_children():
		_determination.remove_child(c)
		c.queue_free()

	var ranked := IdentificationSystem.rank(FieldNotebook.entries,
		InvestigationSystem.active.candidate_species if InvestigationSystem.active != null else [])

	var analysis := RichTextLabel.new()
	analysis.bbcode_enabled = true
	analysis.custom_minimum_size = Vector2(840, 260)
	var out := "[b]What the evidence supports[/b]\n"
	out += "[color=#8a9]Confidence is how well the evidence fits, weighted by how likely the species is to be here. It is not proof.[/color]\n\n"
	if FieldNotebook.entries.is_empty():
		out += "No evidence collected.\n"
	for e in ranked:
		var s: SpeciesData = e["species"]
		out += "  %s%.1f%%\n" % [s.common_name.rpad(26), e["confidence"] * 100.0]
		for n in e["notes"]:
			out += "      [i]%s[/i]\n" % n
	out += "\nCase strength %.2f\n" % FieldNotebook.case_strength()
	analysis.text = out
	_determination.add_child(analysis)

	var prompt := Label.new()
	prompt.text = "File your determination:"
	_determination.add_child(prompt)

	var row := HBoxContainer.new()
	_determination.add_child(row)
	var candidates: Array = (InvestigationSystem.active.candidate_species
		if InvestigationSystem.active != null else SpeciesDB.species_ids())
	for id in candidates:
		var s := SpeciesDB.get_species(StringName(id))
		if s == null:
			continue
		var b := Button.new()
		b.text = s.common_name
		b.pressed.connect(_on_file.bind(s.id))
		row.add_child(b)
	var inconclusive := Button.new()
	inconclusive.text = "Inconclusive"
	inconclusive.pressed.connect(_on_file.bind(&""))
	row.add_child(inconclusive)

	_verdict = RichTextLabel.new()
	_verdict.bbcode_enabled = true
	_verdict.custom_minimum_size = Vector2(840, 180)
	_determination.add_child(_verdict)
	if not FieldNotebook.filed_reports.is_empty():
		_show_verdict(FieldNotebook.filed_reports[FieldNotebook.filed_reports.size() - 1])

func _on_file(species_id: StringName) -> void:
	var result := InvestigationSystem.file_report(species_id)
	if result.get("blocked", false):
		if is_instance_valid(_verdict):
			_verdict.text = "[color=#e9a]%s[/color]" % result["headline"]
		return
	# Filing triggers a notebook rebuild, so this panel may already have been
	# replaced by the time we get here; the rebuilt one re-shows the same result.
	_show_verdict(result)

func _show_verdict(result: Dictionary) -> void:
	if not is_instance_valid(_verdict) or result.is_empty():
		return
	var v: int = result.get("verdict", IdentificationSystem.Verdict.INCONCLUSIVE)
	var out := "[b]%s[/b]\n" % IdentificationSystem.verdict_label(v)
	out += "%s\n\n%s\n" % [result.get("headline", ""), result.get("assessment", "")]
	out += "\n[color=#889]This is a determination made inside a game. It is not a scientific record and must not be cited as one.[/color]"
	_verdict.text = out
