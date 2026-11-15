extends RefCounted
# Custom multi-touch controls. Use with:
#   const TC = preload("res://scripts/touch_controls.gd")
#   var stick = TC.Joystick.new()

class Joystick extends Control:
	var value := Vector2.ZERO   # x = right, y = forward (both -1..1)
	var radius := 90.0
	var _touch := -1
	var _knob := Vector2.ZERO

	func _init() -> void:
		custom_minimum_size = Vector2(260, 260)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed and _touch == -1:
				_touch = event.index
				_update(event.position)
			elif not event.pressed and event.index == _touch:
				_release()
		elif event is InputEventScreenDrag and event.index == _touch:
			_update(event.position)

	func _update(pos: Vector2) -> void:
		var offset := pos - size * 0.5
		if offset.length() > radius:
			offset = offset.normalized() * radius
		_knob = offset
		value = Vector2(offset.x / radius, -offset.y / radius)
		queue_redraw()

	func _release() -> void:
		_touch = -1
		_knob = Vector2.ZERO
		value = Vector2.ZERO
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, radius + 14.0, Color(1, 1, 1, 0.10))
		draw_arc(c, radius + 14.0, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		draw_circle(c + _knob, 42.0, Color(1, 1, 1, 0.40))
		draw_arc(c + _knob, 42.0, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 3.0)

class TButton extends Control:
	signal pressed
	signal released
	var label := ""
	var held := false
	var tint := Color(1, 1, 1)
	var font_size := 24
	var _touch := -1

	func _init(text_in: String = "", diameter: float = 110.0) -> void:
		label = text_in
		custom_minimum_size = Vector2(diameter, diameter)
		size = Vector2(diameter, diameter)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed and _touch == -1:
				_touch = event.index
				held = true
				queue_redraw()
				pressed.emit()
			elif not event.pressed and event.index == _touch:
				_touch = -1
				held = false
				queue_redraw()
				released.emit()

	func set_label(t: String) -> void:
		label = t
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r: float = min(size.x, size.y) * 0.5 - 4.0
		var a := 0.55 if held else 0.28
		draw_circle(c, r, Color(tint.r, tint.g, tint.b, a))
		draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.75), 3.0)
		var font := ThemeDB.fallback_font
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + ts.y * 0.28), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))

class LookPad extends Control:
	signal dragged(delta: Vector2)
	var _touch := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed and _touch == -1:
				_touch = event.index
			elif not event.pressed and event.index == _touch:
				_touch = -1
		elif event is InputEventScreenDrag and event.index == _touch:
			dragged.emit(event.relative)

class Arrow extends Control:
	# Small GPS arrow. Set angle (radians, 0 = up) and text.
	var angle := 0.0
	var text := ""
	var active := false

	func _init() -> void:
		custom_minimum_size = Vector2(120, 90)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if not active:
			return
		var c := Vector2(size.x * 0.5, 34.0)
		var pts := PackedVector2Array([Vector2(0, -26), Vector2(18, 20), Vector2(0, 10), Vector2(-18, 20)])
		var rot := PackedVector2Array()
		for p in pts:
			rot.append(c + p.rotated(angle))
		draw_colored_polygon(rot, Color(1.0, 0.82, 0.2, 0.95))
		var font := ThemeDB.fallback_font
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(font, Vector2(size.x * 0.5 - ts.x * 0.5, 82.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.95))
