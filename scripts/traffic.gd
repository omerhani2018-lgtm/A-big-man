extends Node3D
# Ambient traffic car. Drives back and forth along one straight road.
# It has no collision, so it never blocks the player (keeps the demo stable).

const CarScript = preload("res://scripts/car.gd")

var along_x := false     # true: drives along the X axis at fixed z
var fixed := 0.0         # the fixed coordinate (road centre + lane offset)
var dir := 1.0
var speed := 9.0
var bound := 330.0
var pos_along := 0.0

func setup(mid: String, col: Color, road_center: float, lane: float, start: float, horizontal: bool, d: float, spd: float, b: float) -> void:
	along_x = horizontal
	dir = d
	speed = spd
	bound = b
	fixed = road_center + lane
	pos_along = start
	add_child(CarScript.build_model(mid, col))
	_apply()

func _apply() -> void:
	if along_x:
		position = Vector3(pos_along, 0.0, fixed)
		rotation.y = -PI * 0.5 if dir > 0.0 else PI * 0.5
	else:
		position = Vector3(fixed, 0.0, pos_along)
		rotation.y = PI if dir > 0.0 else 0.0

func _process(delta: float) -> void:
	pos_along += dir * speed * delta
	if pos_along > bound:
		pos_along = -bound
	elif pos_along < -bound:
		pos_along = bound
	_apply()
