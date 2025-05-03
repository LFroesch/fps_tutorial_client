extends Node3D
class_name Pickup

@onready var cooldown_timer: Timer = $CooldownTimer

enum PickupTypes {
	Health,
	Grenade
}

@export var pickup_type := PickupTypes.Health
@export var cooldown_time := 10.0

var lobby : Lobby

var is_picked := false

func _ready() -> void:
	cooldown_timer.wait_time = cooldown_time

func _on_body_entered(player: PlayerServerReal) -> void:
	if is_picked:
		return
		
	match pickup_type:
		PickupTypes.Health:
			if player.current_health < player.MAX_HEALTH:
				player.change_health(75)
				is_picked = true
				cooldown_timer.start()
				lobby.pickup_cooldown_started(name)

func _on_cooldown_timer_timeout() -> void:
	is_picked = false
	lobby.pickup_cooldown_ended(name)
