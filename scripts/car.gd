extends CharacterBody3D
# A drivable car with simple arcade physics. Controls come from the player's
# joystick: up = gas, down = brake/reverse, left/right = steer.

const GD = preload("res://scripts/game_data.gd")

const DIMS := {
	"hatch": Vector3(1.7, 1.4, 3.7),
	"sedan": Vector3(1.8, 1.45, 4.5),
	"suv": Vector3(1.95, 1.8, 4.7),
	"sports": Vector3(1.9, 1.22, 4.4),
}

var kind := "car"
var model_id := "hatch"
var color := Color("#c0392b")
var owned_index := -1
var driver = null
var speed := 0.0
var max_speed := 20.0
var radius := 4.5
var title := "Car"

var _wheels: Array = []

static func build_model(mid: String, col: Color) -> Node3D:
	var dims: Vector3 = DIMS.get(mid, DIMS["hatch"])
	var w := dims.x
	var h := dims.y
	var l := dims.z
	var root := Node3D.new()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = col
	body_mat.metallic = 0.3
	body_mat.roughness = 0.3
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.08, 0.12, 0.18)
	glass.metallic = 0.5
	glass.roughness = 0.08
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.05, 0.06)
	black.roughness = 0.9
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1, 0.95, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.9, 0.6)
	lamp.emission_energy_multiplier = 1.5
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.8, 0.05, 0.05)
	tail.emission_enabled = true
	tail.emission = Color(1, 0.05, 0.05)
	tail.emission_energy_multiplier = 1.2

	var lower := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(w, 0.58, l)
	lower.mesh = lm
	lower.material_override = body_mat
	lower.position = Vector3(0, 0.56, 0)
	root.add_child(lower)

	var cab_h := h - 0.85
	var cabin := MeshInstance3D.new()
	var cm := BoxMesh.new()
	var cab_len := l * (0.62 if mid == "suv" else 0.5)
	cm.size = Vector3(w * 0.88, cab_h, cab_len)
	cabin.mesh = cm
	cabin.material_override = glass
	cabin.position = Vector3(0, 0.85 + cab_h * 0.5, l * 0.08)
	root.add_child(cabin)

	var roof := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(w * 0.9, 0.06, cab_len * 0.92)
	roof.mesh = rm
	roof.material_override = body_mat
	roof.position = Vector3(0, 0.85 + cab_h, l * 0.08)
	root.add_child(roof)

	for sx in [-1, 1]:
		var hl := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(0.3, 0.14, 0.06)
		hl.mesh = hm
		hl.material_override = lamp
		hl.position = Vector3(sx * (w * 0.5 - 0.3), 0.68, -l * 0.5 - 0.01)
		root.add_child(hl)
		var tl := MeshInstance3D.new()
		tl.mesh = hm
		tl.material_override = tail
		tl.position = Vector3(sx * (w * 0.5 - 0.3), 0.68, l * 0.5 + 0.01)
		root.add_child(tl)

	for sx in [-1, 1]:
		for sz in [-1, 1]:
			var wheel := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.34
			cyl.bottom_radius = 0.34
			cyl.height = 0.26
			cyl.radial_segments = 14
			wheel.mesh = cyl
			wheel.material_override = black
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(sx * (w * 0.5 - 0.08), 0.34, sz * (l * 0.5 - 0.8))
			wheel.name = "wheel"
			root.add_child(wheel)
	return root

func setup(mid: String, col: Color, idx: int) -> void:
	model_id = mid
	color = col
	owned_index = idx
	title = "Drive " + str(GD.CARS[mid]["name"])
	max_speed = float(GD.CARS[mid]["speed"])

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.5
	var dims: Vector3 = DIMS.get(model_id, DIMS["hatch"])
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(dims.x, 1.0, dims.z)
	cs.shape = bs
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)
	var model := build_model(model_id, color)
	add_child(model)
	for c in model.get_children():
		if c.name.begins_with("wheel"):
			_wheels.append(c)

func interact_point() -> Vector3:
	return global_position

func prompt_text() -> String:
	return title

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	if driver != null:
		var v: Vector2 = driver.input_vector()
		throttle = v.y
		steer = v.x
	if throttle > 0.05:
		speed = min(speed + throttle * (max_speed * 0.6) * delta, max_speed)
	elif throttle < -0.05:
		if speed > 0.5:
			speed = max(speed - 32.0 * delta, 0.0)
		else:
			speed = max(speed + throttle * 9.0 * delta, -9.0)
	else:
		speed = move_toward(speed, 0.0, 7.0 * delta)

	if absf(speed) > 0.2:
		var rate: float = lerp(1.9, 0.75, clamp(absf(speed) / max_speed, 0.0, 1.0))
		var grip: float = clamp(absf(speed) / 4.0, 0.0, 1.0)
		rotation.y -= steer * rate * delta * grip * signf(speed)

	var fwd := -global_transform.basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 22.0 * delta
	move_and_slide()
	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		if col.get_normal().y < 0.5:
			speed *= 0.35
			break
	for wh in _wheels:
		wh.rotation.x += speed * delta / 0.34

func exit_car() -> void:
	if driver == null:
		return
	var right := global_transform.basis.x
	var pos := global_position + right * 2.4 + Vector3(0, 0.3, 0)
	var d = driver
	driver = null
	speed = 0.0
	d.exit_car_to(pos)
