extends Node3D
class_name Lobby

const WORLD_STATE_SEND_FRAME := 3
const WORLD_STATES_TO_REMEMBER := 60
const DEATH_COOLDOWN_LENGTH := 2
const MATCH_LENGTH_SEC := 300
const TEAM_SCORE_TO_WIN := 15

enum {
	IDLE,
	LOCKED,
	GAME,
	FINISHED
}

var status := IDLE

var client_data := {}
var ready_clients : Array[int] = []
var current_world_state := {"ps" : {}, "t" : 0, "gr" : {}} # ps = player states, t = time, gr = grenades
var server_players := {} 
var previous_world_states : Array[Dictionary] = []
var pickups : Array[Pickup] = []
var spawn_points : Array[Node3D] = []
var grenades := {}

var match_time_left := MATCH_LENGTH_SEC
var match_timer := Timer.new()

func _get_time_string() -> String:
	var datetime = Time.get_datetime_dict_from_system()
	return "[%02d:%02d:%02d] -" % [datetime.hour, datetime.minute, datetime.second]

func _ready() -> void:
	set_physics_process(false)
	add_child(match_timer)
	match_timer.timeout.connect(match_timer_sec_passed)

func _physics_process(delta: float) -> void:
	if Engine.get_physics_frames() % WORLD_STATE_SEND_FRAME == 0:
		current_world_state.t = floori(Time.get_unix_time_from_system() * 1000)
		update_grenades_in_world_state()
		
		for client_id in client_data.keys():
			s_send_world_state.rpc_id(client_id, current_world_state)
			
	while previous_world_states.size() >= WORLD_STATES_TO_REMEMBER:
		previous_world_states.pop_back()
		
	for client_id in server_players.keys():
		if not current_world_state.ps.has(client_id):
			continue
			
		current_world_state.ps[client_id]["anim_pos"] = server_players.get(client_id).real.animation_player.current_animation_position
	previous_world_states.push_front(current_world_state.duplicate(true))
	
func update_grenades_in_world_state() -> void:
	for grenade_name in grenades.keys():
		current_world_state.gr[grenade_name] = {"tform" : grenades.get(grenade_name).transform}
	
@rpc("authority", "call_remote", "unreliable_ordered")
func s_send_world_state(new_world_state : Dictionary) -> void:
	pass

func add_client(id : int, player_name : String) -> void:
	client_data[id] = {"display_name" : player_name, "kills" : 0, "deaths" : 0}
	
func remove_client(id : int) -> void:
	client_data.erase(id)

@rpc("any_peer", "call_remote", "reliable")
func c_lock_client() -> void:
	var client_id := multiplayer.get_remote_sender_id()
	if not client_id in client_data.keys() or client_id in ready_clients:
		return
	ready_clients.append(client_id)
	
	for maybe_ready_client in client_data.keys():
		if not maybe_ready_client in ready_clients:
			return
			
	start_loading_map()
	ready_clients.clear()
	
func start_loading_map() -> void:
	var map = load("res://maps/server_map.tscn").instantiate()
	map.name = "Map"
	add_child(map, true)
	
	var spawn_point_holder = map.get_node("SpawnPoints")
	if spawn_point_holder != null: # NOT GROUPS BECAUSE THESE ARE LOCAL TO EACH LOBBY
		for spawn_point in spawn_point_holder.get_children():
			spawn_points.append(spawn_point)
			
	var pickup_holder = map.get_node("Pickups")
	if pickup_holder != null: # NOT GROUPS BECAUSE THESE ARE LOCAL TO EACH LOBBY
		for maybe_pickup in pickup_holder.get_children():
			if maybe_pickup is Pickup:
				maybe_pickup.lobby = self
				pickups.append(maybe_pickup)
			
	for ready_client in ready_clients:
		s_start_loading_map.rpc_id(ready_client)


# TODO IF MULTIPLE MAPS - WILL NEED TO PASS THE MAP ID HERE AND IN WRAPPER ABOVE
@rpc("authority", "call_remote", "reliable")
func s_start_loading_map() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func c_map_ready() -> void:
	var client_id := multiplayer.get_remote_sender_id()
	if not client_id in client_data.keys() or client_id in ready_clients:
		return
	ready_clients.append(client_id)
	
	for pickup in pickups:
		s_spawn_pickup.rpc_id(client_id, pickup.name, pickup.pickup_type, pickup.position)
	
	for maybe_ready_client in client_data.keys():
		if not maybe_ready_client in ready_clients:
			return
	
	for ready_client_id in ready_clients:
		s_start_weapon_selection.rpc_id(ready_client_id)
		
	ready_clients.clear()

@rpc("authority", "call_remote", "reliable")
func s_spawn_pickup(pickup_name : String, pickup_type : int, pos : Vector3) -> void:
	pass

func spawn_players() -> void:
	var blue_spawn_points : Array[Node3D] = []
	var red_spawn_points : Array[Node3D] = []
	
	for spawn_point in spawn_points:
		if spawn_point.name.begins_with("Blue"):
			blue_spawn_points.append(spawn_point)
		elif spawn_point.name.begins_with("Red"):
			red_spawn_points.append(spawn_point)
	
	ready_clients.shuffle()
	for i in ready_clients.size():
		var team := 0
		var spawn_tform := Transform3D.IDENTITY
		
		if i % 2 == 0:
			team = 0
			spawn_tform = blue_spawn_points[0].transform
			blue_spawn_points.pop_front()
		else:
			team = 1
			spawn_tform = red_spawn_points[0].transform
			red_spawn_points.pop_front()
		
		spawn_server_player(ready_clients[i], spawn_tform, team)
		
		for ready_client_id in ready_clients:
			s_spawn_player.rpc_id(
				ready_client_id,
				ready_clients[i],
				spawn_tform,
				team,
				client_data.get(ready_clients[i]).display_name,
				client_data.get(ready_clients[i]).weapon_id,
				true
			)

func spawn_server_player(client_id : int, spawn_tform : Transform3D, team : int):
	var server_player_real := preload("res://player/player_server_real.tscn").instantiate()
	var server_player_dummy := preload("res://player/player_server_dummy.tscn").instantiate()
	server_player_real.name = str(client_id)
	server_player_dummy.name = str(client_id) + "_dummy"
	server_player_real.global_transform = spawn_tform
	server_player_real.lobby = self
	server_player_dummy.id = client_id
	add_child(server_player_real, true)
	add_child(server_player_dummy, true)
	server_players[client_id] = {}
	server_players[client_id].real = server_player_real
	server_players[client_id].dummy = server_player_dummy
	client_data[client_id].team = team
		
@rpc("authority", "call_remote", "reliable")
func s_spawn_player(client_id: int, spawn_tform : Transform3D, team : int, player_name : String, weapon_id : int, auto_freeze: bool):
	pass

@rpc("authority", "call_remote", "reliable")
func s_start_match() -> void:
	pass 

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_send_player_state(player_state : Dictionary) -> void:
	var client_id := multiplayer.get_remote_sender_id()
	
	if not server_players.has(client_id):
		return
		
	current_world_state.ps[client_id] = player_state
	server_players.get(client_id).real.position = player_state.pos
	server_players.get(client_id).real.rotation.y = player_state.rot_y
	server_players.get(client_id).real.set_anim(player_state.anim)


@rpc("authority", "call_remote", "reliable")
func s_start_weapon_selection() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func c_weapon_selected(weapon_id : int) -> void:
	var weapons := ["Pistol", "SMG", "Shotgun"]
	var client_id := multiplayer.get_remote_sender_id()
	if not client_id in client_data.keys() or client_id in ready_clients:
		return
	client_data[client_id].weapon_id = weapon_id
	
	if status == GAME:
		respawn_player(client_id)
		return
	
	ready_clients.append(client_id)
	for maybe_ready_client in client_data.keys():
		if not maybe_ready_client in ready_clients:
			return
	#print("%s Client (%d) chose weapon %d - %s" % [_get_time_string(), client_id, weapon_id, weapons[weapon_id]])
	start_match()

func start_match() -> void:
	status = GAME
	spawn_players()
	
	
	await get_tree().create_timer(1).timeout
	
	for ready_client_id in ready_clients:
		s_start_match.rpc_id(ready_client_id)
	
	ready_clients.clear()
	set_physics_process(true)
	update_match_time_left()
	match_timer.start()

func respawn_player(respawn_client_id : int) -> void:
	var team : int = client_data.get(respawn_client_id).team
	var team_prefix := "Blue" if team == 0 else "Red"
	var possible_spawn_points : Array[Node3D] = []
	
	for spawn_point in spawn_points:
		if spawn_point.name.begins_with(team_prefix):
			possible_spawn_points.append(spawn_point)
			
	var spawn_point : Node3D = possible_spawn_points.pick_random()
	
	spawn_server_player(respawn_client_id, spawn_point.transform, team)
	
	for client_id in client_data.keys():
			s_spawn_player.rpc_id(
				client_id,
				respawn_client_id,
				spawn_point.transform,
				team,
				client_data.get(respawn_client_id).display_name,
				client_data.get(respawn_client_id).weapon_id,
				false
			)

@rpc("any_peer", "call_remote", "unreliable")
func c_shot_fired(time_stamp : int, player_data : Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	#print("%s %d has shot a bullet" % [_get_time_string(), sender_id])
	for client_id in client_data.keys():
		if client_id != sender_id:
			s_play_shoot_fx.rpc_id(client_id, sender_id)
	
	if sender_id in server_players.keys():
		calculate_shot_results(sender_id, time_stamp, player_data)

func calculate_shot_results(shooter_id : int, time_stamp : int, player_data : Dictionary) -> void:
	var target_time := time_stamp - 100 # 100 ms buffering delay from client
	var target_world_state : Dictionary
	
	for world_state in previous_world_states:
		if world_state.t < target_time:
			target_world_state = world_state
			break
			
	if target_world_state == null:
		return
	
	for client_id in target_world_state.ps.keys():
		if not client_id in server_players.keys():
			continue
			
		
		if not client_id in previous_world_states[0].ps.keys():
			continue
			
		if client_id == shooter_id:
			server_players.get(client_id).dummy.update_body_geometry(player_data)
			continue
			
		if not target_world_state.ps.get(client_id).is_empty():
			server_players.get(client_id).dummy.update_body_geometry(target_world_state.ps.get(client_id))
	
	await get_tree().physics_frame
	
	if not shooter_id in server_players.keys():
		return
	var weapon_data := WeaponConfig.get_weapon_data(client_data.get(shooter_id).weapon_id)
	var space_state = get_world_3d().direct_space_state
	var shooter_dummy : ServerPlayerDummy = server_players.get(shooter_id).dummy
	var ray_params := PhysicsRayQueryParameters3D.new()
	var head_tform := shooter_dummy.head.global_transform
	
	ray_params.from = shooter_dummy.head.global_position
	ray_params.collide_with_areas = true
	ray_params.exclude = shooter_dummy.hitboxes
	ray_params.collision_mask = 16 + 4 # 16 = environment_exact, 4 = hitboxes
	
	for i in weapon_data.projectiles:
		var rand_rot : float = deg_to_rad(randf() * (1 - weapon_data.accuracy) * 5) # 5 is the max degree of inaccuracy
		var shoot_tform := head_tform.rotated_local(Vector3.FORWARD, randf() * PI * 2)
		shoot_tform = shoot_tform.rotated_local(Vector3.UP, rand_rot)
		ray_params.to = ray_params.from + shoot_tform.basis.z * -100 # 100 is the range
		var result := space_state.intersect_ray(ray_params)
		if result.is_empty():
			return
		if result.collider is HitBox:
			var hurt_client_id = result.collider.player.id
			
			if not server_players.has(hurt_client_id):
				continue # if dead 
			if client_data.get(shooter_id).team == client_data.get(hurt_client_id).team:
				continue # if friendly fire
			var hurt_server_player : PlayerServerReal = server_players.get(hurt_client_id).real
			var base_damage = -weapon_data.damage * result.collider.damage_multiplier
			var damage_falloff_start := 10
			var damage_falloff_end := 20
			var damage_max_falloff := 0.4
			var distance = ray_params.from.distance_to(result.position)
			var damage_falloff_multiplier = remap(distance, damage_falloff_start, damage_falloff_end, 1, damage_max_falloff)
			damage_falloff_multiplier = clampf(damage_falloff_multiplier, damage_max_falloff, 1)
			var damage_dealt = base_damage * damage_falloff_multiplier
			hurt_server_player.change_health(damage_dealt, shooter_id)
			#print(result.collider.player.name + " hit by bullet")
			spawn_bullet_hit_fx(result.position - global_position, result.normal, 1)
		else:
			spawn_bullet_hit_fx(result.position - global_position, result.normal, 0)
		
func spawn_bullet_hit_fx(pos: Vector3, normal : Vector3, type: int) -> void:
	# 0 environment, 1 player
	for client_id in client_data.keys():
		s_spawn_bullet_hit_fx.rpc_id(client_id, pos, normal, type)
		
@rpc("authority", "call_remote", "unreliable")
func s_spawn_bullet_hit_fx(pos: Vector3, normal : Vector3, type: int) -> void:
	pass

@rpc("authority", "call_remote", "unreliable")
func s_play_shoot_fx(target_client_id : int) -> void:
	pass

func update_health(target_client_id : int, current_health : int, max_health : int, changed_amount: int) -> void:
	for client_id in client_data.keys():
		s_update_health.rpc_id(client_id, target_client_id, current_health, max_health, changed_amount)
		
@rpc("authority", "call_remote", "unreliable_ordered")
func s_update_health(target_client_id : int, current_health : int, max_health : int, changed_amount: int) -> void:
	pass

func pickup_cooldown_started(pickup_name : String) -> void:
	for client_id in client_data.keys():
		s_pickup_cooldown_started.rpc_id(client_id, pickup_name)

@rpc("authority", "call_remote", "reliable")
func s_pickup_cooldown_started(pickup_name : String) -> void:
	pass
	
func pickup_cooldown_ended(pickup_name : String) -> void:
	for client_id in client_data.keys():
		s_pickup_cooldown_ended.rpc_id(client_id, pickup_name)

@rpc("authority", "call_remote", "reliable")
func s_pickup_cooldown_ended(pickup_name : String) -> void:
	pass

func player_died(dead_player_id : int, killer_id : int) -> void:
	server_players.get(dead_player_id).real.queue_free()
	server_players.get(dead_player_id).dummy.queue_free()
	server_players.erase(dead_player_id)
	current_world_state.ps.erase(dead_player_id)
	
	client_data.get(dead_player_id).deaths += 1
	if dead_player_id != killer_id:
		client_data.get(dead_player_id).kills += 1
	
	for client_id in client_data.keys():
		s_player_died.rpc_id(client_id, dead_player_id)
		
	update_game_scores()
	await get_tree().create_timer(DEATH_COOLDOWN_LENGTH).timeout
	s_start_weapon_selection.rpc_id(dead_player_id)
	
@rpc("authority", "call_remote", "reliable")
func s_player_died(dead_player_id : int) -> void:
	pass

func update_game_scores() -> void:
	var blue_team_kills := 0
	var red_team_kills := 0
	
	for data in client_data.values():
		if data.team == 0:
			red_team_kills += data.deaths
		else:
			blue_team_kills += data.deaths
			
	for client_id in client_data.keys():
		s_update_game_scores.rpc_id(client_id, blue_team_kills, red_team_kills)
	
	if blue_team_kills >= TEAM_SCORE_TO_WIN or red_team_kills >= TEAM_SCORE_TO_WIN:
		end_match()
		
@rpc("authority", "call_remote", "reliable")
func s_update_game_scores(blue_score : int, red_score : int) -> void:
	pass

func match_timer_sec_passed() -> void:
	match_time_left -= 1
	update_match_time_left()
	if match_time_left <= 0:
		end_match()

func update_match_time_left() -> void:
	for client_id in client_data.keys():
		s_update_match_time_left.rpc_id(client_id, match_time_left)

@rpc("authority", "call_remote", "unreliable_ordered")
func s_update_match_time_left(time_left : int) -> void:
	pass

func end_match() -> void:
	status = FINISHED
	match_timer.stop()
	set_physics_process(false)
	
	for client_id in client_data.keys():
		s_end_match.rpc_id(client_id, client_data)
		
	Server.delete_lobby(self)
	
@rpc("authority", "call_remote", "reliable")
func s_end_match(end_client_data : Dictionary) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func c_try_throw_grenade(player_state : Dictionary) -> void:
	var client_id := multiplayer.get_remote_sender_id()
	
	if not server_players.has(client_id):
		return
		
	var player : PlayerServerReal = server_players.get(client_id).real
	
	if player.grenades_left <= 0:
		return
		
	player.grenades_left -= 1
	s_update_grenades_left.rpc_id(client_id, player.grenades_left)
	
	var grenade : Grenade = preload("res://player/grenade/grenade.tscn").instantiate()
	var direction := Vector3.FORWARD
	direction = direction.rotated(Vector3.RIGHT, player_state.rot_x)
	direction = direction.rotated(Vector3.UP, player_state.rot_y)
	
	grenade.set_data(self, direction, player)
	grenade.position = player_state.pos + Vector3.UP * 1.2
	
	grenade.name = str(grenade.get_instance_id())
	add_child(grenade, true)
	grenades[grenade.name] = grenade
	
@rpc("authority", "call_remote", "unreliable_ordered")
func s_update_grenades_left(grenades_left : int) -> void:
	pass

func grenade_exploded(grenade : Grenade) -> void:
	var grenade_name = grenade.name
	
	grenades.erase(grenade_name)
	current_world_state.gr.erase(grenade_name)
	grenade.queue_free()
	
	for client_id in client_data.keys():
		s_explode_grenade.rpc_id(client_id, grenade_name)
		
@rpc("authority", "call_remote", "reliable")
func s_explode_grenade(grenade_name : String) -> void:
	pass
