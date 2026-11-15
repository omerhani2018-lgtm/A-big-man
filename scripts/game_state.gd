extends Node
# Global game data: player stats, time, money, ownership, relationships,
# settings and the save system. Registered as the autoload "GameState".

signal changed
signal message(text: String)
signal new_day(day: int)
signal collapsed

const SAVE_PATH := "user://a_big_man_save.json"
const SETTINGS_PATH := "user://a_big_man_settings.json"
const SECONDS_PER_GAME_HOUR := 30.0
const RENT_PER_DAY := 50
const PARENTS_HOME_DAYS := 7

# ---------------- Settings ----------------
var settings := {
	"camera_mode": "third",
	"look_sensitivity": 1.0,
	"volume": 0.8,
	"shadows": true,
	"show_fps": false,
}

# ---------------- Player ----------------
var started := false
var player_name := "Alex"
var age := 18
var money := 1000
var day := 1
var hour := 8.0
var energy := 100.0
var hunger := 100.0
var health := 100.0
var fitness := 0
var job_id := ""
var shifts := {}            # job_id -> number of shifts worked
var total_shifts := 0
var owned_houses: Array = []  # house ids
var owned_cars: Array = []    # dicts: model, color, x, y, z, yaw
var rented_apartment := false
var relationships := {}     # npc_id -> 0..100
var talked_today := {}      # npc_id -> true
var partner_id := ""
var married := false
var children: Array = []
var player_pos: Array = []  # [x, y, z, yaw]
var flags := {}
var paused_time := false

func _ready() -> void:
	load_settings()
	apply_settings()

# ---------------- Time and needs ----------------
func tick(delta: float) -> void:
	if not started or paused_time:
		return
	advance_time(delta / SECONDS_PER_GAME_HOUR)

func advance_time(hours: float) -> void:
	# Advance in small steps so day changes and needs behave correctly.
	var left := hours
	while left > 0.0:
		var step: float = min(left, 0.25)
		left -= step
		hour += step
		hunger = clamp(hunger - 3.0 * step, 0.0, 100.0)
		energy = clamp(energy - 3.5 * step, 0.0, 100.0)
		if hunger <= 0.0 or energy <= 0.0:
			health = clamp(health - 3.0 * step, 0.0, 100.0)
		elif hunger > 40.0 and energy > 30.0:
			health = clamp(health + 0.6 * step, 0.0, 100.0)
		if hour >= 24.0:
			hour -= 24.0
			_start_new_day()
		if health <= 0.0:
			collapse()
			return
	changed.emit()

func _start_new_day() -> void:
	day += 1
	talked_today.clear()
	if day % 60 == 0:
		age += 1
		notify("Happy birthday! You are now %d years old." % age)
	if rented_apartment:
		if money >= RENT_PER_DAY:
			money -= RENT_PER_DAY
			notify("Rent paid: $%d" % RENT_PER_DAY)
		else:
			rented_apartment = false
			notify("You could not pay rent and lost your apartment!")
	if day == PARENTS_HOME_DAYS + 1 and not has_home():
		notify("Your parents say it is time to move out. Find a place to live!")
	new_day.emit(day)

func collapse() -> void:
	# Player ran out of health: hospital visit.
	var fee: int = min(money, 200)
	money -= fee
	health = 50.0
	energy = 50.0
	hunger = 50.0
	hour = fmod(hour + 6.0, 24.0)
	notify("You collapsed and woke up in hospital. Bill: $%d" % fee)
	collapsed.emit()
	changed.emit()

func time_string() -> String:
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, suffix]

func is_night() -> bool:
	return hour >= 20.0 or hour < 6.0

# ---------------- Money ----------------
func add_money(amount: int) -> void:
	money += amount
	changed.emit()

func spend(amount: int) -> bool:
	if money < amount:
		notify("Not enough money. You need $%d." % amount)
		return false
	money -= amount
	changed.emit()
	return true

func notify(text: String) -> void:
	message.emit(text)

# ---------------- Home ----------------
func can_sleep_at_parents() -> bool:
	return day <= PARENTS_HOME_DAYS

func has_home() -> bool:
	return rented_apartment or owned_houses.size() > 0

func sleep(hours: float) -> void:
	advance_time(hours)
	energy = clamp(energy + hours * 12.5, 0.0, 100.0)
	changed.emit()

# ---------------- Relationships ----------------
func rel(npc_id: String) -> int:
	return int(relationships.get(npc_id, 0))

func add_rel(npc_id: String, amount: int) -> void:
	relationships[npc_id] = clampi(rel(npc_id) + amount, 0, 100)
	changed.emit()

func friends_count() -> int:
	var n := 0
	for k in relationships.keys():
		if int(relationships[k]) >= 40:
			n += 1
	return n

# ---------------- Jobs ----------------
func job_shifts(id: String) -> int:
	return int(shifts.get(id, 0))

func record_shift(id: String) -> void:
	shifts[id] = job_shifts(id) + 1
	total_shifts += 1

# ---------------- New game / save / load ----------------
func new_game(name_in: String) -> void:
	started = true
	player_name = name_in if name_in.strip_edges() != "" else "Alex"
	age = 18
	money = 1000
	day = 1
	hour = 8.0
	energy = 100.0
	hunger = 80.0
	health = 100.0
	fitness = 0
	job_id = ""
	shifts = {}
	total_shifts = 0
	owned_houses = []
	owned_cars = []
	rented_apartment = false
	relationships = {}
	talked_today = {}
	partner_id = ""
	married = false
	children = []
	player_pos = []
	flags = {}

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"player_name": player_name, "age": age, "money": money,
		"day": day, "hour": hour, "energy": energy, "hunger": hunger,
		"health": health, "fitness": fitness, "job_id": job_id,
		"shifts": shifts, "total_shifts": total_shifts,
		"owned_houses": owned_houses, "owned_cars": owned_cars,
		"rented_apartment": rented_apartment,
		"relationships": relationships, "partner_id": partner_id,
		"married": married, "children": children,
		"player_pos": player_pos, "flags": flags,
	}

func from_dict(d: Dictionary) -> void:
	started = true
	player_name = str(d.get("player_name", "Alex"))
	age = int(d.get("age", 18))
	money = int(d.get("money", 0))
	day = int(d.get("day", 1))
	hour = float(d.get("hour", 8.0))
	energy = float(d.get("energy", 100.0))
	hunger = float(d.get("hunger", 100.0))
	health = float(d.get("health", 100.0))
	fitness = int(d.get("fitness", 0))
	job_id = str(d.get("job_id", ""))
	shifts = d.get("shifts", {})
	total_shifts = int(d.get("total_shifts", 0))
	owned_houses = d.get("owned_houses", [])
	owned_cars = d.get("owned_cars", [])
	rented_apartment = bool(d.get("rented_apartment", false))
	relationships = d.get("relationships", {})
	partner_id = str(d.get("partner_id", ""))
	married = bool(d.get("married", false))
	children = d.get("children", [])
	player_pos = d.get("player_pos", [])
	flags = d.get("flags", {})
	talked_today = {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		notify("Could not save the game.")
		return false
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	notify("Game saved.")
	return true

func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	from_dict(data)
	return true

func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# ---------------- Settings ----------------
func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
		f.close()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		for k in data.keys():
			settings[k] = data[k]

func apply_settings() -> void:
	var v: float = clamp(float(settings.get("volume", 0.8)), 0.0001, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(v))
