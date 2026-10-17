extends Node
## Static tables (weapons, drones, upgrades, maps), per-run progression and the save file.
## Autoloaded as `GameData`.

const SAVE_PATH := "user://droneyard.cfg"

const L_WORLD := 1
const L_DRONE := 2
const L_ORB := 4
const L_UI := 8
const L_PICKUP := 16

const ARENA := 20.0

var FONT_STENCIL: Font
var FONT_MONO: Font
var FONT_HEAD: Font

const C_HAZARD := Color(1.0, 0.478, 0.102)
const C_PAPER := Color(0.945, 0.918, 0.863)
const C_ALARM := Color(0.91, 0.255, 0.173)
const C_SIGNAL := Color(0.494, 0.878, 0.631)
const C_SCOUT := Color(1.0, 0.788, 0.235)
const C_MUTED := Color(0.608, 0.655, 0.647)
const C_INK := Color(0.063, 0.09, 0.106)

# ---------------------------------------------------------------- weapons
# Models are the Sci-Fi Essentials Kit guns. The barrel runs along the model's -X axis;
# `grip_x` is where the hand sits along that axis and `muzzle` is the barrel tip in model space.
const WEAPONS := {
	"pistol": {
		"name": "M7 Sidearm", "model": "res://assets/guns/Gun_Pistol.gltf", "scale": 0.5,
		"grip_x": 0.02, "muzzle": Vector3(-0.37, 0.115, 0.0),
		"damage": 24.0, "rate": 0.15, "mag": 15, "reload": 1.1, "auto": false, "pierce": 1,
		"spread": 0.0, "sfx": "shot_pistol", "kick": 1.0, "cost": 0,
		"desc": "Reliable semi-auto. Hold the trigger to keep firing.",
	},
	"revolver": {
		"name": "Hammer .50", "model": "res://assets/guns/Gun_Revolver.gltf", "scale": 0.5,
		"grip_x": 0.03, "muzzle": Vector3(-0.45, 0.09, 0.0),
		"damage": 72.0, "rate": 0.42, "mag": 6, "reload": 1.5, "auto": false, "pierce": 2,
		"spread": 0.0, "sfx": "shot_revolver", "kick": 2.2, "cost": 450,
		"desc": "Six heavy rounds that punch through two drones.",
	},
	"rifle": {
		"name": "VK Carbine", "model": "res://assets/guns/Gun_Rifle.gltf", "scale": 0.42,
		"grip_x": 0.08, "muzzle": Vector3(-0.75, 0.13, 0.0),
		"damage": 15.0, "rate": 0.085, "mag": 32, "reload": 1.6, "auto": true, "pierce": 1,
		"spread": 0.012, "sfx": "shot_rifle", "kick": 0.6, "cost": 650,
		"desc": "Full-auto carbine with a deep magazine.",
	},
	"sniper": {
		"name": "Longshot", "model": "res://assets/guns/Gun_Sniper.gltf", "scale": 0.38,
		"grip_x": 0.16, "muzzle": Vector3(-1.28, 0.1, 0.0),
		"damage": 150.0, "rate": 0.85, "mag": 5, "reload": 2.0, "auto": false, "pierce": 5,
		"spread": 0.0, "sfx": "shot_sniper", "kick": 3.0, "cost": 900,
		"desc": "Rail slug that pierces everything in a line.",
	},
}
const WEAPON_ORDER := ["pistol", "revolver", "rifle", "sniper"]

# ---------------------------------------------------------------- drones
# `yaw` turns each model so it faces -Z. `weak` is the weak point as a fraction of the model's
# half-extents (z = -1 is the front face) and `weak_r` the crit radius around it in metres.
# `anims` maps behaviour slots to clip names in the model.
const DRONES := {
	"scout": {
		"name": "Seeker", "model": "res://assets/drones/Enemy_EyeDrone.gltf", "scale": 0.55, "yaw": PI,
		"hp": 35.0, "speed": 6.2, "radius": 0.3, "weak": Vector3(0, 0, -1), "weak_r": 0.17,
		"range": Vector2(5, 10), "alt": Vector2(1.3, 3.4), "fire_cd": Vector2(1.3, 2.6),
		"dmg": 7.0, "shot_speed": 10.5, "shot_r": 0.08, "shot_color": Color(1.0, 0.75, 0.2),
		"patterns": {"single": 3, "burst": 2, "lead": 2, "feint": 1},
		"score": 100, "credits": 18, "dodge": 0.9, "hum": "hum_small",
		"anims": {"idle": "Idle", "charge": "Charging", "fire": "Attack", "hit": "Hit", "dodge": "BackFlip", "look": "Look"},
	},
	"bomber": {
		"name": "Rotor Bomb", "model": "res://assets/drones/bicopter.glb", "scale": 1.7, "yaw": 0.0,
		"hp": 26.0, "speed": 5.0, "radius": 0.38, "weak": Vector3(0, 0.4, -1), "weak_r": 0.15,
		"range": Vector2(6, 11), "alt": Vector2(1.6, 4.0), "fire_cd": Vector2(2.0, 4.0),
		"dmg": 24.0, "shot_speed": 0.0, "shot_r": 0.0, "shot_color": Color(1, 0.3, 0.1),
		"patterns": {"dive": 1},
		"score": 120, "credits": 20, "dodge": 0.5, "hum": "hum_rotor",
		"anims": {"idle": "Hover", "charge": "Arm", "fire": "Dash", "hit": "Hit", "dash": "Dash"},
	},
	"stinger": {
		"name": "Stinger", "model": "res://assets/drones/bee_bot.glb", "scale": 0.55, "yaw": PI,
		"hp": 62.0, "speed": 4.4, "radius": 0.42, "weak": Vector3(0, 0.45, -1), "weak_r": 0.19,
		"range": Vector2(6, 11), "alt": Vector2(1.6, 3.6), "fire_cd": Vector2(2.0, 3.4),
		"dmg": 9.0, "shot_speed": 8.5, "shot_r": 0.1, "shot_color": Color(0.55, 1.0, 0.25),
		"patterns": {"spread": 3, "burst": 1, "lead": 1},
		"score": 160, "credits": 26, "dodge": 0.55, "hum": "hum_small",
		"anims": {"idle": "Idle", "fire": "spit_attack", "look": "head_movement", "death": "power_off"},
	},
	"sniper": {
		"name": "Sentinel", "model": "res://assets/drones/recon_drone.glb", "scale": 0.42, "yaw": 0.0,
		"hp": 70.0, "speed": 4.5, "radius": 0.44, "weak": Vector3(0, 0, -1), "weak_r": 0.19,
		"range": Vector2(13, 19), "alt": Vector2(3.0, 6.5), "fire_cd": Vector2(3.5, 5.5),
		"dmg": 22.0, "shot_speed": 34.0, "shot_r": 0.07, "shot_color": Color(1.0, 0.15, 0.2),
		"patterns": {"snipe": 1},
		"score": 220, "credits": 34, "dodge": 0.35, "hum": "hum_small",
		"anims": {"idle": "Idle", "charge": "Charge", "fire": "Fire", "hit": "Hit"},
	},
	"heavy": {
		"name": "Carrier", "model": "res://assets/drones/Enemy_Trilobite.gltf", "scale": 0.7, "yaw": PI,
		"hp": 260.0, "speed": 1.9, "radius": 0.95, "weak": Vector3(0, 0.55, -1), "weak_r": 0.4,
		"range": Vector2(9, 14), "alt": Vector2(1.4, 2.6), "fire_cd": Vector2(3.0, 4.2),
		"dmg": 16.0, "shot_speed": 5.6, "shot_r": 0.22, "shot_color": Color(1.0, 0.27, 0.17),
		"patterns": {"heavy_burst": 3, "spread": 1},
		"score": 420, "credits": 70, "dodge": 0.0, "hum": "hum_heavy", "shootable_shots": true,
		"anims": {"idle": "Hanging", "fire": "AttackAuto", "hit": "Hit", "look": "Look", "death": "TurnOff"},
	},
	"boss": {
		"name": "Warden", "model": "res://assets/drones/Enemy_Trilobite.gltf", "scale": 1.5, "yaw": PI,
		"hp": 1500.0, "speed": 1.6, "radius": 2.0, "weak": Vector3(0, 0.55, -1), "weak_r": 0.85,
		"range": Vector2(10, 15), "alt": Vector2(2.4, 4.0), "fire_cd": Vector2(2.2, 3.2),
		"dmg": 14.0, "shot_speed": 6.5, "shot_r": 0.24, "shot_color": Color(1.0, 0.2, 0.35),
		"patterns": {"heavy_burst": 2, "ring": 2, "summon": 1, "spread": 2},
		"score": 3000, "credits": 400, "dodge": 0.0, "hum": "hum_heavy", "shootable_shots": true,
		"anims": {"idle": "Hanging", "fire": "AttackAuto", "hit": "Hit", "look": "Look", "death": "TurnOff"},
	},
}

# ---------------------------------------------------------------- upgrades
const UPGRADES := {
	"damage": {"name": "Hot Cells", "desc": "+20% damage", "max": 5, "cost": 180},
	"rate": {"name": "Trigger Tune", "desc": "+14% fire rate", "max": 5, "cost": 160},
	"mag": {"name": "Deep Mag", "desc": "+35% magazine", "max": 4, "cost": 130},
	"reload": {"name": "Quick Loader", "desc": "-20% reload time", "max": 4, "cost": 120},
	"armor": {"name": "Armor Plating", "desc": "+25 max health", "max": 4, "cost": 200},
	"regen": {"name": "Nano Repair", "desc": "Faster health regen", "max": 3, "cost": 170},
	"crit": {"name": "Weak-Point Optics", "desc": "+40% weak-point damage", "max": 3, "cost": 150},
	"barrier": {"name": "Barrier Cell", "desc": "Block 1 hit each wave", "max": 3, "cost": 260},
	"overclock": {"name": "Overclock", "desc": "Grip button slows time", "max": 3, "cost": 300},
	"magnet": {"name": "Salvage Magnet", "desc": "Pull pickups from further away", "max": 2, "cost": 90},
}

# ---------------------------------------------------------------- maps
const MAPS := {
	"yard": {"name": "Drone Yard", "desc": "Concrete depot, crates and barrels. The classic range."},
	"outpost": {"name": "Red Outpost", "desc": "Mars colony domes, rocks and alien trees."},
	"lunar": {"name": "Lunar Hangar", "desc": "Low-light moon base with a rocket on the pad."},
}
const MAP_ORDER := ["yard", "outpost", "lunar"]

# ---------------------------------------------------------------- run state
var map_id := "yard"
var credits := 0
var levels := {}
var owned := ["pistol"]
var weapon := "pistol"
var best := {}  # map_id -> {"score": int, "wave": int}


func _init() -> void:
	FONT_STENCIL = load("res://assets/fonts/SairaStencilOne.ttf")
	FONT_MONO = load("res://assets/fonts/IBMPlexMono.ttf")
	FONT_HEAD = load("res://assets/fonts/SairaCondensed.ttf")


func _ready() -> void:
	load_save()


func reset_run() -> void:
	credits = 0
	levels = {}
	for k in UPGRADES: levels[k] = 0
	owned = ["pistol"]
	weapon = "pistol"


func lvl(id: String) -> int:
	return int(levels.get(id, 0))


func upgrade_cost(id: String) -> int:
	var u: Dictionary = UPGRADES[id]
	return int(round(float(u.cost) * pow(1.55, lvl(id)) / 10.0) * 10)


func can_upgrade(id: String) -> bool:
	return lvl(id) < int(UPGRADES[id].max)


func buy_upgrade(id: String) -> bool:
	var c := upgrade_cost(id)
	if not can_upgrade(id) or credits < c: return false
	credits -= c
	levels[id] = lvl(id) + 1
	return true


func buy_weapon(id: String) -> bool:
	if id in owned: return false
	var c := int(WEAPONS[id].cost)
	if credits < c: return false
	credits -= c
	owned.append(id)
	weapon = id
	return true


## Weapon stats after upgrades.
func weapon_stats(id: String) -> Dictionary:
	var w: Dictionary = WEAPONS[id].duplicate()
	w.damage = float(w.damage) * (1.0 + 0.2 * lvl("damage"))
	w.rate = float(w.rate) / (1.0 + 0.14 * lvl("rate"))
	w.mag = int(ceil(float(w.mag) * (1.0 + 0.35 * lvl("mag"))))
	w.reload = float(w.reload) * pow(0.8, lvl("reload"))
	w.crit = 2.0 + 0.4 * lvl("crit")
	return w


func max_hp() -> float:
	return 100.0 + 25.0 * lvl("armor")


func regen_rate() -> float:
	return 7.0 + 6.0 * lvl("regen")


func regen_delay() -> float:
	return 4.0 - 0.8 * lvl("regen")


func overclock_cooldown() -> float:
	return 26.0 - 6.0 * lvl("overclock")


func magnet_radius() -> float:
	return 0.7 + 1.6 * lvl("magnet")


# ---------------------------------------------------------------- save
func load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK: return
	for m in MAP_ORDER:
		best[m] = {"score": int(cf.get_value("best", m + "_score", 0)), "wave": int(cf.get_value("best", m + "_wave", 0))}
	map_id = str(cf.get_value("prefs", "map", "yard"))
	if not MAPS.has(map_id): map_id = "yard"


func save() -> void:
	var cf := ConfigFile.new()
	for m in best:
		cf.set_value("best", m + "_score", best[m].score)
		cf.set_value("best", m + "_wave", best[m].wave)
	cf.set_value("prefs", "map", map_id)
	cf.save(SAVE_PATH)


func best_for(m: String) -> Dictionary:
	return best.get(m, {"score": 0, "wave": 0})


## Records a finished run. Returns true when it beats the stored best for that map.
func record_run(score: int, wave: int) -> bool:
	var b := best_for(map_id)
	if score <= int(b.score): return false
	best[map_id] = {"score": score, "wave": wave}
	save()
	return true
