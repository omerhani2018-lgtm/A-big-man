extends Control
# Main menu: New Game, Continue, Settings, Quit. Built entirely in code.

var _main: VBoxContainer
var _new_box: VBoxContainer
var _settings_box: VBoxContainer
var _name_edit: LineEdit
var _continue_btn: Button
var _confirm_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font_size = 26
	theme = th

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.07, 0.09, 0.15)
	add_child(bg)
	_add_skyline()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.88)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(560, 0)
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	var title := Label.new()
	title.text = "A BIG MAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "You just turned 18. Build your life."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	root.add_child(sub)

	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 12)
	root.add_child(_main)
	_btn(_main, "New Game", _show_new)
	_continue_btn = _btn(_main, "Continue", _continue)
	_continue_btn.disabled = not GameState.has_save()
	_btn(_main, "Settings", _show_settings)
	if OS.get_name() != "Android" and OS.get_name() != "iOS":
		_btn(_main, "Quit", func(): get_tree().quit())

	_new_box = VBoxContainer.new()
	_new_box.add_theme_constant_override("separation", 12)
	_new_box.visible = false
	root.add_child(_new_box)
	var nl := Label.new()
	nl.text = "What is your name?"
	_new_box.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.text = "Alex"
	_name_edit.max_length = 14
	_name_edit.custom_minimum_size = Vector2(0, 64)
	_new_box.add_child(_name_edit)
	_confirm_label = Label.new()
	_confirm_label.text = ""
	_confirm_label.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_new_box.add_child(_confirm_label)
	_btn(_new_box, "Start my life", _start_new)
	_btn(_new_box, "Back", _show_main)

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 12)
	_settings_box.visible = false
	root.add_child(_settings_box)
	_build_settings()

func _add_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var x := 0.0
	while x < 2200.0:
		var w := rng.randf_range(60.0, 140.0)
		var h := rng.randf_range(160.0, 520.0)
		var r := ColorRect.new()
		r.color = Color(0.1, 0.13, 0.22).lerp(Color(0.2, 0.26, 0.4), rng.randf())
		r.anchor_top = 1.0
		r.anchor_bottom = 1.0
		r.offset_left = x
		r.offset_right = x + w
		r.offset_top = -h
		r.offset_bottom = 0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		x += w + rng.randf_range(4.0, 20.0)

func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 72)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _show_main() -> void:
	_main.visible = true
	_new_box.visible = false
	_settings_box.visible = false
	_continue_btn.disabled = not GameState.has_save()

func _show_new() -> void:
	_main.visible = false
	_settings_box.visible = false
	_new_box.visible = true
	_confirm_label.text = "Starting a new game will replace your old save." if GameState.has_save() else ""

func _start_new() -> void:
	GameState.new_game(_name_edit.text)
	GameState.delete_save()
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _continue() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file("res://scenes/world.tscn")
	else:
		_continue_btn.text = "Save could not be loaded"

func _show_settings() -> void:
	_main.visible = false
	_new_box.visible = false
	_settings_box.visible = true
	_build_settings()

func _build_settings() -> void:
	for c in _settings_box.get_children():
		c.queue_free()
	var s: Dictionary = GameState.settings
	var qn := ["Low", "Medium", "High"]
	_btn(_settings_box, "Camera: %s person" % ("First" if s["camera_mode"] == "first" else "Third"), func():
		s["camera_mode"] = "third" if s["camera_mode"] == "first" else "first"
		_changed())
	_btn(_settings_box, "Look sensitivity: %.1f" % float(s["look_sensitivity"]), func():
		var vals := [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
		var idx := 0
		for i in range(vals.size()):
			if absf(float(vals[i]) - float(s["look_sensitivity"])) < 0.01:
				idx = i
		s["look_sensitivity"] = vals[(idx + 1) % vals.size()]
		_changed())
	_btn(_settings_box, "Volume: %d%%" % int(round(float(s["volume"]) * 100.0)), func():
		var v := float(s["volume"]) + 0.2
		s["volume"] = 0.0 if v > 1.01 else v
		_changed())
	_btn(_settings_box, "Graphics quality: %s" % qn[int(s.get("quality", 1))], func():
		s["quality"] = (int(s.get("quality", 1)) + 1) % 3
		_changed())
	_btn(_settings_box, "Shadows: %s" % ("On" if s["shadows"] else "Off"), func():
		s["shadows"] = not bool(s["shadows"])
		_changed())
	_btn(_settings_box, "Back", _show_main)

func _changed() -> void:
	GameState.save_settings()
	GameState.apply_settings()
	_build_settings()
