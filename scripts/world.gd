extends Node3D
# The game world: builds the city, spawns the player, NPCs, cars and traffic,
# runs day/night lighting, GPS and saving.

const GD = preload("res://scripts/game_data.gd")
const CityBuilder = preload("res://scripts/city_builder.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HudScript = preload("res://scripts/hud.gd")
const NpcScript = preload("res://scripts/npc.gd")
const CarScript = preload("res://scripts/car.gd")
const TrafficScript = preload("res://scripts/traffic.gd")
const LogicScript = preload("res://scripts/places_logic.gd")

var city
var hud
var player
var logic
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var gps_target := ""
var npcs := {}
var owned_car_nodes := {}
var _autosave_t := 0.0

func _ready() -> void:
	_setup_environment()
	city = CityBuilder.new()
	city.build(self)

	hud = HudScript.new()
	add_child(hud)

	player = PlayerScript.new()
	add_child(player)
	player.connect_hud(hud)
	var start: Vector3 = city.spawn_pos
	if GameState.player_pos.size() >= 4:
		start = Vector3(GameState.player_pos[0], GameState.player_pos[1] + 0.3, GameState.player_pos[2])
		player.teleport(start, float(GameState.player_pos[3]))
	else:
		player.teleport(start + Vector3(0, 0.3, 0), 0.0)

	logic = LogicScript.new()
	logic.setup(self)
	player.interacted.connect(func(t): logic.handle(t))
	hud.phone_pressed.connect(func():
		if not hud.menu_open:
			logic.phone_menu())

	_spawn_npcs()
	_spawn_traffic()
	for i in range(GameState.owned_cars.size()):
		spawn_owned_car(i)
	refresh_house_signs()
	apply_quality()
	_update_lighting()
	GameState.new_day.connect(func(_d): save(true))
	if GameState.day == 1 and GameState.hour < 9.0 and GameState.total_shifts == 0:
		GameState.notify("You are 18! Start your independent life.")
		GameState.notify("Find a job, earn money, and get your own home within a week.")

func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0015
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func apply_quality() -> void:
	var q := int(GameState.settings.get("quality", 1))
	sun.shadow_enabled = bool(GameState.settings.get("shadows", true)) and q > 0
	sun.directional_shadow_max_distance = [60.0, 100.0, 150.0][q]
	var vp := get_viewport()
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][q]
	if player != null:
		player.get_camera().far = [220.0, 360.0, 520.0][q]

# ---------------- Day / night ----------------
func _daylight() -> float:
	var h := GameState.hour
	# 0 at night, 1 at midday, smooth dawn 5-7 and dusk 18-20
	if h < 5.0 or h > 20.0:
		return 0.0
	if h < 7.0:
		return (h - 5.0) / 2.0
	if h > 18.0:
		return (20.0 - h) / 2.0
	return 1.0

func _update_lighting() -> void:
	var d := _daylight()
	var h := GameState.hour
	var angle := ((h - 6.0) / 12.0) * PI   # sun travels across the sky from 6 to 18
	sun.rotation = Vector3(-clamp(sin(angle), 0.05, 1.0) * 1.2, deg_to_rad(40.0), 0.0)
	sun.light_energy = lerp(0.05, 0.75, d)
	var warm: float = 1.0 - abs(d - 0.5) * 2.0
	sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.7, 0.45), warm * (1.0 if d < 1.0 else 0.0))
	sky_mat.sky_top_color = Color(0.03, 0.04, 0.1).lerp(Color(0.25, 0.5, 0.88), d)
	sky_mat.sky_horizon_color = Color(0.06, 0.07, 0.14).lerp(Color(0.68, 0.8, 0.92), d)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = Color(0.03, 0.04, 0.05).lerp(Color(0.3, 0.35, 0.3), d)
	env.ambient_light_energy = lerp(0.25, 0.55, d)
	env.fog_light_color = sky_mat.sky_horizon_color
	city.set_night(1.0 - d)

# ---------------- Spawning ----------------
func _spawn_npcs() -> void:
	var i := 0
	for d in GD.NPCS:
		var n = NpcScript.new()
		var block: Vector3
		if str(d["kind"]) == "family":
			block = Vector3.ZERO
			n.setup(d, block, 0)
			var pp: Dictionary = city.places["parents"]
			n.position = pp["pos"] + Vector3(2.5 * (1 if str(d["id"]) == "mom" else -1), 0.1, 3.0)
		else:
			var b: Array = d["block"]
			block = Vector3(float(b[0]) * CityBuilder.PITCH, 0, float(b[1]) * CityBuilder.PITCH)
			n.setup(d, block, i % 4)
		add_child(n)
		n.face(player)
		n.add_to_group("interactable")
		npcs[str(d["id"])] = n
		i += 1

func _spawn_traffic() -> void:
	var models := ["hatch", "sedan", "suv", "sports"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var count := 0
	for r in range(-4, 4):
		var center: float = (float(r) + 0.5) * CityBuilder.PITCH
		for k in range(2):
			for horizontal in [true, false]:
				var t = TrafficScript.new()
				var dir: float = 1.0 if k == 0 else -1.0
				var lane: float = 4.2 * dir * (1.0 if horizontal else -1.0)
				t.setup(models[rng.randi() % 4], Color(GD.CAR_COLORS[rng.randi() % GD.CAR_COLORS.size()]),
					center, lane, rng.randf_range(-300.0, 300.0), horizontal, dir, rng.randf_range(7.0, 12.0), 335.0)
				add_child(t)
				count += 1

func spawn_owned_car(index: int) -> void:
	var data: Dictionary = GameState.owned_cars[index]
	var c = CarScript.new()
	c.setup(str(data["model"]), Color(str(data["color"])), index)
	add_child(c)
	c.position = Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
	c.rotation.y = float(data.get("yaw", 0.0))
	c.add_to_group("interactable")
	owned_car_nodes[index] = c

func refresh_house_signs() -> void:
	for id in city.house_signs.keys():
		var lbl: Label3D = city.house_signs[id]
		var h: Dictionary = GD.HOUSES.get(id, {})
		if GameState.owned_houses.has(id):
			lbl.text = "%s (YOURS)" % h.get("name", id)
			lbl.modulate = Color(0.4, 1.0, 0.4)
		else:
			lbl.text = "%s  $%d" % [h.get("name", id), int(h.get("price", 0))]

func npc_name(id: String) -> String:
	return str(GD.npc_by_id(id).get("name", id))

# ---------------- Saving ----------------
func _sync_save_data() -> void:
	if player.in_car != null:
		GameState.player_pos = [player.in_car.global_position.x, 0.5, player.in_car.global_position.z, player.yaw]
	else:
		GameState.player_pos = [player.global_position.x, player.global_position.y, player.global_position.z, player.yaw]
	for idx in owned_car_nodes.keys():
		var c = owned_car_nodes[idx]
		if is_instance_valid(c) and idx < GameState.owned_cars.size():
			var d: Dictionary = GameState.owned_cars[idx]
			d["x"] = c.global_position.x
			d["y"] = c.global_position.y
			d["z"] = c.global_position.z
			d["yaw"] = c.rotation.y

func save(silent: bool) -> void:
	_sync_save_data()
	var ok := GameState.save_game()
	if silent and ok:
		pass

func quit_to_menu() -> void:
	save(true)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ---------------- Per-frame ----------------
func _process(delta: float) -> void:
	GameState.tick(delta)
	_update_lighting_throttled(delta)
	_update_gps()
	_autosave_t += delta
	if _autosave_t > 90.0:
		_autosave_t = 0.0
		save(true)

var _light_t := 0.0
func _update_lighting_throttled(delta: float) -> void:
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.5
		_update_lighting()

func _update_gps() -> void:
	if gps_target == "" or not city.places.has(gps_target):
		hud.set_gps(false)
		return
	var tp: Vector3 = city.places[gps_target]["pos"]
	var pp: Vector3 = player.global_position
	var to := tp - pp
	var dist := Vector2(to.x, to.z).length()
	if dist < 6.0:
		hud.set_gps(false)
		GameState.notify("You have arrived.")
		gps_target = ""
		return
	# Angle of destination relative to where the camera looks.
	var cam_yaw: float = player.yaw
	var world_ang := atan2(-to.x, -to.z)
	hud.set_gps(true, wrapf(world_ang - cam_yaw, -PI, PI) * -1.0, "%s  %dm" % [city.places[gps_target]["name"], int(dist)])
