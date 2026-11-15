extends CharacterBody3D
# The player: walking, jumping, first/third person camera, interaction, driving.

signal interacted(target)

const HumanModel = preload("res://scripts/human_model.gd")

const WALK_SPEED := 4.6
const RUN_SPEED := 8.0
const JUMP_SPEED := 6.5
const GRAVITY := 22.0

var hud
var yaw := 0.0
var pitch := -0.2
var first_person := false
var in_car = null
var target = null
var input_enabled := true

var _yaw_node: Node3D
var _pitch_node: Node3D
var _arm: SpringArm3D
var _cam: Camera3D
var _model: Node3D
var _jump_queued := false
var _anim_t := 0.0
var _scan_t := 0.0
var _look_idle := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.4

	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)

	_model = HumanModel.build(Color("#d9a27a"), Color("#2e6fd6"), Color("#2b2f3a"), Color("#2a1b12"), false)
	add_child(_model)

	_yaw_node = Node3D.new()
	_yaw_node.position = Vector3(0, 1.6, 0)
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_yaw_node.add_child(_pitch_node)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	_arm.margin = 0.3
	_pitch_node.add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.1
	_cam.far = 500.0
	_arm.add_child(_cam)
	_cam.current = true
	set_first_person(GameState.settings.get("camera_mode", "third") == "first")

func connect_hud(h) -> void:
	hud = h
	hud.look.connect(_on_look)
	hud.jump_pressed.connect(func(): _jump_queued = true)
	hud.camera_pressed.connect(toggle_camera)
	hud.action_pressed.connect(interact)

func get_camera() -> Camera3D:
	return _cam

func _on_look(d: Vector2) -> void:
	if hud != null and hud.menu_open:
		return
	var s: float = float(GameState.settings.get("look_sensitivity", 1.0)) * 0.0045
	yaw -= d.x * s
	pitch = clamp(pitch - d.y * s, -1.2, 0.9)
	_look_idle = 0.0

func toggle_camera() -> void:
	set_first_person(not first_person)
	GameState.settings["camera_mode"] = "first" if first_person else "third"
	GameState.save_settings()
	GameState.notify("Camera: %s person" % ("First" if first_person else "Third"))

func set_first_person(on: bool) -> void:
	first_person = on
	if on:
		_arm.spring_length = 0.0
		_cam.h_offset = 0.0
		_yaw_node.position = Vector3(0, 1.68, 0)
	else:
		_arm.spring_length = 4.2
		_cam.h_offset = 0.35
		_yaw_node.position = Vector3(0, 1.55, 0)
	_model.visible = (not on) and in_car == null

func _key_vector() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	return v

func input_vector() -> Vector2:
	var v := _key_vector()
	if hud != null:
		v += hud.stick.value
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_jump_queued = true
		elif event.keycode == KEY_E or event.keycode == KEY_ENTER:
			interact()
		elif event.keycode == KEY_C:
			toggle_camera()

func _physics_process(delta: float) -> void:
	_look_idle += delta
	_yaw_node.rotation.y = yaw
	_pitch_node.rotation.x = pitch
	if in_car != null:
		_follow_car(delta)
		return

	var active: bool = input_enabled and (hud == null or not hud.menu_open)
	var mv := input_vector() if active else Vector2.ZERO
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := fwd * mv.y + right * mv.x
	var running: bool = (hud != null and hud.run_on) or Input.is_key_pressed(KEY_SHIFT)
	var speed := RUN_SPEED if running else WALK_SPEED
	if GameState.energy <= 0.0:
		speed *= 0.5
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		if _jump_queued and active:
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	_jump_queued = false
	move_and_slide()

	# Face movement direction and animate.
	var moving := dir.length() > 0.05
	if moving:
		var target_rot := atan2(-dir.x, -dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_rot, min(1.0, delta * 12.0))
		_anim_t += delta * (11.0 if running else 8.0)
	HumanModel.animate(_model, _anim_t, (1.0 if moving else 0.0))

	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.12
		_scan_interactables()

func _scan_interactables() -> void:
	var best = null
	var best_d := 1e9
	var p := global_position
	for n in get_tree().get_nodes_in_group("interactable"):
		var q: Vector3 = n.interact_point()
		var d := Vector2(p.x - q.x, p.z - q.z).length()
		if d <= float(n.radius) and d < best_d and absf(p.y - q.y) < 6.0:
			best = n
			best_d = d
	target = best
	if hud != null:
		hud.set_prompt(("[ACT] " + str(best.prompt_text())) if best != null else "")

func interact() -> void:
	if hud != null and hud.menu_open:
		return
	if in_car != null:
		in_car.exit_car()
		return
	if target != null and is_instance_valid(target):
		interacted.emit(target)

# ---------------- Driving ----------------
func enter_car(car) -> void:
	in_car = car
	car.driver = self
	_model.visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_arm.spring_length = 7.5
	_cam.h_offset = 0.0
	_yaw_node.position = Vector3(0, 2.2, 0)
	pitch = -0.25
	if hud != null:
		hud.set_prompt("")
		hud.set_driving(true, 0.0)

func exit_car_to(pos: Vector3) -> void:
	in_car = null
	global_position = pos
	collision_layer = 2
	collision_mask = 1 | 4
	velocity = Vector3.ZERO
	set_first_person(first_person)
	if hud != null:
		hud.set_driving(false)

func _follow_car(delta: float) -> void:
	global_position = in_car.global_position + Vector3(0, 0.4, 0)
	if _look_idle > 1.5:
		yaw = lerp_angle(yaw, in_car.rotation.y, min(1.0, delta * 2.5))
	if hud != null:
		hud.set_driving(true, absf(in_car.speed) * 3.6)

func teleport(pos: Vector3, new_yaw: float = 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = new_yaw
