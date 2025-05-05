extends CharacterBody3D
class_name PlayerServerReal

const ANIM_BLEND_TIME := 0.2
const MAX_HEALTH := 100

var current_health := MAX_HEALTH
var lobby : Lobby
var grenades_left := 2

@onready var animation_player: AnimationPlayer = %AnimationPlayer

func set_anim(anim_name : String) -> void:
	if animation_player.assigned_animation == anim_name:
		return
	animation_player.play(anim_name, ANIM_BLEND_TIME)

func change_health(amount : int, maybe_damage_dealer : int = 0) -> void:
	current_health = clampi(current_health + amount, 0, MAX_HEALTH)
	
	if current_health <= 0:
		die(maybe_damage_dealer)
	
	lobby.update_health(name.to_int(), current_health, MAX_HEALTH, amount)
		
func die(killer_id : int) -> void:
	print(name, " died")
	lobby.player_died(name.to_int(), killer_id)

func update_grenades_left(new_amount : int) -> void:
	grenades_left = new_amount
	lobby.update_grenades_left(name.to_int(), grenades_left)
