extends Node3D
# Marks a spot the player can interact with (shop door, house door, job site...).
# World code puts these in the group "interactable".

var kind := ""     # "shop", "job", "house", "dealer", "realestate", "apartment", "gym", ...
var id := ""
var title := ""
var radius := 4.5

func interact_point() -> Vector3:
	return global_position

func prompt_text() -> String:
	return title
