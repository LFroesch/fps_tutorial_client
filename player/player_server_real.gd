extends CharacterBody3D
class_name PlayerServerReal

const ANIM_BLEND_TIME := 0.2

@onready var animation_player: AnimationPlayer = %AnimationPlayer

func set_anim(anim_name : String) -> void:
	if animation_player.assigned_animation == anim_name:
		return
	animation_player.play(anim_name, ANIM_BLEND_TIME)
