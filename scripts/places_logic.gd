extends RefCounted
# All the "what happens when I interact" logic: shops, jobs, homes, cars,
# NPC conversations, phone menu and in-game settings.

const GD = preload("res://scripts/game_data.gd")

var world
var hud
var player

func setup(w) -> void:
	world = w
	hud = w.hud
	player = w.player

func handle(target) -> void:
	match str(target.kind):
		"npc":
			talk_menu(target)
		"car":
			player.enter_car(target)
		"house":
			house_menu(str(target.id))
		"job", "shop", "decor":
			place_menu(str(target.id))

func money(n: int) -> String:
	return "$" + str(n)

# =====================================================================
# Places (shops, jobs, services)
# =====================================================================
func place_menu(id: String) -> void:
	var title: String = str(world.city.places[id]["name"])
	var opts: Array = []
	var body := ""
	match id:
		"corner_shop":
			body = "Fresh groceries and snacks. They are also hiring cashiers."
			opts += _food_options(["coffee", "groceries"], id)
		"burger":
			body = "Hot burgers and steaks. Hunger sorted!"
			opts += _food_options(["coffee", "burger", "steak"], id)
		"cafe":
			body = "A cozy cafe with the best coffee in town."
			opts += _food_options(["coffee"], id)
			opts.append({"label": "Sit and relax (1 hour, +10 energy)", "call": func(): _relax()})
		"gym":
			body = "Train to build your fitness. Costs $15 and 2 hours."
			opts.append({"label": "Workout ($15)", "call": func(): _workout()})
		"dealer":
			body = "Premier Motors. Pick a car and drive it away today."
			opts += _car_list_options()
		"realestate":
			body = "Find your dream home. Pick one to set your GPS to it, then visit it to buy."
			opts += _house_list_options()
		"apartment":
			_apartment_menu()
			return
		"hospital":
			body = "Health: %d / 100" % int(GameState.health)
			opts.append({"label": "Treatment and check-up ($60)", "call": func(): _heal()})
		"bank":
			body = "The bank is closed for renovation. Loans and savings are planned for a future update."
		_:
			pass
	# Jobs available at this place
	for jid in GD.JOBS.keys():
		var j: Dictionary = GD.JOBS[jid]
		if str(j["place"]) != id:
			continue
		opts += _job_options(str(jid))
	hud.open_menu(title, body, opts)

# ---------------- Food and small services ----------------
func _food_options(ids: Array, place_id: String) -> Array:
	var out: Array = []
	for f in GD.FOOD:
		if not ids.has(f["id"]):
			continue
		var fd: Dictionary = f
		out.append({"label": "%s  (%s)" % [fd["name"], money(int(fd["price"]))], "call": func(): _buy_food(fd, place_id)})
	return out

func _buy_food(f: Dictionary, place_id: String) -> void:
	if GameState.hunger >= 98.0 and int(f["energy"]) == 0:
		GameState.notify("You are not hungry right now.")
		place_menu(place_id)
		return
	if GameState.spend(int(f["price"])):
		GameState.hunger = clamp(GameState.hunger + float(f["hunger"]), 0.0, 100.0)
		GameState.energy = clamp(GameState.energy + float(f["energy"]), 0.0, 100.0)
		GameState.advance_time(0.4)
		GameState.notify("Yum! +%d food" % int(f["hunger"]))
	place_menu(place_id)

func _relax() -> void:
	GameState.advance_time(1.0)
	GameState.energy = clamp(GameState.energy + 10.0, 0.0, 100.0)
	GameState.notify("You relaxed for an hour.")
	place_menu("cafe")

func _workout() -> void:
	if GameState.energy < 25.0:
		GameState.notify("You are too tired to work out.")
	elif GameState.spend(15):
		GameState.advance_time(2.0)
		GameState.energy = clamp(GameState.energy - 15.0, 0.0, 100.0)
		GameState.health = clamp(GameState.health + 5.0, 0.0, 100.0)
		GameState.fitness += 1
		GameState.notify("Great workout! Fitness is now %d." % GameState.fitness)
	place_menu("gym")

func _heal() -> void:
	if GameState.spend(60):
		GameState.health = 100.0
		GameState.advance_time(1.0)
		GameState.notify("The doctor patched you up. Health restored.")
	place_menu("hospital")

# ---------------- Jobs ----------------
func _job_options(jid: String) -> Array:
	var j: Dictionary = GD.JOBS[jid]
	var out: Array = []
	if GameState.job_id == jid:
		var pay := job_pay(jid)
		out.append({"label": "Work a shift: %dh, +%s" % [int(j["hours"]), money(pay)], "call": func(): _work(jid)})
		out.append({"label": "Quit this job", "call": func(): _quit(jid)})
	else:
		var need: int = int(j["need_shifts"])
		var locked: bool = GameState.total_shifts < need
		var label := "Apply: %s (%s per shift)" % [j["name"], money(int(j["pay"]))]
		if locked:
			label += "  [needs %d shifts]" % need
		out.append({"label": label, "disabled": locked, "call": func(): _apply(jid)})
	return out

func job_pay(jid: String) -> int:
	var j: Dictionary = GD.JOBS[jid]
	var bonus: float = min(0.5, 0.02 * float(GameState.job_shifts(jid)))
	return int(round(float(j["pay"]) * (1.0 + bonus)))

func _apply(jid: String) -> void:
	var j: Dictionary = GD.JOBS[jid]
	GameState.job_id = jid
	GameState.changed.emit()
	GameState.notify("You are hired as %s!" % j["name"])
	place_menu(str(j["place"]))

func _quit(jid: String) -> void:
	var j: Dictionary = GD.JOBS[jid]
	GameState.job_id = ""
	GameState.changed.emit()
	GameState.notify("You quit your job.")
	place_menu(str(j["place"]))

func _work(jid: String) -> void:
	var j: Dictionary = GD.JOBS[jid]
	if bool(j["needs_car"]) and GameState.owned_cars.is_empty():
		GameState.notify("You need your own car for this job.")
	elif GameState.energy < float(j["energy"]) + 5.0:
		GameState.notify("You are too tired. Sleep or drink coffee first.")
	elif GameState.hunger < 10.0:
		GameState.notify("You are too hungry to work. Eat something.")
	else:
		var pay := job_pay(jid)
		GameState.advance_time(float(j["hours"]))
		GameState.energy = clamp(GameState.energy - float(j["energy"]), 0.0, 100.0)
		GameState.add_money(pay)
		GameState.record_shift(jid)
		if jid == "construction":
			GameState.fitness += 1
		GameState.notify("Shift done! You earned %s. (%d shifts at this job)" % [money(pay), GameState.job_shifts(jid)])
	place_menu(str(j["place"]))

# ---------------- Cars ----------------
func _car_list_options() -> Array:
	var out: Array = []
	for mid in GD.CARS.keys():
		var c: Dictionary = GD.CARS[mid]
		var m: String = str(mid)
		out.append({"label": "%s  %s  (%s)" % [c["name"], money(int(c["price"])), c["desc"]], "call": func(): _pick_color(m)})
	return out

func _pick_color(mid: String) -> void:
	var c: Dictionary = GD.CARS[mid]
	if GameState.money < int(c["price"]):
		GameState.notify("You cannot afford the %s yet." % c["name"])
		place_menu("dealer")
		return
	var names := ["Red", "Blue", "Green", "Yellow", "White", "Black", "Orange", "Purple"]
	var opts: Array = []
	for i in range(GD.CAR_COLORS.size()):
		var hex: String = GD.CAR_COLORS[i]
		opts.append({"label": str(names[i]), "call": func(): _buy_car(mid, hex)})
	opts.append({"label": "Back", "call": func(): place_menu("dealer")})
	hud.open_menu("Choose a colour", "%s for %s" % [c["name"], money(int(c["price"]))], opts)

func _buy_car(mid: String, hex: String) -> void:
	var c: Dictionary = GD.CARS[mid]
	if not GameState.spend(int(c["price"])):
		return
	var pl: Dictionary = world.city.places["dealer"]
	var spawn: Vector3 = pl["pos"] + pl["out"] * 6.0 + Vector3(6.0, 0.6, 0.0)
	GameState.owned_cars.append({"model": mid, "color": hex, "x": spawn.x, "y": spawn.y, "z": spawn.z, "yaw": 0.0})
	world.spawn_owned_car(GameState.owned_cars.size() - 1)
	GameState.notify("Congratulations! Your new %s is parked outside the dealership." % c["name"])

# ---------------- Real estate and houses ----------------
func _house_list_options() -> Array:
	var out: Array = []
	for hid in GD.HOUSES.keys():
		var h: Dictionary = GD.HOUSES[hid]
		var hs: String = str(hid)
		var status := "YOURS" if GameState.owned_houses.has(hs) else money(int(h["price"]))
		out.append({"label": "%s - %s" % [h["name"], status], "call": func(): _show_house_info(hs)})
	return out

func _show_house_info(hid: String) -> void:
	var h: Dictionary = GD.HOUSES[hid]
	world.gps_target = hid
	GameState.notify("GPS set to %s. Follow the arrow!" % h["name"])
	place_menu("realestate")

func house_menu(id: String) -> void:
	if id == "parents":
		_parents_menu()
		return
	var h: Dictionary = GD.HOUSES[id]
	if GameState.owned_houses.has(id):
		var opts: Array = [
			{"label": "Sleep (8 hours)", "call": func(): _sleep(id)},
			{"label": "Cook and eat at home ($8)", "call": func(): _cook(id)},
			{"label": "Relax on the sofa (1 hour)", "call": func(): _sofa(id)},
			{"label": "Save game", "call": func(): world.save(false)},
		]
		hud.open_menu(str(h["name"]) + " (your home)", "Home sweet home. Sleep to restore your energy.", opts)
	else:
		var price: int = int(h["price"])
		var opts2: Array = [
			{"label": "Buy for %s" % money(price), "disabled": GameState.money < price, "call": func(): _buy_house(id)},
		]
		hud.open_menu(str(h["name"]) + " - FOR SALE", "%s\n\nPrice: %s\nYou have: %s" % [h["desc"], money(price), money(GameState.money)], opts2)

func _buy_house(id: String) -> void:
	var h: Dictionary = GD.HOUSES[id]
	if GameState.spend(int(h["price"])):
		GameState.owned_houses.append(id)
		world.refresh_house_signs()
		GameState.notify("You bought %s! Welcome home." % h["name"])
		house_menu(id)

func _sleep(id: String) -> void:
	GameState.sleep(8.0)
	hud.blink()
	GameState.notify("You slept well. Energy restored.")
	world.save(true)
	house_menu(id)

func _cook(id: String) -> void:
	if GameState.spend(8):
		GameState.hunger = clamp(GameState.hunger + 45.0, 0.0, 100.0)
		GameState.advance_time(0.5)
		GameState.notify("A home-cooked meal. Delicious!")
	house_menu(id)

func _sofa(id: String) -> void:
	GameState.advance_time(1.0)
	GameState.energy = clamp(GameState.energy + 6.0, 0.0, 100.0)
	house_menu(id)

func _parents_menu() -> void:
	var opts: Array = []
	if GameState.can_sleep_at_parents():
		var left := GameState.PARENTS_HOME_DAYS - GameState.day + 1
		opts.append({"label": "Sleep in your old room (8 hours)", "call": func(): _sleep_parents()})
		opts.append({"label": "Eat with the family (free)", "call": func(): _parents_eat()})
		hud.open_menu("Family Home", "You can stay here for %d more day(s). Then it is time to live on your own!" % left, opts)
	else:
		opts.append({"label": "Have dinner with the family (free)", "call": func(): _parents_eat()})
		hud.open_menu("Family Home", "Your parents are happy to see you, but you have your own life now. Find a home of your own!", opts)

func _sleep_parents() -> void:
	GameState.sleep(8.0)
	hud.blink()
	GameState.notify("You slept in your old room.")
	world.save(true)
	_parents_menu()

func _parents_eat() -> void:
	GameState.hunger = clamp(GameState.hunger + 50.0, 0.0, 100.0)
	GameState.advance_time(0.5)
	GameState.notify("Mom's cooking is the best.")
	_parents_menu()

func _apartment_menu() -> void:
	var opts: Array = []
	var body := ""
	if GameState.rented_apartment:
		body = "You rent a room here for $%d per day (paid every morning)." % GameState.RENT_PER_DAY
		opts.append({"label": "Sleep (8 hours)", "call": func(): _sleep_apartment()})
		opts.append({"label": "Cancel rental", "call": func(): _cancel_rent()})
	else:
		body = "Rent a small room for $%d per day, charged automatically each morning. Cancel any time." % GameState.RENT_PER_DAY
		opts.append({"label": "Rent a room (first day $%d now)" % GameState.RENT_PER_DAY, "call": func(): _rent()})
	hud.open_menu("Sunrise Apartments", body, opts)

func _rent() -> void:
	if GameState.spend(GameState.RENT_PER_DAY):
		GameState.rented_apartment = true
		GameState.notify("You rented a room. It is your new home!")
	_apartment_menu()

func _cancel_rent() -> void:
	GameState.rented_apartment = false
	GameState.notify("Rental cancelled.")
	_apartment_menu()

func _sleep_apartment() -> void:
	GameState.sleep(8.0)
	hud.blink()
	GameState.notify("You slept in your room.")
	world.save(true)
	_apartment_menu()

# =====================================================================
# NPC conversations and relationships
# =====================================================================
func rel_name(v: int) -> String:
	if v >= 90:
		return "Best friend"
	if v >= 70:
		return "Close friend"
	if v >= 40:
		return "Friend"
	if v >= 15:
		return "Acquaintance"
	return "Stranger"

func talk_menu(npc, line: String = "") -> void:
	var id: String = str(npc.id)
	var d: Dictionary = npc.data
	var nm: String = str(d["name"])
	var r := GameState.rel(id)
	npc.talking = true
	npc.face(player)
	var lines: Array = d.get("lines", ["Hello there."])
	if line == "":
		line = str(lines[randi() % lines.size()])
	var status := rel_name(r)
	if GameState.partner_id == id:
		status = "Spouse" if GameState.married else "Partner"
	var body := "\"%s\"\n\nRelationship: %s (%d/100)" % [line, status, r]
	var opts: Array = []
	var first_today: bool = not GameState.talked_today.has(id)
	opts.append({"label": "Chat (15 min)", "call": func(): _chat(npc, first_today)})
	opts.append({"label": "Compliment", "call": func(): _compliment(npc)})
	opts.append({"label": "Buy a gift ($20)", "call": func(): _gift(npc)})
	opts.append({"label": "Hang out for 2 hours ($15)", "disabled": r < 15, "call": func(): _hangout(npc)})
	# Family extras
	if id == "mom" or id == "dad":
		var fl := "bday_" + id
		if not GameState.flags.has(fl):
			opts.append({"label": "Accept birthday gift", "call": func(): _family_gift(npc, fl)})
	# Romance (early version; future updates will expand this)
	if bool(d.get("romance", false)):
		if GameState.partner_id == id:
			opts.append({"label": "Go on a date ($50, 3 hours)", "call": func(): _date(npc)})
			if not GameState.married:
				opts.append({"label": "Propose marriage (ring $800, needs 85+)", "disabled": r < 85, "call": func(): _propose(npc)})
			else:
				opts.append({"label": "Start a family: have a baby ($300, needs 90+)", "disabled": r < 90 or GameState.children.size() >= 4, "call": func(): _baby(npc)})
			opts.append({"label": "Break up", "call": func(): _breakup(npc)})
		elif GameState.partner_id == "":
			opts.append({"label": "Ask to be partners ($40 date, needs 60+)", "disabled": r < 60, "call": func(): _ask_partner(npc)})
	opts.append({"label": "Goodbye", "call": func(): _end_talk(npc)})
	hud.open_menu(nm, body, opts)

func _end_talk(npc) -> void:
	npc.talking = false

func _gain(npc, amount: int, text: String) -> void:
	GameState.add_rel(str(npc.id), amount)
	GameState.talked_today[str(npc.id)] = true
	GameState.notify(text)
	talk_menu(npc, "")

func _chat(npc, first_today: bool) -> void:
	GameState.advance_time(0.25)
	_gain(npc, 4 if first_today else 1, "You had a nice chat. +%d" % (4 if first_today else 1))

func _compliment(npc) -> void:
	var gain := 3 if not GameState.talked_today.has(str(npc.id)) else 1
	_gain(npc, gain, "They smiled at your compliment. +%d" % gain)

func _gift(npc) -> void:
	if GameState.spend(20):
		_gain(npc, 8, "They loved the gift! +8")
	else:
		talk_menu(npc, "")

func _hangout(npc) -> void:
	if GameState.spend(15):
		GameState.advance_time(2.0)
		GameState.energy = clamp(GameState.energy - 5.0, 0.0, 100.0)
		_gain(npc, 10, "You had a great time together. +10")
	else:
		talk_menu(npc, "")

func _family_gift(npc, flag: String) -> void:
	GameState.flags[flag] = true
	GameState.add_money(300)
	GameState.notify("Happy 18th birthday! You received $300.")
	talk_menu(npc, "Happy birthday! Use it wisely.")

func _ask_partner(npc) -> void:
	if GameState.spend(40):
		GameState.partner_id = str(npc.id)
		GameState.add_rel(str(npc.id), 5)
		GameState.notify("You are now dating %s!" % npc.data["name"])
	talk_menu(npc, "I would love that.")

func _date(npc) -> void:
	if GameState.spend(50):
		GameState.advance_time(3.0)
		_gain(npc, 8, "What a lovely date. +8")
	else:
		talk_menu(npc, "")

func _propose(npc) -> void:
	if GameState.spend(800):
		GameState.married = true
		GameState.add_rel(str(npc.id), 10)
		GameState.notify("%s said YES! You are married!" % npc.data["name"])
		talk_menu(npc, "Yes! A thousand times yes!")
	else:
		talk_menu(npc, "")

func _baby(npc) -> void:
	if GameState.spend(300):
		var names := ["Sam", "Noah", "Ava", "Mia", "Leo", "Zoe", "Omar", "Layla"]
		var nm: String = str(names[randi() % names.size()])
		GameState.children.append(nm)
		GameState.changed.emit()
		GameState.notify("Congratulations! Baby %s was born!" % nm)
		talk_menu(npc, "Our family is growing.")
	else:
		talk_menu(npc, "")

func _breakup(npc) -> void:
	GameState.partner_id = ""
	GameState.married = false
	GameState.relationships[str(npc.id)] = 20
	GameState.notify("You broke up.")
	_end_talk(npc)

# =====================================================================
# Phone menu
# =====================================================================
func phone_menu() -> void:
	var opts: Array = [
		{"label": "My status", "call": func(): _status_menu()},
		{"label": "GPS: go to a place", "call": func(): gps_menu()},
		{"label": "People I know", "call": func(): _people_menu()},
		{"label": "Save game", "call": func(): world.save(false)},
		{"label": "Settings", "call": func(): settings_menu()},
		{"label": "Quit to main menu", "call": func(): world.quit_to_menu()},
	]
	hud.open_menu("Phone", "%s  -  Day %d, %s" % [GameState.player_name, GameState.day, GameState.time_string()], opts)

func _status_menu() -> void:
	var home := "None (find one!)"
	if GameState.owned_houses.size() > 0:
		var names: Array = []
		for hid in GameState.owned_houses:
			names.append(str(GD.HOUSES[hid]["name"]))
		home = ", ".join(names)
	elif GameState.rented_apartment:
		home = "Rented room"
	elif GameState.can_sleep_at_parents():
		home = "Parents' home (%d days left)" % (GameState.PARENTS_HOME_DAYS - GameState.day + 1)
	var cars: Array = []
	for c in GameState.owned_cars:
		cars.append(str(GD.CARS[c["model"]]["name"]))
	var job := "Unemployed"
	if GameState.job_id != "":
		job = str(GD.JOBS[GameState.job_id]["name"])
	var fam := "Single"
	if GameState.partner_id != "":
		var pn: String = str(GD.npc_by_id(GameState.partner_id).get("name", "?"))
		fam = ("Married to " if GameState.married else "Dating ") + pn
	var txt := "Name: %s   Age: %d\nMoney: %s\nJob: %s  (total shifts: %d)\nFitness: %d\nHome: %s\nCars: %s\nRelationship: %s\nChildren: %s\nFriends: %d" % [
		GameState.player_name, GameState.age, money(GameState.money), job, GameState.total_shifts,
		GameState.fitness, home, (", ".join(cars) if cars.size() > 0 else "None"), fam,
		(", ".join(GameState.children) if GameState.children.size() > 0 else "None"), GameState.friends_count()]
	hud.open_menu("My status", txt, [{"label": "Back", "call": func(): phone_menu()}])

func _people_menu() -> void:
	var lines: Array = []
	for k in GameState.relationships.keys():
		var v := int(GameState.relationships[k])
		if v <= 0:
			continue
		var nm: String = str(world.npc_name(str(k)))
		lines.append("%s - %s (%d)" % [nm, rel_name(v), v])
	var txt := "You have not met anyone yet. Go say hello!" if lines.is_empty() else "\n".join(lines)
	hud.open_menu("People I know", txt, [{"label": "Back", "call": func(): phone_menu()}])

func gps_menu() -> void:
	var opts: Array = []
	var ids: Array = world.city.places.keys()
	ids.sort()
	for pid in ids:
		var p: Dictionary = world.city.places[pid]
		var ps: String = str(pid)
		if ps == "parents":
			opts.append({"label": "Family Home", "call": func(): _set_gps(ps)})
		else:
			opts.append({"label": str(p["name"]), "call": func(): _set_gps(ps)})
	opts.append({"label": "Turn GPS off", "call": func(): _set_gps("")})
	hud.open_menu("GPS", "Choose a destination. An arrow will point the way.", opts)

func _set_gps(pid: String) -> void:
	world.gps_target = pid
	GameState.notify("GPS off." if pid == "" else "GPS set. Follow the arrow!")

# =====================================================================
# In-game settings
# =====================================================================
func settings_menu() -> void:
	var s: Dictionary = GameState.settings
	var qn := ["Low", "Medium", "High"]
	var opts: Array = [
		{"label": "Camera: %s person" % ("First" if s["camera_mode"] == "first" else "Third"), "call": func(): _toggle_cam()},
		{"label": "Look sensitivity: %.1f" % float(s["look_sensitivity"]), "call": func(): _cycle_sens()},
		{"label": "Graphics quality: %s" % qn[int(s.get("quality", 1))], "call": func(): _cycle_quality()},
		{"label": "Shadows: %s" % ("On" if s["shadows"] else "Off"), "call": func(): _toggle_shadows()},
		{"label": "Show FPS: %s" % ("On" if s["show_fps"] else "Off"), "call": func(): _toggle_fps()},
		{"label": "Back", "call": func(): phone_menu()},
	]
	hud.open_menu("Settings", "", opts)

func _toggle_cam() -> void:
	player.toggle_camera()
	settings_menu()

func _cycle_sens() -> void:
	var vals := [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
	var cur := float(GameState.settings["look_sensitivity"])
	var idx := 0
	for i in range(vals.size()):
		if absf(float(vals[i]) - cur) < 0.01:
			idx = i
	GameState.settings["look_sensitivity"] = vals[(idx + 1) % vals.size()]
	GameState.save_settings()
	settings_menu()

func _cycle_quality() -> void:
	GameState.settings["quality"] = (int(GameState.settings.get("quality", 1)) + 1) % 3
	GameState.save_settings()
	world.apply_quality()
	settings_menu()

func _toggle_shadows() -> void:
	GameState.settings["shadows"] = not bool(GameState.settings["shadows"])
	GameState.save_settings()
	world.apply_quality()
	settings_menu()

func _toggle_fps() -> void:
	GameState.settings["show_fps"] = not bool(GameState.settings["show_fps"])
	GameState.save_settings()
	settings_menu()
