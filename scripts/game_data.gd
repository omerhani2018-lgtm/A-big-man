extends RefCounted
# Static game content. Edit the numbers here to rebalance or expand the game.
# Use from other scripts with:  const GD = preload("res://scripts/game_data.gd")

# ---------------- Jobs ----------------
# pay = money per shift, hours = game hours a shift takes, energy = energy used,
# need_shifts = total shifts worked (any job) required to be hired, needs_car = bool
const JOBS := {
	"cashier": {"name": "Shop Cashier", "place": "corner_shop", "pay": 60, "hours": 4, "energy": 15, "need_shifts": 0, "needs_car": false,
		"desc": "Scan groceries and chat with customers. Easy first job."},
	"construction": {"name": "Construction Worker", "place": "construction", "pay": 110, "hours": 6, "energy": 32, "need_shifts": 0, "needs_car": false,
		"desc": "Heavy work, good pay. Builds your fitness too."},
	"delivery": {"name": "Delivery Driver", "place": "depot", "pay": 95, "hours": 5, "energy": 20, "need_shifts": 0, "needs_car": true,
		"desc": "Deliver parcels around the city. You need your own car."},
	"office": {"name": "Office Clerk", "place": "office", "pay": 150, "hours": 6, "energy": 22, "need_shifts": 6, "needs_car": false,
		"desc": "Paperwork in the Skyline Tower. Needs 6 shifts of experience."},
	"manager": {"name": "Office Manager", "place": "office", "pay": 280, "hours": 7, "energy": 28, "need_shifts": 25, "needs_car": false,
		"desc": "Run the whole floor. Needs 25 shifts of experience."},
}

# ---------------- Food and services ----------------
const FOOD := [
	{"id": "coffee", "name": "Coffee", "price": 5, "hunger": 5, "energy": 12},
	{"id": "burger", "name": "Burger Meal", "price": 12, "hunger": 30, "energy": 0},
	{"id": "groceries", "name": "Groceries (cook at home)", "price": 25, "hunger": 55, "energy": 0},
	{"id": "steak", "name": "Steak Dinner", "price": 45, "hunger": 80, "energy": 5},
]

# ---------------- Houses for sale ----------------
const HOUSES := {
	"h1": {"name": "Maple Cottage", "price": 3000, "desc": "Tiny starter home with a small garden."},
	"h2": {"name": "Oak Street House", "price": 6500, "desc": "Two bedrooms and a garage."},
	"h3": {"name": "Riverside Villa", "price": 14000, "desc": "Spacious villa on a quiet street."},
	"h4": {"name": "Hilltop Residence", "price": 28000, "desc": "Large modern house with a view."},
	"h5": {"name": "Sunset Bungalow", "price": 8500, "desc": "Cozy bungalow near the park."},
	"h6": {"name": "Grand Manor", "price": 60000, "desc": "The biggest house in town. A true big man's home."},
}

# ---------------- Cars ----------------
const CARS := {
	"hatch": {"name": "City Hatchback", "price": 800, "speed": 20.0, "desc": "Cheap and cheerful."},
	"sedan": {"name": "Family Sedan", "price": 2500, "speed": 25.0, "desc": "Comfortable and reliable."},
	"suv": {"name": "Explorer SUV", "price": 6000, "speed": 27.0, "desc": "Big, tough and roomy."},
	"sports": {"name": "Thunder GT", "price": 15000, "speed": 38.0, "desc": "Very fast. Turn heads everywhere."},
}
const CAR_COLORS := ["#c0392b", "#2980b9", "#27ae60", "#f1c40f", "#ecf0f1", "#2c3e50", "#e67e22", "#8e44ad"]

# ---------------- NPCs ----------------
# kind: "family" stands near the parents' home; "walker" strolls around a block.
# romance: can be dated. block: [i, j] block the walker strolls around.
const NPCS := [
	{"id": "mom", "name": "Maria (Mom)", "kind": "family", "skin": "#e0ac8a", "shirt": "#c0392b", "romance": false, "female": true,
		"lines": ["I am so proud of you, sweetheart.", "Eat properly and sleep enough, okay?", "Eighteen already... time flies.", "Find a job, then a home. You can do it."]},
	{"id": "dad", "name": "Robert (Dad)", "kind": "family", "skin": "#c68d6a", "shirt": "#34495e", "romance": false, "female": false,
		"lines": ["Money does not grow on trees, son. Work hard.", "Save up. A house first, then a car.", "I started at the construction yard. Honest work.", "You can always visit us."]},
	{"id": "lily", "name": "Lily (Sister)", "kind": "walker", "block": [0, 1], "skin": "#e0ac8a", "shirt": "#e84393", "romance": false, "female": true,
		"lines": ["Big brother! Take me for a ride when you get a car.", "I want to see the city with you.", "Mom worries about you too much.", "Buy me an ice cream sometime!"]},
	{"id": "jake", "name": "Jake", "kind": "walker", "block": [0, 0], "skin": "#c68d6a", "shirt": "#27ae60", "romance": false, "female": false,
		"lines": ["Hey! New in town? The Corner Shop is always hiring.", "I fix cars. Come by if yours breaks.", "Nice weather for a walk.", "Delivery work pays okay if you own a car."]},
	{"id": "sofia", "name": "Sofia", "kind": "walker", "block": [-1, 0], "skin": "#f1c27d", "shirt": "#f39c12", "romance": true, "female": true,
		"lines": ["I work at the cafe. Come say hi!", "Do you like coffee? I make the best.", "This city is bigger than it looks.", "I love walking at sunset."]},
	{"id": "marcus", "name": "Marcus", "kind": "walker", "block": [1, 0], "skin": "#8d5524", "shirt": "#2980b9", "romance": false, "female": false,
		"lines": ["Hit the gym regularly. It changes everything.", "Strong body, strong mind.", "Want a workout buddy?", "I lift every single day."]},
	{"id": "emma", "name": "Emma", "kind": "walker", "block": [1, 1], "skin": "#f1c27d", "shirt": "#9b59b6", "romance": true, "female": true,
		"lines": ["I am studying architecture.", "The tall towers downtown are beautiful.", "Have you seen the park yet?", "I could talk about buildings all day."]},
	{"id": "carlos", "name": "Carlos", "kind": "walker", "block": [-1, 1], "skin": "#a16b47", "shirt": "#d35400", "romance": false, "female": false,
		"lines": ["Work shifts add up. Experience opens better jobs.", "Office jobs pay best, but you must earn them.", "Save before you spend, my friend.", "I have lived here thirty years."]},
	{"id": "nina", "name": "Nina", "kind": "walker", "block": [0, -1], "skin": "#e0ac8a", "shirt": "#16a085", "romance": true, "female": true,
		"lines": ["I am a nurse. Take care of your health!", "Sleep and food keep you going.", "The hospital is on the west side.", "Long shifts, but I love helping people."]},
	{"id": "omar", "name": "Omar", "kind": "walker", "block": [-1, -1], "skin": "#a16b47", "shirt": "#7f8c8d", "romance": false, "female": false,
		"lines": ["I drive a taxi. I know every street.", "Traffic is crazy at noon.", "A good car changes your life.", "Need directions? Use your phone GPS."]},
	{"id": "hannah", "name": "Hannah", "kind": "walker", "block": [1, -1], "skin": "#f1c27d", "shirt": "#e74c3c", "romance": true, "female": true,
		"lines": ["I own a little boutique downtown.", "Business is slow but steady.", "You look like someone who will go far.", "Come visit when you have time."]},
]

static func npc_by_id(id: String) -> Dictionary:
	for n in NPCS:
		if n["id"] == id:
			return n
	return {}
