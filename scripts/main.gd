extends Node3D
## Game controller: starts OpenXR (or desktop fallback), builds the selected map, runs the
## menu -> wave -> armory -> wave loop, and owns score, credits and the shootable UI.

const PlayerScript := preload("res://scripts/player.gd")
const MapBuilder := preload("res://scripts/map_builder.gd")
const ProjectilesScript := preload("res://scripts/projectiles.gd")

var xr_interface: OpenXRInterface
var vr := false
var state := "menu"     # menu | playing | armory | over
var paused := false
var wave := 0
var score := 0
var kills := 0
var wave_active := false
var to_spawn: Array = []
var spawn_t := 0.0
var intermission := 0.0
var armory_t := 0.0

var world: Node3D
var map: Node3D
var player: XROrigin3D
var projectiles: Node3D
var drones: Array = []
var pickups_root: Node3D
var ui: Node3D
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var boss_label: Label3D
var _boss: Drone
var _armory_buttons := {}
var _armory_info: Label3D
var _armory_center := Transform3D.IDENTITY
var _focus_paused := false


func _ready() -> void:
	vr = _init_xr()
	world_env = WorldEnvironment.new()
	world_env.environment = Environment.new()
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 32.0
	sun.shadow_blur = 1.0
	add_child(sun)

	world = Node3D.new()
	world.name = "World"
	add_child(world)
	map = MapBuilder.new()
	map.name = "Map"
	world.add_child(map)
	projectiles = ProjectilesScript.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	pickups_root = Node3D.new()
	pickups_root.name = "Pickups"
	world.add_child(pickups_root)

	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.setup(self, vr)
	projectiles.player = player

	ui = Node3D.new()
	ui.name = "UI"
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)

	boss_label = Label3D.new()
	boss_label.font = GameData.FONT_HEAD
	boss_label.font_size = 72
	boss_label.pixel_size = 0.006
	boss_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	boss_label.modulate = GameData.C_ALARM
	boss_label.outline_size = 14
	boss_label.no_depth_test = true
	boss_label.visible = false
	world.add_child(boss_label)

	GameData.reset_run()
	_load_map(GameData.map_id)
	player.reset_for_run()
	go_menu()
	# dev hook: `-- --tool=autotest` runs res://tools/autotest.gd (tools/ is not exported)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tool=") and ResourceLoader.exists("res://tools/%s.gd" % arg.substr(7)):
			add_child((load("res://tools/%s.gd" % arg.substr(7)) as GDScript).new())


# ---------------------------------------------------------------- XR
func _init_xr() -> bool:
	if "--fake-vr" in OS.get_cmdline_user_args(): return true  # dev: exercise the VR code path without a headset
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr_interface.session_begun.connect(_on_session_begun)
		xr_interface.session_visible.connect(_on_session_visible)
		xr_interface.session_focussed.connect(_on_session_focussed)
		xr_interface.session_stopping.connect(_on_session_stopping)
		xr_interface.pose_recentered.connect(func(): XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true))
		return true
	return false


func _on_session_begun() -> void:
	if not xr_interface: return
	var rates: Array = xr_interface.get_available_display_refresh_rates()
	var want := 0.0
	for r in rates:
		if float(r) <= 90.5 and float(r) > want: want = float(r)
	if want > 0.0: xr_interface.display_refresh_rate = want
	var rr := xr_interface.get_display_refresh_rate()
	if rr <= 0.0: rr = 72.0
	Engine.physics_ticks_per_second = int(round(rr))


func _on_session_visible() -> void:
	# headset taken off / system menu open: hold the game
	if state == "playing" and not paused:
		_focus_paused = true
		set_paused(true)


func _on_session_focussed() -> void:
	if _focus_paused:
		_focus_paused = false


func _on_session_stopping() -> void:
	GameData.save()


# ---------------------------------------------------------------- helpers
func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func alive_hostiles() -> int:
	var n := 0
	for d in drones:
		if is_instance_valid(d) and (d as Drone).alive: n += 1
	return n


func left_text() -> String:
	if state != "playing": return ""
	if not wave_active: return "NEXT WAVE"
	return "%d LEFT" % (alive_hostiles() + to_spawn.size())


func _clear_ui() -> void:
	for c in ui.get_children(): c.queue_free()
	_armory_buttons.clear()
	_armory_info = null


func _label(text: String, pos: Vector3, size: int, color: Color, font: Font = GameData.FONT_HEAD, px := 0.004, parent: Node3D = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = maxi(4, size / 8)
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.position = pos
	(parent if parent else ui).add_child(l)
	return l


func _button(size: Vector2, pos: Vector3, title: String, sub := "", accent := GameData.C_HAZARD, parent: Node3D = null) -> Button3D:
	var b := Button3D.new()
	(parent if parent else ui).add_child(b)
	b.setup(size, title, sub, accent)
	b.position = pos
	return b


## A UI anchor in front of the player's current gaze, on the floor plane.
func _anchor_in_front(dist: float) -> Node3D:
	var h: Vector3 = player.head_position()
	var f: Vector3 = -player.camera.global_transform.basis.z
	f.y = 0
	f = f.normalized() if f.length() > 0.05 else Vector3.FORWARD
	var a := Node3D.new()
	ui.add_child(a)
	var pos := Vector3(h.x, 0, h.z) + f * dist
	a.global_transform = Transform3D(Basis.looking_at(f, Vector3.UP), pos)
	return a


func _load_map(id: String) -> void:
	GameData.map_id = id
	map.build(id, world_env, sun)


# ---------------------------------------------------------------- menu
func go_menu() -> void:
	set_paused(false)
	state = "menu"
	wave = 0
	wave_active = false
	to_spawn.clear()
	_clear_world()
	_clear_ui()
	GameData.reset_run()
	player.reset_for_run()
	player.input_enabled = true
	_reset_player_position()
	_spawn_ambient()
	_build_menu()


func _reset_player_position() -> void:
	player.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0, 3.2))
	if vr: XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)


func _build_menu() -> void:
	_clear_ui()
	var a := Node3D.new()
	ui.add_child(a)
	a.position = Vector3(0, 0, 0.2)
	var t := _label("DRONE YARD", Vector3(0, 2.9, 0), 200, GameData.C_HAZARD, GameData.FONT_STENCIL, 0.0038, a)
	t.outline_size = 30
	_label("VR · WAVE DEFENCE · SHOOT A PANEL TO CHOOSE", Vector3(0, 2.5, 0), 44, GameData.C_PAPER, GameData.FONT_MONO, 0.004, a)
	var x := -1.18
	for id in GameData.MAP_ORDER:
		var m: Dictionary = GameData.MAPS[id]
		var b := GameData.best_for(id)
		var best := "BEST  W%d · %s" % [b.wave, fmt(int(b.score))] if int(b.score) > 0 else "NO RUNS YET"
		var btn := _button(Vector2(1.1, 0.66), Vector3(x, 1.88, 0), m.name.to_upper(), m.desc, GameData.C_HAZARD, a)
		btn.set_text(m.name.to_upper(), m.desc, best)
		btn.set_selected(id == GameData.map_id)
		btn.pressed.connect(_on_map_pressed.bind(id))
		x += 1.18
	var deploy := _button(Vector2(1.7, 0.44), Vector3(0, 1.2, 0), "DEPLOY", "Start wave 1 on " + GameData.MAPS[GameData.map_id].name, GameData.C_SIGNAL, a)
	deploy.pressed.connect(start_game)

	var ctl := "CONTROLS\n\nTRIGGER   fire (hold for auto)\nL STICK   move\nR STICK   snap turn\nA / X     reload  (or aim at floor)\nB / Y     swap weapon\nGRIP      overclock (once bought)\nMENU      pause\nBODY      duck behind cover"
	if not vr:
		ctl = "CONTROLS (desktop)\n\nCLICK     fire / capture mouse\nWASD      move · SHIFT sprint\nC         crouch\nR         reload\nQ         swap weapon\nE         overclock\nP / ESC   pause"
	var cl := _label(ctl, Vector3(-3.0, 1.7, 1.6), 40, GameData.C_PAPER, GameData.FONT_MONO, 0.0028, a)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cl.rotation.y = deg_to_rad(52)
	var th := "THREATS\n\nSEEKER     fast, flips out of your aim\nROTOR BOMB dives in and explodes\nSTINGER    zig-zags, spits fans of acid\nSENTINEL   sniper: dodge off the laser\nCARRIER    slow tank, shoot its orbs\nWARDEN     boss every 5th wave\n\nElites glow: swift, shielded, volatile.\nShoot the glowing core for crits."
	var tl := _label(th, Vector3(3.0, 1.7, 1.6), 40, GameData.C_PAPER, GameData.FONT_MONO, 0.0028, a)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tl.rotation.y = deg_to_rad(-52)


func _on_map_pressed(id: String) -> void:
	if id == GameData.map_id: return
	_clear_world()
	_load_map(id)
	GameData.save()
	_reset_player_position()
	_spawn_ambient()
	_build_menu()


func _spawn_ambient() -> void:
	var i := 0
	for t in ["scout", "bomber", "stinger", "sniper"]:
		var a := float(i) / 4.0 * TAU
		var d := spawn_drone(t, Vector3(cos(a) * 10.0, 3.0 + i * 0.6, sin(a) * 10.0 - 4.0), "")
		d.spawn_t = 0.01
		d.target_alt = 2.6 + i * 0.7
		i += 1


func _clear_world() -> void:
	for d in drones:
		if is_instance_valid(d): (d as Node).queue_free()
	drones.clear()
	_boss = null
	boss_label.visible = false
	projectiles.clear()
	for p in pickups_root.get_children(): p.queue_free()
	FX.clear()


# ---------------------------------------------------------------- run
func start_game() -> void:
	set_paused(false)
	_clear_world()
	GameData.reset_run()
	score = 0
	kills = 0
	wave = 0
	wave_active = false
	to_spawn.clear()
	intermission = 3.0
	player.reset_for_run()
	player.input_enabled = true
	_clear_ui()
	state = "playing"
	player.banner("GET READY", GameData.MAPS[GameData.map_id].name.to_upper(), 2.6)
	Sfx.play("wave_start", -2.0)


func wave_list(n: int) -> Array:
	var count := mini(3 + n * 2, 34)
	var pool := {"scout": 4.0}
	if n >= 2: pool["bomber"] = 2.6
	if n >= 3: pool["stinger"] = 2.6
	if n >= 4: pool["sniper"] = 1.4 + 0.1 * n
	var heavy_cap := 0
	if n >= 6: heavy_cap = mini(int((n - 4) / 2), 5)
	var out: Array = []
	if n % 5 == 0:
		out.append("boss")
		count = int(count * 0.6)
	for i in heavy_cap: out.append("heavy")
	var total := 0.0
	for k in pool: total += pool[k]
	while out.size() < count:
		var r := randf() * total
		for k in pool:
			r -= pool[k]
			if r <= 0.0:
				out.append(k)
				break
	out.shuffle()
	# open each wave with something light
	if out[0] in ["heavy", "boss"]:
		for i in out.size():
			if out[i] == "scout":
				var tmp = out[0]
				out[0] = out[i]
				out[i] = tmp
				break
	return out


func start_wave(n: int) -> void:
	_clear_ui()
	state = "playing"
	wave = n
	wave_active = true
	to_spawn = wave_list(n)
	spawn_t = 0.8
	player.barrier = GameData.lvl("barrier")
	player.input_enabled = true
	var sub := "%d drones inbound" % to_spawn.size()
	if "boss" in to_spawn: sub = "WARDEN INBOUND + %d drones" % (to_spawn.size() - 1)
	player.banner("WAVE %d" % n, sub, 2.6)
	Sfx.play("wave_start", 0.0)


func spawn_drone(type: String, pos: Vector3, elite: String) -> Drone:
	var d := Drone.new()
	world.add_child(d)
	d.setup(type, self, elite)
	d.global_position = pos
	d.target_alt = pos.y
	d.died.connect(_on_drone_died)
	drones.append(d)
	if type == "boss": _boss = d
	return d


func _spawn_from_queue() -> void:
	var type: String = to_spawn.pop_front()
	var h: Vector3 = player.head_position()
	var fwd: Vector3 = -player.camera.global_transform.basis.z
	var pos := Vector3.ZERO
	for attempt in 12:
		var a := randf() * TAU
		# sometimes come from behind
		if randf() < 0.65:
			var base := atan2(fwd.x, fwd.z)
			a = base + randf_range(-1.2, 1.2)
		var r := randf_range(12.0, 18.0)
		pos = Vector3(h.x + sin(a) * r, randf_range(2.5, 6.0), h.z + cos(a) * r)
		var L := GameData.ARENA - 2.0
		pos.x = clampf(pos.x, -L, L)
		pos.z = clampf(pos.z, -L, L)
		var blocked := false
		for ob in map.obstacles:
			if (ob as AABB).grow(1.0).has_point(pos):
				blocked = true
				break
		if not blocked: break
	if type == "boss": pos.y = 4.0
	var elite := ""
	var chance := clampf((wave - 3) * 0.05, 0.0, 0.35)
	if type != "boss" and randf() < chance: elite = ["swift", "shielded", "volatile"][randi() % 3]
	spawn_drone(type, pos, elite)
	FX.ring(pos, GameData.C_HAZARD, 3.0 if type != "boss" else 7.0, 0.9)
	FX.sparks(pos, Vector3.UP, GameData.C_HAZARD, 20)
	Sfx.play_at("spawn", pos, 0.0)
	if type == "boss": player.banner("WARDEN", "Shoot the glowing core", 2.5)


func _on_drone_died(d: Drone, by_player: bool) -> void:
	drones.erase(d)
	if d == _boss:
		_boss = null
		boss_label.visible = false
	if state == "menu":
		return
	if not by_player: return
	var cfg: Dictionary = d.cfg
	kills += 1
	var mult := 1.0 + 0.1 * (wave - 1)
	if d.elite != "": mult *= 1.5
	score += int(round(float(cfg.score) * mult))
	GameData.credits += int(round(float(cfg.credits) * (1.4 if d.elite != "" else 1.0)))
	var pos := d.global_position
	var r := randf()
	if d.type in ["heavy", "boss"] or (r < 0.14 and player.hp < GameData.max_hp()):
		_spawn_pickup("health", pos)
	elif r < 0.32:
		_spawn_pickup("credits", pos)
	elif r < 0.38 and GameData.lvl("overclock") > 0:
		_spawn_pickup("overclock", pos)
	if d.type == "boss":
		for i in 4: _spawn_pickup("credits", pos + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))


func _spawn_pickup(kind: String, pos: Vector3) -> void:
	var p := Pickup.new()
	pickups_root.add_child(p)
	p.setup(kind, self, pos)


func on_pickup(kind: String) -> void:
	match kind:
		"health":
			player.heal(30.0)
		"credits":
			var c := 25 + 5 * wave
			GameData.credits += c
			FX.number(player.head_position() + (-player.camera.global_transform.basis.z) * 1.2, c, false)
		"overclock":
			player.overclock_cd = 0.0


func _update_waves(delta: float) -> void:
	if not wave_active:
		intermission -= delta
		if intermission <= 0.0: start_wave(wave + 1)
		return
	var max_alive := mini(3 + wave / 2, 10)
	if to_spawn.size() > 0 and alive_hostiles() < max_alive:
		spawn_t -= delta
		if spawn_t <= 0.0:
			_spawn_from_queue()
			spawn_t = maxf(0.45, randf_range(0.7, 1.6) - wave * 0.04)
	if to_spawn.is_empty() and alive_hostiles() == 0:
		wave_active = false
		var bonus := wave * 200
		var cbonus := 60 + wave * 25
		score += bonus
		GameData.credits += cbonus
		player.heal(25.0)
		player.end_overclock()
		player.banner("WAVE %d CLEAR" % wave, "+%s pts · +%d credits" % [fmt(bonus), cbonus], 2.0)
		Sfx.play("wave_clear", 0.0)
		_open_armory()


func on_player_dead() -> void:
	if state != "playing": return
	state = "over"
	wave_active = false
	Sfx.play("game_over", 0.0)
	var is_best := GameData.record_run(score, wave)
	player.banner("YARD LOST", "Wave %d · %s pts" % [wave, fmt(score)], 1.5)
	await get_tree().create_timer(1.6, true, false, true).timeout
	if state == "over": _build_game_over(is_best)


func _build_game_over(is_best: bool) -> void:
	_clear_ui()
	player.clear_banner()
	var a := _anchor_in_front(2.6)
	_label("YARD LOST", Vector3(0, 2.6, 0), 200, GameData.C_ALARM, GameData.FONT_STENCIL, 0.004, a)
	var shots := 0
	var hits := 0
	for g in player.guns:
		shots += (g as Gun).shots
		hits += (g as Gun).hits
	var acc := int(round(100.0 * hits / maxi(1, shots)))
	var b := GameData.best_for(GameData.map_id)
	var stats := "WAVE %d    SCORE %s    DRONES %d    ACCURACY %d%%\n%s" % [wave, fmt(score), kills, acc,
			"NEW BEST RUN" if is_best else "BEST  W%d · %s" % [b.wave, fmt(int(b.score))]]
	_label(stats, Vector3(0, 2.1, 0), 48, GameData.C_PAPER, GameData.FONT_MONO, 0.004, a)
	var again := _button(Vector2(1.2, 0.42), Vector3(-0.68, 1.4, 0), "REDEPLOY", "Same map, fresh run", GameData.C_SIGNAL, a)
	again.pressed.connect(start_game)
	var menu := _button(Vector2(1.2, 0.42), Vector3(0.68, 1.4, 0), "MAIN MENU", "Pick another map", GameData.C_HAZARD, a)
	menu.pressed.connect(go_menu)
	player.refill()


# ---------------------------------------------------------------- armory
func _open_armory() -> void:
	state = "armory"
	armory_t = 35.0
	player.refill()
	await get_tree().create_timer(2.1, false).timeout
	if state != "armory": return
	_clear_ui()
	player.clear_banner()
	var a := _anchor_in_front(2.4)
	_armory_center = a.global_transform
	# a real terminal model under the holo cards
	var term: Node3D = (load("res://assets/station/computer-wide.glb") as PackedScene).instantiate()
	term.scale = Vector3.ONE * 2.0
	term.position = Vector3(0, 0, 0.35)
	term.rotation.y = PI
	a.add_child(term)
	_label("ARMORY", Vector3(0, 2.72, 0), 150, GameData.C_HAZARD, GameData.FONT_STENCIL, 0.004, a)
	_armory_info = _label("", Vector3(0, 2.36, 0), 46, GameData.C_PAPER, GameData.FONT_MONO, 0.004, a)

	var offers: Array = []
	var ups: Array = []
	for k in GameData.UPGRADES:
		if GameData.can_upgrade(k): ups.append(k)
	ups.shuffle()
	for i in mini(4, ups.size()): offers.append(["up", ups[i]])
	var unowned: Array = []
	for w in GameData.WEAPON_ORDER:
		if not (w in GameData.owned): unowned.append(w)
	if unowned.size() > 0: offers.append(["gun", unowned[0] if randf() < 0.6 else unowned[randi() % unowned.size()]])
	var n := offers.size()
	var w_card := 0.74
	var x0 := -(n - 1) * (w_card + 0.06) / 2.0
	for i in n:
		var o: Array = offers[i]
		var b := _button(Vector2(w_card, 0.56), Vector3(x0 + i * (w_card + 0.06), 1.82, 0), "", "", GameData.C_SCOUT if o[0] == "gun" else GameData.C_HAZARD, a)
		b.pressed.connect(_on_offer.bind(o[0], o[1]))
		_armory_buttons[o[0] + ":" + o[1]] = b
	var rep := _button(Vector2(0.9, 0.4), Vector3(-0.98, 1.2, 0), "", "", GameData.C_SIGNAL, a)
	rep.pressed.connect(_on_offer.bind("repair", ""))
	_armory_buttons["repair:"] = rep
	if GameData.owned.size() > 1:
		var sw := _button(Vector2(0.9, 0.4), Vector3(0.0, 1.2, 0), "", "", GameData.C_SCOUT, a)
		sw.pressed.connect(_on_offer.bind("swap", ""))
		_armory_buttons["swap:"] = sw
	var nxt := _button(Vector2(0.9, 0.4), Vector3(0.98, 1.2, 0), "NEXT WAVE", "", GameData.C_SIGNAL, a)
	nxt.pressed.connect(_armory_done)
	_armory_buttons["next:"] = nxt
	_refresh_armory()


func _repair_cost() -> int:
	return 40 + wave * 8


func _refresh_armory() -> void:
	if _armory_info:
		_armory_info.text = "CREDITS  %d      HEALTH  %d / %d" % [GameData.credits, int(ceil(player.hp)), int(GameData.max_hp())]
	for key in _armory_buttons:
		var b: Button3D = _armory_buttons[key]
		if not is_instance_valid(b): continue
		var parts: PackedStringArray = (key as String).split(":")
		match parts[0]:
			"up":
				var u: Dictionary = GameData.UPGRADES[parts[1]]
				var lv := GameData.lvl(parts[1])
				if GameData.can_upgrade(parts[1]):
					var c := GameData.upgrade_cost(parts[1])
					b.set_text(u.name.to_upper(), u.desc, "LV %d>%d · %d CR" % [lv, lv + 1, c])
					b.set_enabled(GameData.credits >= c)
				else:
					b.set_text(u.name.to_upper(), u.desc, "MAXED")
					b.set_enabled(false)
			"gun":
				var w: Dictionary = GameData.WEAPONS[parts[1]]
				if parts[1] in GameData.owned:
					b.set_text(w.name.to_upper(), w.desc, "OWNED")
					b.set_enabled(false)
				else:
					b.set_text(w.name.to_upper(), w.desc, "WEAPON · %d CR" % int(w.cost))
					b.set_enabled(GameData.credits >= int(w.cost))
			"repair":
				var full: bool = player.hp >= GameData.max_hp() - 0.5
				b.set_text("REPAIR +40", "", "FULL" if full else "%d CR" % _repair_cost())
				b.set_enabled(not full and GameData.credits >= _repair_cost())
			"swap":
				b.set_text("SWAP GUN", "", GameData.WEAPONS[GameData.weapon].name.to_upper())
			"next":
				b.set_text("NEXT WAVE", "", "AUTO IN %ds" % int(ceil(armory_t)))


func _on_offer(kind: String, id: String) -> void:
	var ok := false
	match kind:
		"up":
			ok = GameData.buy_upgrade(id)
			if ok:
				player.refresh_weapon_stats()
				if id == "armor": player.heal(25.0)
				if id == "barrier": player.barrier = GameData.lvl("barrier")
		"gun":
			ok = GameData.buy_weapon(id)
			if ok:
				player.equip(id)
				if not _armory_buttons.has("swap:"): pass
		"repair":
			if GameData.credits >= _repair_cost() and player.hp < GameData.max_hp():
				GameData.credits -= _repair_cost()
				player.heal(40.0)
				ok = true
		"swap":
			player.cycle_weapon()
			ok = true
	if ok and kind != "swap": Sfx.play("pickup", -2.0, 1.2)
	_refresh_armory()


func _armory_done() -> void:
	if state != "armory": return
	start_wave(wave + 1)


# ---------------------------------------------------------------- pause
func toggle_pause() -> void:
	if state != "playing" and not paused: return
	set_paused(not paused)


func set_paused(v: bool) -> void:
	if paused == v: return
	paused = v
	get_tree().paused = v
	if v:
		player.end_overclock()
		_clear_ui()
		var a := _anchor_in_front(2.2)
		_label("HOLD FIRE", Vector3(0, 2.4, 0), 180, GameData.C_HAZARD, GameData.FONT_STENCIL, 0.004, a)
		var r := _button(Vector2(1.1, 0.42), Vector3(-0.62, 1.55, 0), "RESUME", "", GameData.C_SIGNAL, a)
		r.pressed.connect(func(): set_paused(false))
		var q := _button(Vector2(1.1, 0.42), Vector3(0.62, 1.55, 0), "QUIT", "Back to menu", GameData.C_ALARM, a)
		q.pressed.connect(go_menu)
	else:
		if state == "playing": _clear_ui()


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	if paused: return
	match state:
		"playing":
			_update_waves(delta)
		"armory":
			armory_t -= delta
			if Engine.get_physics_frames() % 15 == 0: _refresh_armory()
			if armory_t <= 0.0: _armory_done()
	if _boss and is_instance_valid(_boss) and _boss.alive:
		boss_label.visible = true
		boss_label.global_position = _boss.global_position + Vector3(0, _boss._half.y + 1.0, 0)
		var cells := 20
		var on := int(ceil(_boss.hp / _boss.max_hp * cells))
		boss_label.text = "WARDEN  " + "|".repeat(on) + ".".repeat(cells - on)
	else:
		boss_label.visible = false
