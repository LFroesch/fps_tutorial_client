extends Node3D
class_name Lobby

const WORLD_STATE_SEND_FRAME := 3
const WORLD_STATES_TO_REMEMBER := 60

enum {
	IDLE,
	LOCKED,
	GAME
}

var status := IDLE

var client_data := {}
var ready_clients : Array[int] = []
var current_world_state := {"ps" : {}, "t" : 0} # ps = player states, t = time
var server_players := {} 
var previous_world_states : Array[Dictionary] = []

func _get_time_string() -> String:
	var datetime = Time.get_datetime_dict_from_system()
	return "[%02d:%02d:%02d] -" % [datetime.hour, datetime.minute, datetime.second]

func _ready() -> void:
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	if Engine.get_physics_frames() % WORLD_STATE_SEND_FRAME == 0:
		current_world_state.t = floori(Time.get_unix_time_from_system() * 1000)
		for client_id in client_data.keys():
			s_send_world_state.rpc_id(client_id, current_world_state)
	while previous_world_states.size() >= WORLD_STATES_TO_REMEMBER:
		previous_world_states.pop_back()
	for client_id in server_players.keys():
		if not current_world_state.ps.has(client_id):
			continue
			
		current_world_state.ps[client_id]["anim_pos"] = server_players.get(client_id).real.animation_player.current_animation_position
	previous_world_states.push_front(current_world_state.duplicate(true))
@rpc("authority", "call_remote", "unreliable_ordered")
func s_send_world_state(new_world_state : Dictionary) -> void:
	pass

func add_client(id : int, player_name : String) -> void:
	client_data[id] = {"display_name" : player_name}
	
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
	
	for maybe_ready_client in client_data.keys():
		if not maybe_ready_client in ready_clients:
			return
	
	for ready_client_id in ready_clients:
		s_start_weapon_selection.rpc_id(ready_client_id)
		
	ready_clients.clear()

func spawn_players() -> void:
	var spawn_points = get_tree().get_nodes_in_group("SpawnPoints")
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
		
		spawn_server_player(ready_clients[i], spawn_tform)
		
		for ready_client_id in ready_clients:
			s_spawn_player.rpc_id(
				ready_client_id,
				ready_clients[i],
				spawn_tform,
				team,
				client_data.get(ready_clients[i]).display_name,
				client_data.get(ready_clients[i]).weapon_id
			)

func spawn_server_player(client_id : int, spawn_tform : Transform3D):
	var server_player_real := preload("res://player/player_server_real.tscn").instantiate()
	var server_player_dummy := preload("res://player/player_server_dummy.tscn").instantiate()
	server_player_real.name = str(client_id)
	server_player_dummy.name = str(client_id) + "_dummy"
	server_player_real.global_transform = spawn_tform
	add_child(server_player_real, true)
	add_child(server_player_dummy, true)
	server_players[client_id] = {}
	server_players[client_id].real = server_player_real
	server_players[client_id].dummy = server_player_dummy
		
@rpc("authority", "call_remote", "reliable")
func s_spawn_player(client_id: int, spawn_tform : Transform3D, team : int, player_name : String, weapon_id : int):
	pass

@rpc("authority", "call_remote", "reliable")
func s_start_match() -> void:
	pass 

@rpc("any_peer", "call_remote", "unreliable_ordered")
func c_send_player_state(player_state : Dictionary) -> void:
	current_world_state.ps[multiplayer.get_remote_sender_id()] = player_state

@rpc("authority", "call_remote", "reliable")
func s_start_weapon_selection() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func c_weapon_selected(weapon_id : int) -> void:
	var weapons := ["Pistol", "SMG", "Shotgun"]
	var client_id := multiplayer.get_remote_sender_id()
	if not client_id in client_data.keys() or client_id in ready_clients:
		return
	ready_clients.append(client_id)
	client_data[client_id].weapon_id = weapon_id
	for maybe_ready_client in client_data.keys():
		if not maybe_ready_client in ready_clients:
			return
	#print("%s Client (%d) chose weapon %d - %s" % [_get_time_string(), client_id, weapon_id, weapons[weapon_id]])
	spawn_players()
	
	await get_tree().create_timer(1).timeout
	
	for ready_client_id in ready_clients:
		s_start_match.rpc_id(ready_client_id)
	
	ready_clients.clear()
	set_physics_process(true)

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
