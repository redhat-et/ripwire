class_name Blind
extends Node

@onready var uniq: Node = $%SceneUnique

func keyword_reassign() -> void:
	var remote := {}
	remote = {"a": 1}
	helper_fn()

func survives_after_blind_spot() -> void:
	helper_fn()

func helper_fn() -> void:
	pass
