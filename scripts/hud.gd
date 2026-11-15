extends CanvasLayer
# Heads-up display: stats, touch controls, popup menus, notifications.

const TC = preload("res://scripts/touch_controls.gd")

signal action_pressed
signal jump_pressed
signal camera_pressed
signal phone_pressed
signal look(delta: Vector2)

var stick
var run_on := false
var menu_open := false

var _money_label: Label
var _time_label: Label
var _job_label: Label
var _bars := {}
var _prompt: Label
var _notes: VBoxContainer
var _arrow
var _speed_label: Label
var _action_btn
var _jump_btn
var _run_btn
var _menu_panel: PanelContainer
var _menu_title: Label
var _menu_body: Label
var _menu_options: VBoxContainer
var _fps_label: Label
var _root: Control

func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font_size = 22
	_root.theme = th
	add_child(_root)

	var pad := TC.LookPad.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.dragged.connect(func(d: Vector2): look.emit(d))
	_root.add_child(pad)

	_build_status_panel()
	_build_controls()
	_build_overlays()
	_build_menu()
	GameState.changed.connect(refresh)
	GameState.message.connect(notify)
	refresh()

func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob

# ---------------- Building the UI ----------------
func _build_status_panel() -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	_place(panel, 0, 0, 0, 0, 14, 14, 330, 200)
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	_money_label = Label.new()
	_money_label.add_theme_font_size_override("font_size", 28)
	_money_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	vb.add_child(_money_label)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 18)
	vb.add_child(_time_label)
	_job_label = Label.new()
	_job_label.add_theme_font_size_override("font_size", 18)
	vb.add_child(_job_label)
	_add_bar(vb, "health", "Health", Color(0.9, 0.25, 0.25))
	_add_bar(vb, "energy", "Energy", Color(0.95, 0.8, 0.2))
	_add_bar(vb, "hunger", "Food", Color(0.4, 0.75, 0.35))

func _add_bar(parent: Control, key: String, text: String, col: Color) -> void:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.custom_minimum_size = Vector2(70, 0)
	hb.add_child(l)
	var pb := ProgressBar.new()
	pb.min_value = 0
	pb.max_value = 100
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(190, 16)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(6)
	pb.add_theme_stylebox_override("fill", fill)
	pb.add_theme_stylebox_override("background", bg)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(pb)
	parent.add_child(hb)
	_bars[key] = pb

func _build_controls() -> void:
	stick = TC.Joystick.new()
	_place(stick, 0, 1, 0, 1, 30, -300, 290, -40)
	_root.add_child(stick)

	_action_btn = TC.TButton.new("ACT", 130.0)
	_action_btn.tint = Color(0.2, 0.8, 0.4)
	_place(_action_btn, 1, 1, 1, 1, -170, -180, -40, -50)
	_action_btn.pressed.connect(func(): action_pressed.emit())
	_root.add_child(_action_btn)

	_jump_btn = TC.TButton.new("JUMP", 100.0)
	_jump_btn.tint = Color(0.3, 0.55, 0.95)
	_place(_jump_btn, 1, 1, 1, 1, -300, -140, -200, -40)
	_jump_btn.pressed.connect(func(): jump_pressed.emit())
	_root.add_child(_jump_btn)

	_run_btn = TC.TButton.new("RUN", 90.0)
	_run_btn.tint = Color(0.95, 0.6, 0.2)
	_run_btn.font_size = 20
	_place(_run_btn, 1, 1, 1, 1, -150, -290, -60, -200)
	_run_btn.pressed.connect(_toggle_run)
	_root.add_child(_run_btn)

	var cam := TC.TButton.new("CAM", 84.0)
	cam.font_size = 20
	_place(cam, 1, 0, 1, 0, -110, 14, -26, 98)
	cam.pressed.connect(func(): camera_pressed.emit())
	_root.add_child(cam)

	var phone := TC.TButton.new("PHONE", 84.0)
	phone.font_size = 17
	phone.tint = Color(0.6, 0.4, 0.9)
	_place(phone, 1, 0, 1, 0, -206, 14, -122, 98)
	phone.pressed.connect(func(): phone_pressed.emit())
	_root.add_child(phone)

func _build_overlays() -> void:
	_arrow = TC.Arrow.new()
	_place(_arrow, 0.5, 0, 0.5, 0, -60, 8, 60, 98)
	_root.add_child(_arrow)

	_notes = VBoxContainer.new()
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notes.alignment = BoxContainer.ALIGNMENT_BEGIN
	_place(_notes, 0.5, 0, 0.5, 0, -300, 110, 300, 260)
	_root.add_child(_notes)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 26)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_prompt, 0.5, 1, 0.5, 1, -330, -130, 330, -80)
	_prompt.visible = false
	_root.add_child(_prompt)

	_speed_label = Label.new()
	_speed_label.add_theme_font_size_override("font_size", 40)
	_speed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_speed_label.add_theme_constant_override("outline_size", 8)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_speed_label, 0.5, 1, 0.5, 1, -150, -90, 150, -30)
	_speed_label.visible = false
	_root.add_child(_speed_label)

	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_fps_label, 0, 0, 0, 0, 340, 14, 460, 40)
	_root.add_child(_fps_label)

func _build_menu() -> void:
	_menu_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.96)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(18)
	sb.border_color = Color(0.45, 0.6, 0.95)
	sb.set_border_width_all(3)
	_menu_panel.add_theme_stylebox_override("panel", sb)
	_place(_menu_panel, 0.5, 0.5, 0.5, 0.5, -380, -300, 380, 300)
	_menu_panel.visible = false
	_root.add_child(_menu_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_menu_panel.add_child(vb)
	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 32)
	_menu_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(_menu_title)
	_menu_body = Label.new()
	_menu_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_body.custom_minimum_size = Vector2(700, 0)
	vb.add_child(_menu_body)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	_menu_options = VBoxContainer.new()
	_menu_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_options.add_theme_constant_override("separation", 8)
	sc.add_child(_menu_options)
	var close := Button.new()
	close.text = "Close"
	_style_button(close, Color(0.55, 0.2, 0.2))
	close.custom_minimum_size = Vector2(0, 58)
	close.pressed.connect(close_menu)
	vb.add_child(close)

# ---------------- Public API ----------------
func open_menu(title: String, body: String, options: Array) -> void:
	menu_open = true
	GameState.paused_time = true
	stick.value = Vector2.ZERO
	_menu_title.text = title
	_menu_body.text = body
	_menu_body.visible = body != ""
	for c in _menu_options.get_children():
		c.queue_free()
	for o in options:
		var b := Button.new()
		b.text = str(o.get("label", "?"))
		b.custom_minimum_size = Vector2(0, 58)
		b.disabled = bool(o.get("disabled", false))
		_style_button(b)
		var cb: Callable = o.get("call", Callable())
		b.pressed.connect(func(): _on_option(cb))
		_menu_options.add_child(b)
	_menu_panel.visible = true

func _style_button(b: Button, base: Color = Color(0.2, 0.34, 0.62)) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(10)
		var c := base
		if st == "pressed":
			c = base.lightened(0.3)
		elif st == "hover":
			c = base.lightened(0.12)
		elif st == "disabled":
			c = Color(0.18, 0.19, 0.22)
		sb.bg_color = c
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.55))

func _on_option(cb: Callable) -> void:
	close_menu()
	if cb.is_valid():
		cb.call()

func close_menu() -> void:
	menu_open = false
	GameState.paused_time = false
	_menu_panel.visible = false

func notify(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notes.add_child(l)
	while _notes.get_child_count() > 4:
		_notes.get_child(0).queue_free()
		_notes.remove_child(_notes.get_child(0))
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())

func blink() -> void:
	# Quick fade to black and back, used when sleeping.
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	tw.tween_interval(0.5)
	tw.tween_property(fade, "color:a", 0.0, 0.6)
	tw.tween_callback(fade.queue_free)

func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""

func set_driving(on: bool, speed_kmh: float = 0.0) -> void:
	_speed_label.visible = on
	_jump_btn.visible = not on
	_run_btn.visible = not on
	if on:
		_speed_label.text = "%d km/h" % int(speed_kmh)

func set_gps(active: bool, angle: float = 0.0, text: String = "") -> void:
	_arrow.active = active
	_arrow.angle = angle
	_arrow.text = text
	_arrow.queue_redraw()

func refresh() -> void:
	_money_label.text = "$ %s" % _commas(GameState.money)
	_time_label.text = "Day %d  %s  |  Age %d" % [GameState.day, GameState.time_string(), GameState.age]
	_job_label.text = "Job: %s" % (GD_job_name(GameState.job_id))
	_bars["health"].value = GameState.health
	_bars["energy"].value = GameState.energy
	_bars["hunger"].value = GameState.hunger

func GD_job_name(id: String) -> String:
	if id == "":
		return "Unemployed"
	var GD = preload("res://scripts/game_data.gd")
	return GD.JOBS[id]["name"]

func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

func _toggle_run() -> void:
	run_on = not run_on
	_run_btn.tint = Color(0.2, 0.9, 0.3) if run_on else Color(0.95, 0.6, 0.2)
	_run_btn.set_label("WALK" if run_on else "RUN")

func _process(_delta: float) -> void:
	_fps_label.visible = bool(GameState.settings.get("show_fps", false))
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	# Refresh clock every frame (cheap).
	_time_label.text = "Day %d  %s  |  Age %d" % [GameState.day, GameState.time_string(), GameState.age]
	_bars["health"].value = GameState.health
	_bars["energy"].value = GameState.energy
	_bars["hunger"].value = GameState.hunger
