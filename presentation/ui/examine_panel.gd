class_name ExaminePanel
extends PanelContainer
## Shows what the player got out of studying one piece of sign.
##
## Note what it does NOT show: the species. It shows measurements, what could
## not be read, how old the sign is, and what the wider trail suggests. Drawing
## the conclusion is the player's job, with the field guide open.

var _body: RichTextLabel
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	# Pinned to the right edge so it never covers what you are looking at.
	anchor_left = 1.0
	anchor_top = 0.5
	anchor_right = 1.0
	anchor_bottom = 0.5
	offset_left = -500
	offset_top = -240
	offset_right = -40
	offset_bottom = 240
	visible = false
	_rng.randomize()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.08, 0.94)
	style.border_color = Color(0.45, 0.5, 0.4)
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	add_child(vbox)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.custom_minimum_size = Vector2(430, 380)
	_body.scroll_active = true
	vbox.add_child(_body)

	var close := Button.new()
	close.text = "Close  —  E or Esc"
	close.pressed.connect(hide_panel)
	vbox.add_child(close)

	EventBus.request_examine.connect(show_for)

## Claimed in _input so a focused button can never swallow the close key.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		hide_panel()
		get_viewport().set_input_as_handled()

func show_for(record: EvidenceRecord) -> void:
	var report := TrackExaminer.examine(record, _rng)
	_body.text = _format(record, report)
	visible = true
	EventBus.ui_modal_changed.emit(true)

func hide_panel() -> void:
	if not visible:
		return
	visible = false
	EventBus.ui_modal_changed.emit(false)

func _format(r: EvidenceRecord, report: Dictionary) -> String:
	var out := "[b]%s[/b]  —  %s\n" % [r.type_label(), r.substrate_label]
	out += "[i]%s[/i]\n\n" % report["age"]

	var observed: Dictionary = report["observed"]
	if observed.is_empty():
		out += "[color=#c98]Nothing measurable.[/color]\n"
	else:
		out += "[b]Measured[/b]  (±%d%%)\n" % report["error_margin_pct"]
		for key in observed:
			out += "  %s: %s\n" % [_pretty(key), _value(observed[key])]

	var unreadable: Array = report["unreadable"]
	if not unreadable.is_empty():
		out += "\n[color=#c98][b]Could not read[/b][/color]\n"
		for key in unreadable:
			out += "  %s — did not register\n" % _pretty(key)

	out += "\n[color=#9ab]%s[/color]\n" % report["confidence_note"]

	# What the wider trail says. Requires more than this one print.
	var nearby := EvidenceSystem.records_near(r.position, 25.0)
	var direction := TrackExaminer.infer_direction(nearby)
	out += "\n[b]Trail[/b]\n  %s\n" % direction["text"]
	out += "  %s\n" % TrackExaminer.estimate_animal_count(FieldNotebook.entries)

	out += "\n[color=#7a9]Recorded in the field notebook. Case strength now %.2f.[/color]" % FieldNotebook.case_strength()
	return out

func _pretty(key: String) -> String:
	match key:
		"length_cm": return "Print length"
		"width_cm": return "Print width"
		"stride_cm": return "Stride"
		"straddle_cm": return "Straddle"
		"toe_count": return "Toes"
		"claw_marks": return "Claw marks"
	return key.capitalize()

func _value(v) -> String:
	if v is bool:
		return "present" if v else "absent"
	if v is int:
		return str(v)
	return "%.1f cm" % float(v)
