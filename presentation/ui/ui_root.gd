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

func _on_investigation_started(_inv: InvestigationData) -> void:
	# Open the notebook on the briefing so the player starts by reading it.
	if not notebook.visible:
		notebook.toggle()
