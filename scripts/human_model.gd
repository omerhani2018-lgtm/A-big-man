extends RefCounted
# Builds a simple 3D human out of primitive meshes (no external assets needed).
# The front of the model faces -Z.

static func _mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 4
	return c

static func build(skin: Color, shirt: Color, pants: Color, hair: Color, female: bool = false) -> Node3D:
	var root := Node3D.new()
	var skin_m := _mat(skin)
	var shirt_m := _mat(shirt)
	var pants_m := _mat(pants)
	var hair_m := _mat(hair, 0.6)
	var shoe_m := _mat(Color(0.08, 0.08, 0.1), 0.5)

	# Torso
	var tw := 0.36 if female else 0.42
	var torso := BoxMesh.new()
	torso.size = Vector3(tw, 0.58, 0.24)
	_add(root, torso, shirt_m, Vector3(0, 1.17, 0))

	# Head, face, hair
	var head := SphereMesh.new()
	head.radius = 0.12
	head.height = 0.25
	head.radial_segments = 14
	head.rings = 8
	_add(root, head, skin_m, Vector3(0, 1.63, 0))
	var nose := BoxMesh.new()
	nose.size = Vector3(0.03, 0.04, 0.04)
	_add(root, nose, skin_m, Vector3(0, 1.62, -0.125))
	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.13
	hair_mesh.height = 0.2
	hair_mesh.radial_segments = 14
	hair_mesh.rings = 6
	_add(root, hair_mesh, hair_m, Vector3(0, 1.68, 0.01))
	if female:
		var back := BoxMesh.new()
		back.size = Vector3(0.2, 0.32, 0.07)
		_add(root, back, hair_m, Vector3(0, 1.5, 0.11))

	# Neck
	var neck := _capsule(0.05, 0.14)
	_add(root, neck, skin_m, Vector3(0, 1.49, 0))

	# Legs (pivot at hip so they can swing)
	for side in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.1 * side, 0.88, 0)
		root.add_child(pivot)
		_add(pivot, _capsule(0.085, 0.88), pants_m, Vector3(0, -0.44, 0))
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.14, 0.08, 0.26)
		_add(pivot, shoe, shoe_m, Vector3(0, -0.84, -0.04))
		root.set_meta("leg_" + ("l" if side < 0 else "r"), pivot)

	# Arms (pivot at shoulder)
	for side in [-1, 1]:
		var pivot := Node3D.new()
		pivot.position = Vector3((tw * 0.5 + 0.06) * side, 1.42, 0)
		root.add_child(pivot)
		_add(pivot, _capsule(0.058, 0.56), shirt_m, Vector3(0, -0.26, 0))
		var hand := SphereMesh.new()
		hand.radius = 0.05
		hand.height = 0.1
		_add(pivot, hand, skin_m, Vector3(0, -0.56, 0))
		root.set_meta("arm_" + ("l" if side < 0 else "r"), pivot)
	return root

static func animate(root: Node3D, t: float, amount: float) -> void:
	# amount 0 = standing still, 1 = full stride.
	var s := sin(t) * amount * 0.75
	root.get_meta("leg_l").rotation.x = s
	root.get_meta("leg_r").rotation.x = -s
	root.get_meta("arm_l").rotation.x = -s * 0.8
	root.get_meta("arm_r").rotation.x = s * 0.8
