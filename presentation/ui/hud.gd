class_name HUD
extends Control
## Heads-up display: time, current objective, transient field notes, viewfinder.
##
## It reads from systems and listens to EventBus. It never decides anything.

const NOTICE_LIFETIME := 7.0

var _clock_label: Label
var _objective_label: Label
var _notice_box: VBoxContainer
var _crosshair: Label
var _viewfinder: Control
var _zoom_label: Label
var _subject_label: Label
var _player: PlayerController

func setup(player: PlayerController) -> void:
	_player = player

func _ready() -> void:
	# Anchors AND offsets, set explicitly. set_anchors_preset() alone left this
	# Control at zero size under the CanvasLayer, so everything anchored to the
	# screen centre — crosshair, viewfinder, field notes — was laid out around
	# the origin and drawn in (or off) the top-left corner.
	_fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := VBoxContainer.new()
	top.position = Vector2(20, 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)

	_clock_label = _make_label("", 18, Color(0.92, 0.94, 0.9))
	top.add_child(_clock_label)

	_objective_label = _make_label("", 15, Color(0.85, 0.88, 0.7))
	_objective_label.custom_minimum_size.x = 520
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_objective_label)

	var hint := _make_label(
		"WASD move   SHIFT slow   C crouch   E examine   F camera   TAB notebook   ESC cursor",
		12, Color(0.7, 0.72, 0.68))
	top.add_child(hint)

	# So a stale cached page is obvious at a glance rather than a mystery.
	top.add_child(_make_label(BuildInfo.label(), 11, Color(0.55, 0.57, 0.54)))

	_crosshair = _make_label("+", 20, Color(0.92, 0.92, 0.92, 0.55))
	_centre(_crosshair, Vector2(-7, -14), Vector2(7, 14))
	add_child(_crosshair)

	_notice_box = VBoxContainer.new()
	_notice_box.anchor_top = 1.0
	_notice_box.anchor_bottom = 1.0
	_notice_box.offset_left = 20
	_notice_box.offset_top = -240
	_notice_box.offset_right = 680
	_notice_box.offset_bottom = -20
	_notice_box.alignment = BoxContainer.ALIGNMENT_END
	_notice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice_box)

	_build_viewfinder()

	EventBus.notice.connect(_on_notice)
	EventBus.time_changed.connect(func(_d, _h): _refresh_clock())
	InvestigationSystem.state_changed.connect(_refresh_objective)
	_refresh_objective()

func _process(_delta: float) -> void:
	if _player == null:
		return
	_viewfinder.visible = _player.camera_mode
	_crosshair.visible = not _player.camera_mode
	if not _player.camera_mode:
		return

	_zoom_label.text = "%.1fx    f/4    ISO %d" % [
		_player.zoom, int(lerpf(3200.0, 200.0, GameClock.light_level()))]

	# Tell the player what the camera can see before they spend the shot. The
	# species is deliberately NOT named — that is what the photograph is for.
	var subject: Dictionary = _player.camera_subject
	if subject.is_empty():
		_subject_label.text = "NO SUBJECT IN FRAME"
		_subject_label.add_theme_color_override("font_color", Color(0.95, 0.6, 0.45))
		return
	var fraction: float = subject.get("screen_fraction", 0.0)
	var occlusion: float = subject.get("occlusion", 0.0)
	var note := "animal in frame — %.0f m, fills %d%% of the frame" % [
		subject.get("distance", 0.0), int(fraction * 100.0)]
	if occlusion > 0.3:
		note += ", partly behind cover"
	if fraction < 0.05:
		note += "  ·  too small to review — get closer or zoom"
	_subject_label.text = note.to_upper()
	_subject_label.add_theme_color_override("font_color",
		Color(0.6, 0.9, 0.6) if fraction >= 0.05 and occlusion <= 0.3 else Color(0.95, 0.8, 0.45))

func _build_viewfinder() -> void:
	_viewfinder = Control.new()
	_fill(_viewfinder)
	_viewfinder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewfinder.visible = false
	add_child(_viewfinder)

	var frame := Panel.new()
	_centre(frame, Vector2(-450, -280), Vector2(450, 280))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.95, 0.95, 0.95, 0.35)
	style.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewfinder.add_child(frame)

	# Bottom-right of the frame: the bottom-left belongs to the field notes.
	_zoom_label = _make_label("", 14, Color(0.95, 0.35, 0.3))
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_centre(_zoom_label, Vector2(180, 244), Vector2(430, 268))
	_viewfinder.add_child(_zoom_label)

	var shoot_hint := _make_label(
		"LEFT CLICK to shoot    MOUSE WHEEL to zoom    F to stow the camera",
		13, Color(0.95, 0.95, 0.95, 0.85))
	shoot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre(shoot_hint, Vector2(-430, -308), Vector2(430, -288))
	_viewfinder.add_child(shoot_hint)

	# Live read on the shot, directly under the frame where the eye already is.
	_subject_label = _make_label("", 14, Color(0.9, 0.9, 0.9))
	_subject_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre(_subject_label, Vector2(-430, 288), Vector2(430, 308))
	_viewfinder.add_child(_subject_label)

func _refresh_clock() -> void:
	_clock_label.text = "%s    light %d%%" % [
		GameClock.clock_string(), int(GameClock.light_level() * 100.0)]

func _refresh_objective() -> void:
	if InvestigationSystem.active == null:
		_objective_label.text = ""
		return
	_objective_label.text = "%s  [%s]\n> %s" % [
		InvestigationSystem.active.title,
		InvestigationSystem.progress_string(),
		InvestigationSystem.current_text()]

func _on_notice(text: String, kind: String) -> void:
	var color := Color(0.85, 0.87, 0.85)
	match kind:
		"clue": color = Color(0.65, 0.85, 0.95)
		"success": color = Color(0.6, 0.9, 0.6)
		"warn": color = Color(0.95, 0.75, 0.45)
	var label := _make_label(text, 15, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 620
	_notice_box.add_child(label)
	while _notice_box.get_child_count() > 4:
		var oldest := _notice_box.get_child(0)
		_notice_box.remove_child(oldest)   # queue_free alone is deferred, so a
		oldest.queue_free()                # burst of finds could stack up

	var tween := create_tween()
	tween.tween_interval(NOTICE_LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, 1.2)
	tween.tween_callback(label.queue_free)

## Fill the parent rect. Explicit, because the preset helpers are easy to get
## subtly wrong and the failure mode is silent.
func _fill(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

## Anchor a control to the screen centre with explicit offsets, so it stays put
## at any resolution.
func _centre(c: Control, top_left: Vector2, bottom_right: Vector2) -> void:
	c.anchor_left = 0.5
	c.anchor_top = 0.5
	c.anchor_right = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = top_left.x
	c.offset_top = top_left.y
	c.offset_right = bottom_right.x
	c.offset_bottom = bottom_right.y

func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
