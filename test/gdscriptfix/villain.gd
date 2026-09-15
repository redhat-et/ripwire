# DECOY: re-uses take_damage/_apply so the map must carry TWO defs of each name, one per
# file, rather than collapsing them into whichever file the crawl reached first.
class_name Villain
extends Node2D

func take_damage(amount: int) -> void:
	_apply(amount)

func _apply(amount: int) -> void:
	pass

func only_here() -> void:
	pass
