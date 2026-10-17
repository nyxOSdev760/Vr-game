class_name Drone
extends CharacterBody3D
## A hostile drone. Drives the model's own skeletal/keyframe animations from an AI that is
## deliberately hard to read: every drone rolls a personality, drifts on its own noise field,
## picks its next move from weighted random choices, flanks, feints, and dodges when it notices
## a gun pointed at it.

signal died(drone: Drone, by_player: bool)

const ENTER_TIME := 0.7

var type := ""
var cfg := {}
var game: Node
var hp := 1.0
var max_hp := 1.0
var elite := ""
var alive := true

var state := "enter"
var state_t := 0.0
var fire_t := 2.0
var dodge_cd := 0.0
var spawn_t := ENTER_TIME
var target := Vector3.ZERO
var target_alt := 2.0
var orbit_dir := 1.0
var pattern := ""
var shots_left := 0
var shot_t := 0.0
var dive_from := Vector3.ZERO
var dive_ctrl := Vector3.ZERO
var dive_k := 0.0
var dive_abort := false
var stuck_t := 0.0
var t := 0.0

# personality, rolled per drone
var aggression := 0.5
var jitter := 0.5
var pref_range := 8.0
var dodge_skill := 0.5
var speed := 4.0
var lead_bias := 0.5

var _pivot: Node3D
var _model: Node3D
var _ap: AnimationPlayer
var _anim := {}
var _half := Vector3.ONE * 0.3
var _center := Vector3.ZERO
var _weak_local := Vector3.ZERO
var _overlay: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _flash := 0.0
var _tint := Color(0, 0, 0, 0)
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _laser: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _laser_aim := Vector3.ZERO
var _hum: AudioStreamPlayer3D
var _noise := FastNoiseLite.new()
var _dying := 0.0
var _death_spin := Vector3.ZERO


func setup(p_type: String, p_game: Node, p_elite := "") -> void:
	type = p_type
	cfg = GameData.DRONES[type]
	game = p_game
	elite = p_elite
	collision_layer = GameData.L_DRONE
	collision_mask = GameData.L_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	set_meta("drone", self)

	_noise.seed = randi()
	_noise.frequency = 0.35
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH

	var wave: int = game.wave
	aggression = randf_range(0.2, 1.0)
	jitter = randf_range(0.25, 1.0)
	dodge_skill = clampf(float(cfg.dodge) * randf_range(0.6, 1.3) + 0.02 * wave, 0.0, 1.3)
	var r: Vector2 = cfg.range
	pref_range = randf_range(r.x, r.y)
	speed = float(cfg.speed) * randf_range(0.85, 1.2) * (1.0 + 0.015 * wave)
	lead_bias = randf()
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	max_hp = float(cfg.hp) * (1.0 + 0.06 * maxi(0, wave - 1))
	var fc: Vector2 = cfg.fire_cd
	fire_t = randf_range(fc.x, fc.y) * 0.8

	match elite:
		"swift":
			speed *= 1.4
			dodge_skill += 0.45
			_tint = Color(0.15, 0.7, 1.0)
		"shielded":
			max_hp *= 1.9
			_tint = Color(0.35, 0.45, 1.0)
		"volatile":
			_tint = Color(1.0, 0.25, 0.1)
	hp = max_hp

	_pivot = Node3D.new()
	add_child(_pivot)
	_model = (load(cfg.model) as PackedScene).instantiate()
	_model.scale = Vector3.ONE * float(cfg.scale)
	_model.rotation.y = float(cfg.yaw)
	_pivot.add_child(_model)
	var box := _local_aabb(_model, _model.transform)
	_center = box.get_center()
	_half = box.size * 0.5
	_model.position -= _center
	var wf: Vector3 = cfg.weak
	_weak_local = wf * _half

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size * 0.85
	cs.shape = bs
	add_child(cs)

	for m in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(m)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(0, 0, 0, 0)
	if elite != "": _set_overlay(true)

	_ap = _model.find_child("AnimationPlayer", true, false)
	if _ap:
		var names := _ap.get_animation_list()
		var slots: Dictionary = cfg.anims
		for slot in slots:
			var want: String = slots[slot]
			for n in names:
				if n == want or n.ends_with("|" + want):
					_anim[slot] = n
					break
		for slot in ["idle", "look", "dash"]:
			if _anim.has(slot):
				var a := _ap.get_animation(_anim[slot])
				if a: a.loop_mode = Animation.LOOP_LINEAR
		_ap.playback_default_blend_time = 0.15
		_play("idle")
		_ap.seek(randf() * 1.0, true)

	# charge glow at the weapon point: a billboard sprite that swells before each shot
	_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_glow.mesh = q
	_glow_mat = FX.additive_material(cfg.shot_color, FX.glow_tex)
	_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.position = _weak_local + Vector3(0, 0, -0.05)
	_glow.visible = false
	_pivot.add_child(_glow)
	if type == "heavy" or type == "boss":
		# the core weak point glows so players know where to aim
		var core := MeshInstance3D.new()
		core.mesh = q
		var cm := FX.additive_material(Color(1.0, 0.35, 0.2, 0.75), FX.glow_tex)
		cm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		core.material_override = cm
		core.scale = Vector3.ONE * float(cfg.weak_r) * 2.2
		core.position = _weak_local
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pivot.add_child(core)

	if type == "sniper":
		_laser = MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1, 1, 1)
		_laser.mesh = lb
		_laser_mat = FX.additive_material(Color(1, 0.1, 0.12, 0.5))
		_laser.material_override = _laser_mat
		_laser.top_level = true
		_laser.visible = false
		_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_laser)

	_hum = Sfx.make_loop(str(cfg.hum), self, -15.0 if type != "boss" else -6.0, randf_range(0.9, 1.15))
	_pivot.scale = Vector3.ONE * 0.2


func _local_aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.get_children():
		var ct := xf
		if c is Node3D: ct = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var b := ct * (c as MeshInstance3D).get_aabb()
			if first:
				out = b
				first = false
			else:
				out = out.merge(b)
		var sub := _local_aabb(c, ct)
		if sub.size != Vector3.ZERO:
			if first:
				out = sub
				first = false
			else:
				out = out.merge(sub)
	return out


func _play(slot: String, speed_scale := 1.0, restart := false) -> bool:
	if not _ap or not _anim.has(slot): return false
	var n: String = _anim[slot]
	if restart or _ap.current_animation != n:
		_ap.play(n, -1, speed_scale)
		if restart: _ap.seek(0.0, true)
	return true


func _play_once(slot: String, then := "idle", speed_scale := 1.0) -> bool:
	if not _play(slot, speed_scale, true): return false
	if _anim.has(then) and then != slot: _ap.queue(_anim[then])
	return true


func _set_overlay(on: bool) -> void:
	for m in _meshes: m.material_overlay = _overlay if on else null


func weak_point_global() -> Vector3:
	return _pivot.global_transform * _weak_local


func center() -> Vector3:
	return global_position


# ---------------------------------------------------------------- damage
## Returns true when the hit landed on a live drone.
func take_damage(amount: float, _weak_hint: bool, dir: Vector3, at: Vector3) -> bool:
	if not alive: return false
	var crit := at.distance_to(weak_point_global()) <= float(cfg.weak_r)
	var mult: float = GameData.weapon_stats(GameData.weapon).crit if crit else 1.0
	var d := amount * mult
	if spawn_t > 0.0: d *= 0.5
	hp -= d
	_flash = 0.12
	_set_overlay(true)
	velocity += dir * (2.0 if type != "boss" and type != "heavy" else 0.4)
	FX.number(at, d, crit)
	if crit: Sfx.play_at("crit", at, -8.0, 1.3)
	if hp <= 0.0:
		die(true)
		return true
	# getting hit often sparks a reaction
	if randf() < 0.35 * jitter and state != "dive" and state != "aim" and type != "boss" and type != "heavy":
		_start_dodge(dir)
	elif not _play_once("hit", "idle"):
		pass
	if hp < max_hp * 0.35 and randf() < 0.4 and type != "bomber" and type != "boss":
		_set_state("retreat", randf_range(1.5, 3.0))
		target = _point_away(randf_range(14.0, 18.0))
	return true


func die(by_player: bool) -> void:
	if not alive: return
	alive = false
	collision_layer = 0
	_glow.visible = false
	if _laser: _laser.visible = false
	if _hum: _hum.stop()
	_dying = 0.55 if type != "boss" else 1.6
	if type == "bomber" and not by_player: _dying = 0.0
	_death_spin = Vector3(randf_range(-3, 3), randf_range(-6, 6), randf_range(-3, 3))
	if not _play("death", 1.4, true): _play("hit", 0.6, true)
	died.emit(self, by_player)


func _explode() -> void:
	var size := clampf(_half.length() * 1.6, 0.7, 4.0)
	FX.explode(global_position, size, cfg.shot_color)
	FX.ring(Vector3(global_position.x, 0.05, global_position.z), cfg.shot_color, size * 2.2, 0.6)
	Sfx.play_at("explode_big" if type == "boss" or type == "heavy" else ("explode1" if randf() < 0.5 else "explode2"), global_position, 2.0 if type == "boss" else 0.0)
	if elite == "volatile" or type == "bomber":
		var ph: Vector3 = game.player.head_position()
		var dd := ph.distance_to(global_position)
		if dd < 3.0: game.player.hurt(float(cfg.dmg if type == "bomber" else 14.0) * (1.0 - dd / 3.5), (ph - global_position).normalized())
	queue_free()


# ---------------------------------------------------------------- AI helpers
func _set_state(s: String, dur: float) -> void:
	state = s
	state_t = dur


func _player_head() -> Vector3:
	return game.player.head_position()


func _flat_dir_to_player() -> Vector3:
	var d := _player_head() - global_position
	d.y = 0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


func _random_alt() -> float:
	var a: Vector2 = cfg.alt
	return randf_range(a.x, a.y)


## A point around the player, biased toward the flanks and behind them.
func _flank_point(dist: float) -> Vector3:
	var p := _player_head()
	var from := global_position - p
	from.y = 0
	var base := atan2(from.x, from.z)
	var swing := randf_range(0.6, 2.4) * (1.0 if randf() < 0.5 else -1.0) * (0.4 + aggression)
	var a := base + swing
	var pt := p + Vector3(sin(a), 0, cos(a)) * dist
	return _clamp_arena(pt)


func _point_away(dist: float) -> Vector3:
	var d := global_position - _player_head()
	d.y = 0
	if d.length() < 0.1: d = Vector3(randf() - 0.5, 0, randf() - 0.5)
	d = d.normalized().rotated(Vector3.UP, randf_range(-0.8, 0.8))
	return _clamp_arena(_player_head() + d * dist)


func _clamp_arena(p: Vector3) -> Vector3:
	var L := GameData.ARENA - 1.5
	return Vector3(clampf(p.x, -L, L), p.y, clampf(p.z, -L, L))


func _has_los() -> bool:
	var from := weak_point_global()
	var to := _player_head()
	var q := PhysicsRayQueryParameters3D.create(from, to, GameData.L_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _aimed_at() -> Vector3:
	## Returns the aim direction of a gun pointed at this drone, or ZERO.
	for g in game.player.guns:
		var gun: Gun = g
		if not gun.is_visible_in_tree(): continue
		var o := gun.muzzle_position()
		var d := -gun.aim_basis().z
		var v := global_position - o
		var along := v.dot(d)
		if along < 0.5: continue
		var off := (v - d * along).length()
		if off < _half.length() + 0.35 + along * 0.02: return d
	return Vector3.ZERO


func _start_dodge(threat_dir: Vector3) -> void:
	var side := threat_dir.cross(Vector3.UP).normalized()
	if side.length() < 0.1: side = Vector3.RIGHT
	if randf() < 0.5: side = -side
	var up := randf_range(-0.6, 0.9)
	velocity = (side + Vector3(0, up, 0)).normalized() * speed * randf_range(1.5, 2.3)
	_set_state("dodge", randf_range(0.3, 0.5))
	dodge_cd = randf_range(0.9, 2.6) / maxf(0.3, dodge_skill)
	if not _play_once("dodge", "idle", 1.6): _play_once("hit", "idle")
	if randf() < 0.5: Sfx.play_at("dash", global_position, -10.0, 1.4)


func _pick_next() -> void:
	var dist := global_position.distance_to(_player_head())
	var weights := {
		"reposition": 2.0 + jitter * 2.0,
		"strafe": 3.0,
		"hold": 0.6,
	}
	var can_attack: bool = game.state == "playing"
	if fire_t <= 0.0 and dist < 40.0 and can_attack: weights["attack"] = 5.0 + aggression * 4.0
	if dist < pref_range * 0.6: weights["reposition"] += 3.0
	if type == "sniper":
		weights = {"reposition": 1.0, "hold": 0.4}
		if fire_t <= 0.0 and can_attack: weights["attack"] = 6.0
	if type == "bomber" and fire_t <= 0.0 and can_attack: weights["attack"] = 6.0 + aggression * 6.0
	var total := 0.0
	for k in weights: total += weights[k]
	var roll := randf() * total
	var choice := "strafe"
	for k in weights:
		roll -= weights[k]
		if roll <= 0.0:
			choice = k
			break
	match choice:
		"reposition":
			var dd := pref_range * randf_range(0.7, 1.3)
			target = _flank_point(dd)
			target_alt = _random_alt()
			_set_state("reposition", randf_range(1.6, 3.2))
			if randf() < 0.3: _play_once("look", "idle")
		"strafe":
			if randf() < 0.45: orbit_dir = -orbit_dir
			target_alt = _random_alt()
			_set_state("strafe", randf_range(1.0, 2.8))
		"hold":
			_set_state("hold", randf_range(0.4, 1.0))
			_play_once("look", "idle")
		"attack":
			_begin_attack()


func _begin_attack() -> void:
	if not _has_los():
		target = _flank_point(pref_range)
		_set_state("reposition", 1.4)
		fire_t = 0.5
		return
	var pats: Dictionary = cfg.patterns
	var total := 0.0
	for k in pats: total += float(pats[k])
	var roll := randf() * total
	pattern = pats.keys()[0]
	for k in pats:
		roll -= float(pats[k])
		if roll <= 0.0:
			pattern = k
			break
	match pattern:
		"dive":
			_set_state("arm", 0.75)
			_play("charge", 1.0, true)
			Sfx.play_at("charge", global_position, -4.0, 0.7)
		"snipe":
			_set_state("aim", randf_range(1.3, 2.1) * (1.25 - 0.03 * mini(game.wave, 10)))
			_laser_aim = _player_head() + Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
			_laser.visible = true
			_play("charge", 1.0, true)
			Sfx.play_at("charge", global_position, -2.0, 0.55)
		"summon":
			_set_state("charge", 0.9)
			_play("look", 1.0, true)
		_:
			var c := randf_range(0.4, 0.75) * (1.0 - 0.02 * mini(game.wave, 12))
			if pattern == "feint": c = randf_range(0.3, 0.5)
			_set_state("charge", c)
			_play("charge", 1.0, true)
			Sfx.play_at("charge", global_position, -9.0, randf_range(0.9, 1.3))


func _fire_shot(spread_deg := 0.0, lead := -1.0, speed_mul := 1.0) -> void:
	var from := weak_point_global()
	var aim := _player_head() - Vector3(0, 0.15, 0)
	var spd := float(cfg.shot_speed) * (1.0 + 0.025 * mini(game.wave, 15)) * speed_mul
	var l := lead if lead >= 0.0 else lead_bias * 0.6
	var tt := from.distance_to(aim) / spd
	aim += (game.player.head_velocity as Vector3) * tt * l
	var dir := (aim - from).normalized()
	var wobble := 0.025 + 0.02 * jitter
	dir = (dir + Vector3(randf_range(-wobble, wobble), randf_range(-wobble, wobble) * 0.6, randf_range(-wobble, wobble))).normalized()
	if spread_deg != 0.0: dir = dir.rotated(Vector3.UP, deg_to_rad(spread_deg))
	game.projectiles.fire(from + dir * 0.1, dir * spd, float(cfg.shot_r), float(cfg.dmg), cfg.shot_color, bool(cfg.get("shootable_shots", false)))
	Sfx.play_at("enemy_spit" if type == "stinger" else ("enemy_shot2" if randf() < 0.5 else "enemy_shot"), from, -3.0)
	velocity -= dir * (1.2 if type != "boss" else 0.2)


func _execute_pattern() -> void:
	_play_once("fire", "idle")
	var fc: Vector2 = cfg.fire_cd
	fire_t = randf_range(fc.x, fc.y) * (1.25 - 0.4 * aggression) * maxf(0.55, 1.0 - 0.035 * game.wave)
	match pattern:
		"single":
			_fire_shot(0.0, 0.0)
		"lead":
			_fire_shot(0.0, randf_range(0.6, 1.0))
		"burst":
			shots_left = randi_range(2, 4)
			shot_t = randf_range(0.12, 0.22)
			_fire_shot()
			_set_state("burst", 2.0)
			return
		"heavy_burst":
			shots_left = randi_range(2, 4) + (2 if type == "boss" else 0)
			shot_t = 0.3
			_fire_shot()
			_set_state("burst", 3.0)
			return
		"spread":
			var n := 3 if randf() < 0.6 else 5
			var step := randf_range(9.0, 16.0)
			for i in n: _fire_shot((i - (n - 1) / 2.0) * step, 0.2)
		"ring":
			var n2 := randi_range(10, 16)
			for i in n2: _fire_shot((i - (n2 - 1) / 2.0) * (100.0 / n2), 0.0, randf_range(0.85, 1.15))
		"summon":
			for i in randi_range(2, 3):
				var off := Vector3(randf_range(-2.5, 2.5), randf_range(0.5, 1.5), randf_range(-2.5, 2.5))
				game.spawn_drone("bomber" if randf() < 0.6 else "scout", global_position + off, "")
			FX.ring(global_position, GameData.C_HAZARD, 4.0, 0.7)
		"feint":
			_start_dodge(_flat_dir_to_player())
			return
	_after_attack()


func _after_attack() -> void:
	if randf() < 0.55 + 0.3 * jitter:
		target = _flank_point(pref_range * randf_range(0.8, 1.2))
		target_alt = _random_alt()
		_set_state("reposition", randf_range(1.0, 2.2))
	else:
		_set_state("strafe", randf_range(0.8, 1.8))


# ---------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	t += delta
	if not alive:
		_update_dying(delta)
		return
	if _flash > 0.0:
		_flash -= delta
		var f := maxf(0.0, _flash) / 0.12
		_overlay.albedo_color = Color(_tint.lerp(Color.WHITE, f), maxf(0.28 if elite != "" else 0.0, f * 0.85))
		if _flash <= 0.0:
			_overlay.albedo_color = Color(_tint, 0.28)
			if elite == "": _set_overlay(false)
	elif elite == "volatile":
		_overlay.albedo_color.a = 0.2 + 0.18 * sin(t * 8.0)

	if spawn_t > 0.0:
		spawn_t -= delta
		var k := clampf(1.0 - spawn_t / ENTER_TIME, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		_pivot.scale = Vector3.ONE * (0.2 + 0.8 * e)
		_pivot.rotation.y = (1.0 - e) * 5.0
		velocity = velocity.lerp(Vector3.ZERO, delta * 4.0)
		move_and_slide()
		if spawn_t <= 0.0:
			_pivot.scale = Vector3.ONE
			_pick_next()
		return

	var playing: bool = game.state == "playing"
	if not playing:
		_wander(delta)
		return
	fire_t -= delta
	dodge_cd -= delta
	state_t -= delta

	var ph := _player_head()
	var to_p := ph - global_position
	var dist := to_p.length()
	var flat := Vector3(to_p.x, 0, to_p.z)
	var fdist := maxf(0.01, flat.length())
	var fdir := flat / fdist
	var desired := Vector3.ZERO
	var accel := 3.0

	# reacting to the player's aim
	if dodge_cd <= 0.0 and state in ["strafe", "reposition", "hold", "charge"] and dodge_skill > 0.0:
		var threat := _aimed_at()
		if threat != Vector3.ZERO and randf() < dodge_skill * delta * 2.2:
			_start_dodge(threat)

	match state:
		"reposition", "retreat":
			var to_t := target - global_position
			to_t.y = 0
			if to_t.length() < 1.0 or state_t <= 0.0:
				_pick_next()
			else:
				desired = to_t.normalized() * speed * (1.3 if state == "retreat" else 1.0)
		"strafe":
			var tangent := Vector3(-fdir.z, 0, fdir.x) * orbit_dir
			var radial := fdir * clampf((fdist - pref_range) * 0.5, -1.0, 1.0)
			desired = (tangent * 0.9 + radial).normalized() * speed * 0.8
			if randf() < 0.25 * jitter * delta: orbit_dir = -orbit_dir
			if state_t <= 0.0: _pick_next()
		"hold":
			desired = fdir * clampf((fdist - pref_range) * 0.3, -1.0, 1.0) * speed * 0.3
			if state_t <= 0.0: _pick_next()
		"dodge":
			accel = 1.2
			desired = velocity
			if state_t <= 0.0: _pick_next()
		"charge":
			desired = Vector3.ZERO
			accel = 4.0
			var ck := 1.0 - clampf(state_t / 0.7, 0.0, 1.0)
			_glow.visible = true
			_glow.scale = Vector3.ONE * maxf(0.001, (float(cfg.shot_r) * 2.5 + 0.12) * ck * (2.5 if type == "boss" else 1.0))
			if state_t <= 0.0:
				_glow.visible = false
				_execute_pattern()
		"burst":
			desired = Vector3(-fdir.z, 0, fdir.x) * orbit_dir * speed * 0.3
			shot_t -= delta
			if shot_t <= 0.0 and shots_left > 0:
				shots_left -= 1
				_fire_shot(randf_range(-4.0, 4.0))
				shot_t = 0.3 if pattern == "heavy_burst" else randf_range(0.12, 0.22)
			if shots_left <= 0 and shot_t <= 0.0: _after_attack()
		"arm":
			desired = Vector3.ZERO
			accel = 5.0
			if state_t <= 0.0: _begin_dive()
		"dive":
			_update_dive(delta)
			return
		"aim":
			_update_aim(delta)
			desired = Vector3.ZERO
			accel = 3.0
		_:
			_pick_next()

	# organic drift so even straight moves wobble
	var n := Vector3(_noise.get_noise_2d(t * 1.3, 0.0), _noise.get_noise_2d(0.0, t * 1.1), _noise.get_noise_2d(t * 1.2, 50.0))
	desired += n * speed * 0.55 * jitter
	# altitude
	var alt_goal := target_alt + sin(t * 1.7 + float(get_instance_id() % 97)) * 0.15
	desired.y += clampf((alt_goal - global_position.y) * 1.6, -3.0, 3.0)
	# don't crowd other drones
	for o in game.drones:
		if o == self or not is_instance_valid(o) or not o.alive: continue
		var sep: Vector3 = global_position - (o as Node3D).global_position
		var dl := sep.length()
		var mind := _half.length() + (o as Drone)._half.length() + 0.6
		if dl < mind and dl > 0.001: desired += sep / dl * (mind - dl) * 3.0
	# keep out of the player's face
	if dist < 2.2 and type != "bomber": desired -= to_p.normalized() * speed

	velocity = velocity.lerp(desired, clampf(delta * accel, 0.0, 1.0))
	_move(delta)
	_face(ph, delta, fdir)


func _move(delta: float) -> void:
	var before := global_position
	move_and_slide()
	var p := global_position
	var L := GameData.ARENA - 0.8
	p.x = clampf(p.x, -L, L)
	p.z = clampf(p.z, -L, L)
	p.y = clampf(p.y, 0.6, 14.0)
	global_position = p
	if velocity.length() > 1.0 and before.distance_to(p) < velocity.length() * delta * 0.25:
		stuck_t += delta
		if stuck_t > 0.6:
			stuck_t = 0.0
			target = _flank_point(pref_range)
			target_alt = _random_alt() + 1.5
			_set_state("reposition", 1.5)
	else:
		stuck_t = 0.0


func _face(ph: Vector3, delta: float, fdir: Vector3) -> void:
	var want_yaw := atan2(-fdir.x, -fdir.z)
	rotation.y = lerp_angle(rotation.y, want_yaw, clampf(delta * 5.0, 0.0, 1.0))
	var local_v := global_transform.basis.inverse() * velocity
	var pitch_goal := clampf(local_v.z * 0.06, -0.45, 0.45)
	var aim_pitch := 0.0
	if type in ["scout", "sniper"]:
		var dv := ph - global_position
		aim_pitch = atan2(dv.y, Vector2(dv.x, dv.z).length()) * 0.8
	_pivot.rotation.x = lerp_angle(_pivot.rotation.x, pitch_goal + aim_pitch, clampf(delta * 6.0, 0.0, 1.0))
	_pivot.rotation.z = lerp_angle(_pivot.rotation.z, clampf(-local_v.x * 0.08, -0.6, 0.6), clampf(delta * 6.0, 0.0, 1.0))
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, 0.0, clampf(delta * 8.0, 0.0, 1.0))


func _begin_dive() -> void:
	_set_state("dive", 3.2)
	dive_from = global_position
	var ph := _player_head()
	var side := (ph - dive_from).cross(Vector3.UP).normalized()
	dive_ctrl = (dive_from + ph) * 0.5 + side * randf_range(-5.0, 5.0) + Vector3(0, randf_range(1.0, 4.0), 0)
	dive_k = 0.0
	dive_abort = randf() < 0.22 - 0.01 * mini(game.wave, 10)
	_play("dash", 1.3, true)
	Sfx.play_at("dash", global_position, 0.0, 0.9)
	if _hum: _hum.pitch_scale = 1.6


func _update_dive(delta: float) -> void:
	var ph := _player_head() + (game.player.head_velocity as Vector3) * 0.25
	var length := dive_from.distance_to(dive_ctrl) + dive_ctrl.distance_to(ph)
	var spd := speed * 2.0 + 2.0
	dive_k = minf(1.0, dive_k + delta * spd / maxf(1.0, length))
	var a := dive_from.lerp(dive_ctrl, dive_k)
	var b := dive_ctrl.lerp(ph, dive_k)
	var goal := a.lerp(b, dive_k)
	var v := (goal - global_position) / maxf(delta, 0.001)
	velocity = v.limit_length(spd * 1.6)
	_move(delta)
	look_at(global_position + Vector3(velocity.x, 0, velocity.z) + Vector3(0.0001, 0, 0), Vector3.UP)
	_pivot.rotation.x = lerp_angle(_pivot.rotation.x, -0.5, delta * 6.0)
	if dive_abort and dive_k > 0.55:
		dive_abort = false
		if _hum: _hum.pitch_scale = 1.0
		target = _point_away(pref_range + 3.0)
		target_alt = _random_alt() + 1.0
		_set_state("reposition", 1.6)
		_play("idle")
		fire_t = randf_range(0.8, 1.6)
		return
	if global_position.distance_to(_player_head()) < 0.95 + _half.length() * 0.5:
		alive = false
		collision_layer = 0
		if _hum: _hum.stop()
		died.emit(self, false)
		_explode()
		return
	if dive_k >= 1.0 or state_t <= 0.0:
		if _hum: _hum.pitch_scale = 1.0
		_play("idle")
		var fc: Vector2 = cfg.fire_cd
		fire_t = randf_range(fc.x, fc.y)
		target = _flank_point(pref_range)
		target_alt = _random_alt()
		_set_state("reposition", 1.8)


func _update_aim(delta: float) -> void:
	var ph := _player_head() - Vector3(0, 0.1, 0)
	# the beam trails the player, so moving off the line is how you dodge it
	_laser_aim = _laser_aim.lerp(ph, clampf(delta * (2.2 + 0.1 * game.wave), 0.0, 1.0))
	var from := weak_point_global()
	var dir := (_laser_aim - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, GameData.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = from + dir * 60.0
	if not hit.is_empty(): end = hit.position
	var len := from.distance_to(end)
	var w := 0.006 + 0.02 * (1.0 - clampf(state_t / 1.5, 0.0, 1.0))
	_laser.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT), from + dir * len * 0.5)
	_laser.scale = Vector3(w, w, len)
	_laser_mat.albedo_color.a = 0.35 + 0.4 * (1.0 - clampf(state_t / 1.5, 0.0, 1.0)) + (0.25 if fmod(t, 0.12) < 0.06 and state_t < 0.4 else 0.0)
	if state_t <= 0.0:
		_laser.visible = false
		var spd := float(cfg.shot_speed)
		game.projectiles.fire(from + dir * 0.2, dir * spd, float(cfg.shot_r), float(cfg.dmg), cfg.shot_color, false, "bolt")
		Sfx.play_at("enemy_snipe", from, 2.0)
		FX.flash(from, cfg.shot_color, 2.0, 0.12)
		_play_once("fire", "idle")
		velocity -= dir * 4.0
		var fc: Vector2 = cfg.fire_cd
		fire_t = randf_range(fc.x, fc.y) * maxf(0.6, 1.0 - 0.03 * game.wave)
		# relocate right away so the player has to find it again
		target = _flank_point(pref_range * randf_range(0.9, 1.1))
		target_alt = _random_alt()
		_set_state("reposition", randf_range(1.5, 2.5))


func _wander(delta: float) -> void:
	# menu / armory idle: lazy loops around the yard
	var a := t * 0.12 + float(get_instance_id() % 13)
	var goal := Vector3(cos(a) * 11.0, target_alt if target_alt > 0.5 else 2.5, sin(a) * 11.0)
	var desired := (goal - global_position).limit_length(1.0) * speed * 0.35
	velocity = velocity.lerp(desired, clampf(delta * 2.0, 0.0, 1.0))
	_move(delta)
	var fd := Vector3(velocity.x, 0, velocity.z)
	if fd.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-fd.x, -fd.z), clampf(delta * 2.0, 0.0, 1.0))


func _update_dying(delta: float) -> void:
	if _dying <= 0.0:
		_explode()
		return
	_dying -= delta
	velocity.y -= 9.8 * delta
	velocity.x *= 0.98
	velocity.z *= 0.98
	global_position += velocity * delta
	_pivot.rotation += _death_spin * delta
	if global_position.y < _half.y * 0.6 or _dying <= 0.0:
		_dying = 0.0
