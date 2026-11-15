extends RefCounted
# Procedurally builds the whole city: roads, blocks, buildings, houses, trees,
# street lights and all the special places (shops, jobs, homes).
# No external art files are needed.

const GD = preload("res://scripts/game_data.gd")
const IA = preload("res://scripts/interactable.gd")

const PITCH := 70.0     # distance between block centres
const BLOCK := 56.0     # block size (the rest is road)
const GRID := 4         # blocks run from -GRID..GRID in x and z
const LOT := 24.0
const LOT_OFF := 14.0
const EXTENT := 350.0

const FACADE_SHADER := """
shader_type spatial;
uniform vec3 tint = vec3(1.0);
uniform float seed = 0.0;
uniform float night = 0.0;
varying vec3 wpos;
varying vec3 wnorm;
varying vec4 vcol;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vcol = vec4(COLOR.rgb * tint, COLOR.a);
}
void fragment() {
	float wall = 1.0 - step(0.5, abs(wnorm.y));
	float u = mix(wpos.x, wpos.z, step(0.5, abs(wnorm.x)));
	vec2 cell = vec2(u / 3.2, (wpos.y - 1.4) / 3.4);
	vec2 f = fract(cell);
	vec2 cid = floor(cell);
	float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.2, f.y) * step(f.y, 0.82);
	win *= wall * step(0.0, cell.y);
	float s = vcol.a * 97.0 + seed;
	float h = fract(sin(dot(cid + vec2(s, s * 0.37), vec2(12.9898, 78.233))) * 43758.5453);
	float lit = step(0.55, h);
	vec3 glass = vec3(0.10, 0.17, 0.26);
	vec3 base = vcol.rgb;
	if (wnorm.y > 0.5) {
		base = base * 0.55;
	}
	ALBEDO = mix(base, glass, win);
	ROUGHNESS = mix(0.85, 0.18, win);
	METALLIC = win * 0.35;
	EMISSION = win * lit * night * vec3(1.0, 0.82, 0.45) * 1.6;
}
"""

const SPECIALS := {
	"0,0,0": {"id": "office", "type": "job", "name": "Skyline Tower", "color": "#5b7ea8", "h": 46.0},
	"0,0,1": {"id": "bank", "type": "decor", "name": "City Bank", "color": "#b8a98a", "h": 16.0},
	"0,0,2": {"id": "corner_shop", "type": "shop", "name": "Corner Shop", "color": "#d98c3a", "h": 8.0},
	"0,0,3": {"id": "burger", "type": "shop", "name": "Burger Bar", "color": "#c0392b", "h": 8.0},
	"1,0,0": {"id": "construction", "type": "job", "name": "Construction Yard", "color": "#e5b82e", "h": 7.0},
	"1,0,1": {"id": "gym", "type": "shop", "name": "Iron Gym", "color": "#4b5568", "h": 9.0},
	"1,0,2": {"id": "dealer", "type": "shop", "name": "Premier Motors", "color": "#2f6f9f", "h": 8.0},
	"1,0,3": {"id": "realestate", "type": "shop", "name": "Realty Office", "color": "#4f9d69", "h": 12.0},
	"-1,0,0": {"id": "apartment", "type": "shop", "name": "Sunrise Apartments", "color": "#9a6fb0", "h": 24.0},
	"-1,0,1": {"id": "depot", "type": "job", "name": "Parcel Depot", "color": "#8b979a", "h": 8.0},
	"-1,0,2": {"id": "hospital", "type": "shop", "name": "City Hospital", "color": "#e8eef2", "h": 16.0},
	"-1,0,3": {"id": "cafe", "type": "shop", "name": "Moonlight Cafe", "color": "#7b5645", "h": 7.0},
	"0,1,0": {"id": "parents", "type": "house", "name": "Family Home", "color": "#e8d9b8"},
	"0,1,1": {"id": "h1", "type": "house", "color": "#d9a066"},
	"0,1,2": {"id": "h5", "type": "house", "color": "#9fc5a0"},
	"0,1,3": {"id": "h2", "type": "house", "color": "#c9b79c"},
	"0,-1,0": {"id": "h3", "type": "house", "color": "#a7b9d6"},
	"0,-1,1": {"id": "h4", "type": "house", "color": "#e6e0d4"},
	"0,-1,2": {"id": "h6", "type": "house", "color": "#c9a0a0"},
	"0,-1,3": {"id": "park", "type": "park", "name": "Central Park"},
}

const PLACE_COLORS := {
	"job": Color(1.0, 0.8, 0.2),
	"shop": Color(0.3, 0.8, 1.0),
	"house": Color(0.5, 1.0, 0.5),
	"decor": Color(0.8, 0.8, 0.8),
}

var root: Node3D
var rng := RandomNumberGenerator.new()
var places := {}          # id -> {"name", "pos" (door point), "type"}
var house_signs := {}     # house id -> Label3D
var facade_materials: Array = []
var lamp_material: StandardMaterial3D
var spawn_pos := Vector3.ZERO

var _shader: Shader
var _body: StaticBody3D
var _slabs: Array = []
var _gen_buildings: Array = []
var _house_bodies: Array = []
var _house_roofs: Array = []
var _trees: Array = []
var _special_keys := {}

func build(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "City"
	parent.add_child(root)
	rng.seed = 20260101
	_shader = Shader.new()
	_shader.code = FACADE_SHADER
	_body = StaticBody3D.new()
	_body.name = "CityCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	root.add_child(_body)
	_build_ground()
	_build_blocks()
	_build_road_markings()
	_build_street_lights()
	_flush_multimeshes()

func set_night(value: float) -> void:
	for m in facade_materials:
		m.set_shader_parameter("night", value)
	if lamp_material != null:
		lamp_material.emission_energy_multiplier = 0.3 + value * 3.0

# ---------------- helpers ----------------
func _facade_material(col: Color, seed_val: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("seed", seed_val)
	facade_materials.append(m)
	return m

func _std_material(col: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m

func _collider(pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	_body.add_child(cs)

func _box_xform(pos: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)

func _flush_multimesh(mesh: Mesh, items: Array, mat: Material, use_colors: bool, shadows: bool = true) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in range(items.size()):
		mm.set_instance_transform(i, items[i][0])
		if use_colors:
			mm.set_instance_color(i, items[i][1])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

# ---------------- ground ----------------
func _build_ground() -> void:
	var grass := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(4000, 4000)
	grass.mesh = gp
	grass.material_override = _std_material(Color(0.27, 0.42, 0.22))
	grass.position = Vector3(0, -0.08, 0)
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(grass)

	var road := MeshInstance3D.new()
	var rp := PlaneMesh.new()
	rp.size = Vector2(EXTENT * 2.0, EXTENT * 2.0)
	road.mesh = rp
	road.material_override = _std_material(Color(0.13, 0.13, 0.15), 0.95)
	road.position = Vector3(0, 0.0, 0)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(road)

	_collider(Vector3(0, -1.0, 0), Vector3(EXTENT * 2.0 + 400.0, 2.0, EXTENT * 2.0 + 400.0))
	# Invisible boundary walls.
	var e := EXTENT
	_collider(Vector3(0, 10, e + 1), Vector3(e * 2.0 + 4, 20, 2))
	_collider(Vector3(0, 10, -e - 1), Vector3(e * 2.0 + 4, 20, 2))
	_collider(Vector3(e + 1, 10, 0), Vector3(2, 20, e * 2.0 + 4))
	_collider(Vector3(-e - 1, 10, 0), Vector3(2, 20, e * 2.0 + 4))

# ---------------- blocks ----------------
func _build_blocks() -> void:
	for i in range(-GRID, GRID + 1):
		for j in range(-GRID, GRID + 1):
			_build_block(i, j)

func _build_block(i: int, j: int) -> void:
	var c := Vector3(i * PITCH, 0, j * PITCH)
	var d: int = max(abs(i), abs(j))
	var slab_col := Color(0.38, 0.39, 0.41)
	if d >= 2:
		slab_col = Color(0.34, 0.4, 0.31)
	if d >= 4 or (i == 0 and abs(j) == 1):
		slab_col = Color(0.2, 0.36, 0.17)
	_slabs.append([_box_xform(c + Vector3(0, 0.05, 0), Vector3(BLOCK, 0.1, BLOCK)), slab_col])

	for k in range(4):
		var kx := -1.0 if k % 2 == 0 else 1.0
		var kz := -1.0 if k < 2 else 1.0
		var lot_c := c + Vector3(kx * LOT_OFF, 0, kz * LOT_OFF)
		var key := "%d,%d,%d" % [i, j, k]
		if SPECIALS.has(key):
			_build_special(SPECIALS[key], lot_c, kz)
		else:
			_build_generic(d, lot_c)
	# Sidewalk trees (skipped in the downtown core to keep it urban).
	if d >= 1:
		for s in [-14.0, 14.0]:
			_trees.append(Vector3(c.x + s, 0, c.z + 27.0))
			_trees.append(Vector3(c.x + s, 0, c.z - 27.0))
			_trees.append(Vector3(c.x + 27.0, 0, c.z + s))
			_trees.append(Vector3(c.x - 27.0, 0, c.z + s))

func _build_generic(d: int, lot_c: Vector3) -> void:
	if d >= 2 and rng.randf() < 0.1:
		for n in range(5):
			_trees.append(lot_c + Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9)))
		return
	var col_v := rng.randf_range(0.55, 0.9)
	var seed_a := rng.randf()
	if d <= 1:
		var h := rng.randf_range(20.0, 52.0)
		var w := rng.randf_range(17.0, 22.0)
		var dd := rng.randf_range(17.0, 22.0)
		var tints := [Color(0.62, 0.68, 0.76), Color(0.72, 0.7, 0.66), Color(0.55, 0.6, 0.62), Color(0.78, 0.76, 0.72)]
		var col: Color = tints[rng.randi() % tints.size()] * col_v
		col.a = seed_a
		_gen_buildings.append([_box_xform(lot_c + Vector3(0, h * 0.5, 0), Vector3(w, h, dd)), col])
		_collider(lot_c + Vector3(0, h * 0.5, 0), Vector3(w, h, dd))
	elif d <= 3:
		var h2 := rng.randf_range(8.0, 22.0)
		var w2 := rng.randf_range(15.0, 21.0)
		var d2 := rng.randf_range(15.0, 21.0)
		var tints2 := [Color(0.8, 0.62, 0.5), Color(0.7, 0.72, 0.62), Color(0.76, 0.74, 0.7), Color(0.6, 0.66, 0.72), Color(0.8, 0.72, 0.55)]
		var col2: Color = tints2[rng.randi() % tints2.size()] * col_v
		col2.a = seed_a
		_gen_buildings.append([_box_xform(lot_c + Vector3(0, h2 * 0.5, 0), Vector3(w2, h2, d2)), col2])
		_collider(lot_c + Vector3(0, h2 * 0.5, 0), Vector3(w2, h2, d2))
	else:
		var off := Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		_add_house_geometry(lot_c + off, rng.randf_range(10.0, 13.0), rng.randf_range(9.0, 12.0), rng.randf_range(4.5, 6.0),
			Color.from_hsv(rng.randf(), 0.18, rng.randf_range(0.75, 0.95)))

func _add_house_geometry(pos: Vector3, w: float, d: float, h: float, col: Color) -> void:
	var c := col
	c.a = rng.randf()
	_house_bodies.append([_box_xform(pos + Vector3(0, h * 0.5, 0), Vector3(w, h, d)), c])
	_house_roofs.append([_box_xform(pos + Vector3(0, h + 1.2, 0), Vector3(w + 1.2, 2.4, d + 1.2)), Color(0.45, 0.2, 0.15)])
	_collider(pos + Vector3(0, h * 0.5, 0), Vector3(w, h, d))

# ---------------- special places ----------------
func _build_special(spec: Dictionary, lot_c: Vector3, kz: float) -> void:
	var id: String = spec["id"]
	var type: String = spec["type"]
	if type == "park":
		for n in range(14):
			_trees.append(lot_c + Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10)))
		var bench := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0, 0.5, 0.6)
		bench.mesh = bm
		bench.material_override = _std_material(Color(0.4, 0.28, 0.16))
		bench.position = lot_c + Vector3(0, 0.3, 0)
		root.add_child(bench)
		places[id] = {"name": spec["name"], "pos": lot_c + Vector3(0, 0, kz * 4.0), "type": "park", "out": Vector3(0, 0, kz)}
		return

	var col := Color(str(spec["color"]))
	var w := 20.0
	var d := 20.0
	var h: float = float(spec.get("h", 6.0))
	var title: String = str(spec.get("name", ""))
	var door_radius := 4.8
	if type == "house":
		var hd: Dictionary = GD.HOUSES.get(id, {})
		w = 14.0
		d = 12.0
		h = 5.0
		if id == "parents":
			w = 16.0
			d = 13.0
			h = 6.0
			title = "Family Home"
		else:
			title = str(hd.get("name", id))
		door_radius = 7.0
		_add_house_geometry(lot_c, w, d, h, col)
	else:
		var mi := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(w, h, d)
		mi.mesh = bm2
		mi.material_override = _facade_material(col, rng.randf() * 50.0)
		mi.position = lot_c + Vector3(0, h * 0.5, 0)
		root.add_child(mi)
		_collider(lot_c + Vector3(0, h * 0.5, 0), Vector3(w, h, d))

	var face_z := lot_c.z + kz * (d * 0.5)
	# Door
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(2.4, 3.0, 0.3)
	door.mesh = dm
	door.material_override = _std_material(Color(0.12, 0.08, 0.06), 0.6)
	door.position = Vector3(lot_c.x, 1.5, face_z + kz * 0.08)
	root.add_child(door)

	# Sign board with name (readable from the street side)
	var sign_col: Color = PLACE_COLORS.get(type, Color(0.8, 0.8, 0.8))
	var board := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(9.0, 1.6, 0.25)
	board.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = sign_col * 0.5
	bmat.emission_enabled = true
	bmat.emission = sign_col
	bmat.emission_energy_multiplier = 0.6
	board.material_override = bmat
	var sign_y: float = min(h - 0.9, 5.2) if type != "house" else h + 0.6
	if type == "house":
		sign_y = 3.6
	board.position = Vector3(lot_c.x, sign_y, face_z + kz * 0.2)
	root.add_child(board)

	var wall_label := Label3D.new()
	wall_label.text = title
	wall_label.font_size = 56
	wall_label.pixel_size = 0.014
	wall_label.outline_size = 8
	wall_label.position = Vector3(lot_c.x, sign_y, face_z + kz * 0.4)
	if kz < 0.0:
		wall_label.rotation.y = PI
	root.add_child(wall_label)

	# Floating label visible from far away
	var top_label := Label3D.new()
	top_label.text = title
	top_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	top_label.font_size = 64
	top_label.pixel_size = 0.03
	top_label.outline_size = 12
	top_label.modulate = sign_col
	top_label.position = lot_c + Vector3(0, (h if type != "house" else h + 2.4) + 3.0, 0)
	top_label.visibility_range_end = 260.0
	root.add_child(top_label)
	if type == "house":
		house_signs[id] = top_label

	# Interaction point at the door
	var ia := IA.new()
	ia.kind = type
	ia.id = id
	ia.title = ("Enter " + title) if type != "house" else title
	ia.radius = door_radius
	ia.position = Vector3(lot_c.x, 0, face_z + kz * 1.8)
	root.add_child(ia)
	ia.add_to_group("interactable")
	places[id] = {"name": title, "pos": ia.position, "type": type, "out": Vector3(0, 0, kz)}
	if id == "parents":
		spawn_pos = Vector3(lot_c.x + 6.0, 0.2, face_z + kz * 5.5)

# ---------------- roads and lights ----------------
func _build_road_markings() -> void:
	var dashes: Array = []
	var white := Color(0.85, 0.85, 0.8)
	var limit := EXTENT - 8.0
	for r in range(-GRID - 1, GRID + 1):
		var center := (float(r) + 0.5) * PITCH
		var t := -limit
		while t < limit:
			var near_cross := absf(fposmod(t, PITCH) - PITCH * 0.5) < 9.0
			if not near_cross:
				dashes.append([_box_xform(Vector3(center, 0.03, t), Vector3(0.3, 0.02, 3.5)), white])
				dashes.append([_box_xform(Vector3(t, 0.03, center), Vector3(3.5, 0.02, 0.3)), white])
			t += 8.0
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	_flush_multimesh(BoxMesh.new(), dashes, mat, true, false)

func _build_street_lights() -> void:
	var poles: Array = []
	var lamps: Array = []
	for i in range(-GRID, GRID + 1):
		for j in range(-GRID, GRID + 1):
			var c := Vector3(i * PITCH, 0, j * PITCH)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := c + Vector3(sx * 27.6, 0, sz * 27.6)
					poles.append([_box_xform(p + Vector3(0, 3.5, 0), Vector3(0.22, 7.0, 0.22)), Color.WHITE])
					lamps.append([_box_xform(p + Vector3(-sx * 0.5, 7.1, -sz * 0.5), Vector3(0.9, 0.18, 0.9)), Color.WHITE])
	_flush_multimesh(BoxMesh.new(), poles, _std_material(Color(0.18, 0.2, 0.22), 0.6), false, false)
	lamp_material = StandardMaterial3D.new()
	lamp_material.albedo_color = Color(1, 0.95, 0.8)
	lamp_material.emission_enabled = true
	lamp_material.emission = Color(1.0, 0.85, 0.5)
	lamp_material.emission_energy_multiplier = 0.3
	_flush_multimesh(BoxMesh.new(), lamps, lamp_material, false, false)

# ---------------- final multimeshes ----------------
func _flush_multimeshes() -> void:
	var slab_mat := StandardMaterial3D.new()
	slab_mat.vertex_color_use_as_albedo = true
	slab_mat.roughness = 0.95
	_flush_multimesh(BoxMesh.new(), _slabs, slab_mat, true, false)

	var fac := _facade_material(Color.WHITE, 0.0)
	_flush_multimesh(BoxMesh.new(), _gen_buildings, fac, true)
	var house_mat := _facade_material(Color.WHITE, 3.0)
	_flush_multimesh(BoxMesh.new(), _house_bodies, house_mat, true)

	var prism := PrismMesh.new()
	var roof_mat := StandardMaterial3D.new()
	roof_mat.vertex_color_use_as_albedo = true
	roof_mat.roughness = 0.85
	_flush_multimesh(prism, _house_roofs, roof_mat, true)

	# Trees: trunk + crown
	var trunks: Array = []
	var crowns: Array = []
	for p in _trees:
		var s := rng.randf_range(0.8, 1.3)
		trunks.append([Transform3D(Basis.from_scale(Vector3(0.45 * s, 3.0 * s, 0.45 * s)), p + Vector3(0, 1.5 * s, 0)), Color.WHITE])
		var g := Color(rng.randf_range(0.12, 0.25), rng.randf_range(0.38, 0.55), rng.randf_range(0.12, 0.22))
		crowns.append([Transform3D(Basis.from_scale(Vector3(3.6 * s, 3.8 * s, 3.6 * s)), p + Vector3(0, 4.2 * s, 0)), g])
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.5
	trunk_mesh.bottom_radius = 0.6
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	_flush_multimesh(trunk_mesh, trunks, _std_material(Color(0.32, 0.22, 0.14)), false, false)
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.5
	crown_mesh.height = 1.0
	crown_mesh.radial_segments = 8
	crown_mesh.rings = 5
	var crown_mat := StandardMaterial3D.new()
	crown_mat.vertex_color_use_as_albedo = true
	crown_mat.roughness = 0.9
	_flush_multimesh(crown_mesh, crowns, crown_mat, true)
