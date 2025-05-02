class_name WeaponConfig

const WEAPON_DATA := {
	0 : {"name" : "Pistol", "damage" : 35, "accuracy" : 0.9, "projectiles" : 1},
	1 : {"name" : "SMG", "damage" : 20, "accuracy" : 0.7, "projectiles" : 1},
	2 : {"name" : "Shotgun", "damage" : 18, "accuracy" : 0.4, "projectiles" : 6}
}

static func get_weapon_data(weapon_id) -> Dictionary:
	return WEAPON_DATA.get(weapon_id)
