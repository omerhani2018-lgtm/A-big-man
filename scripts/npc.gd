extends Node3D
# A non-player character. "walker" NPCs stroll around the sidewalk of a block,
# "family" NPCs stand near the parents' home. All NPCs are adults (18+).

const HumanModel = preload("res://scripts/human_model.gd")

const RING := 27.0   # sidewalk ring half-size inside a 56 m block

var kind := "npc"
var id := ""
var data := {}
var title := ""
var radius := 3.4
var talking := false

var _model: Node3D
var _points: Array = []
var _next := 0
var _speed := 1.4
var _pause := 0.0
var _anim_t := 0.0
var _stand := false
var _face_target: Node3D = null
var _home_yaw := 0.0

func setup(d: Dictionary, block_center: Vector3, start_corner: int) -> void:
	data = d
	id = str(d["id"])
	title = "Talk to " + str(d["name"])
	_stand = str(d.get("kind", "walker")) == "family"
	var h := RING
	_points = [
		Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)
	]
	for i in range(_points.size()):
		_points[i] = _points[i] + block_center
	_next = (start_corner + 1) % 4
	position = _points[start_corner % 4]
	_speed = randf_range(1.1, 1.6)
	_pause = randf_range(0.0, 3.0)

func _ready() -> void:
	var female: bool = bool(data.get("female", false))
	var hairs := [Color("#1e1410"), Color("#3b2416"), Color("#7a5230"), Color("#c9a24b"), Color("#111111")]
	var hair: Color = hairs[abs(hash(id)) % hairs.size()]
	var pants_cols := [Color("#2b2f3a"), Color("#3d3a33"), Color("#1f3552"), Color("#4a3b2e")]
	var pants: Color = pants_cols[abs(hash(id + "p")) % pants_cols.size()]
	_model = HumanModel.build(Color(str(data["skin"])), Color(str(data["shirt"])), pants, hair, female)
	add_child(_model)
	_apply_visibility(_model)
	var tag := Label3D.new()
	tag.text = str(data["name"])
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.05, 0)
	tag.pixel_size = 0.006
	tag.font_size = 40
	tag.outline_size = 10
	tag.no_depth_test = false
	tag.visibility_range_end = 25.0
	add_child(tag)

func _apply_visibility(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.visibility_range_end = 110.0
		_apply_visibility(c)

func face(target: Node3D) -> void:
	_face_target = target

func interact_point() -> Vector3:
	return global_position

func prompt_text() -> String:
	return title

func _process(delta: float) -> void:
	if _face_target != null and (talking or _stand):
		var d := _face_target.global_position - global_position
		if d.length() < 6.0:
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-d.x, -d.z), min(1.0, delta * 6.0))
	if talking or _stand:
		HumanModel.animate(_model, _anim_t, 0.0)
		return
	if _pause > 0.0:
		_pause -= delta
		HumanModel.animate(_model, _anim_t, 0.0)
		return
	var tgt: Vector3 = _points[_next]
	var to := tgt - position
	to.y = 0.0
	if to.length() < 0.3:
		_next = (_next + 1) % 4
		if randf() < 0.4:
			_pause = randf_range(1.0, 4.0)
		return
	var dir := to.normalized()
	position += dir * _speed * delta
	_anim_t += delta * 6.5
	_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-dir.x, -dir.z), min(1.0, delta * 8.0))
	HumanModel.animate(_model, _anim_t, 0.8)
