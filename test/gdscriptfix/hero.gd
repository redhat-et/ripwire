# Fixture: the full GDScript definition surface queries/gdscript/tags.scm claims.
class_name Hero
extends Node2D

signal died(who: Node)

const MAX_HP := 100
const lowercase_const := 7

enum State { IDLE, RUN, FALL }

@export var hp: int = 10
@onready var sprite: Sprite2D = $Sprite
var velocity := Vector2.ZERO
static var spawned := 0

# Inner class: its func must land as t="method", unlike the file-scope funcs below.
class Loadout:
	var weapon_id := "sword"

	func describe() -> String:
		return weapon_id

func take_damage(amount: int) -> void:
	_apply(amount)
	sprite.set_modulate(amount)
	self.notify_died()

func _apply(amount: int) -> void:
	hp -= amount

func notify_died() -> void:
	died.emit(self)

# `hero` (lower) must stay a DISTINCT symbol from the class `Hero` (upper) — macOS's
# case-insensitive filesystem does not make the symbol table case-insensitive, and a
# collapse here would silently merge a type with a variable.
var hero := 1
