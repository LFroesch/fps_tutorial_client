extends CharacterBody3D
class_name PlayerServerReal

const ANIM_BLEND_TIME := 0.2
const MAX_HEALTH := 100

var current_health := MAX_HEALTH
var lobby : Lobby

@onready var animation_player: AnimationPlayer = %AnimationPlayer

func set_anim(anim_name : String) -> void:
	if animation_player.assigned_animation == anim_name:
		return
	animation_player.play(anim_name, ANIM_BLEND_TIME)

func change_health(amount : int) -> void:
	current_health = clampi(current_health + amount, 0, MAX_HEALTH)
	
	if current_health <= 0:
		die()
	
	lobby.update_health(name.to_int(), current_health, MAX_HEALTH, amount)
		
func die() -> void:
	print(name, " died")
