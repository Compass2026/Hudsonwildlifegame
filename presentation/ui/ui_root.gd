class_name UIRoot
extends CanvasLayer
## Owns the interface. One place to swap the whole UI out.

var hud: HUD
var examine_panel: ExaminePanel
var notebook: NotebookUI

func setup(player: PlayerController) -> void:
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(player)

	examine_panel = ExaminePanel.new()
	examine_panel.name = "ExaminePanel"
	add_child(examine_panel)

	notebook = NotebookUI.new()
	notebook.name = "Notebook"
	add_child(notebook)

	EventBus.investigation_started.connect(_on_investigation_started)
	EventBus.ui_modal_changed.connect(_on_modal_changed)

## One place owns the mouse cursor. Panels say whether they are open; they do
## not each fight over Input.mouse_mode.
func _on_modal_changed(is_open: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED

func _on_investigation_started(_inv: InvestigationData) -> void:
	# Open the notebook on the briefing so the player starts by reading it.
	notebook.open_panel()
	EventBus.notice.emit("Read the briefing, then press Tab to close the notebook and head out.", "info")
