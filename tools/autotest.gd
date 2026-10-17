extends Node
## Desktop smoke test: tours every map, plays waves with an aimbot, buys upgrades, dies.
## Run: godot --path . --xr-mode off -- --tool=autotest

var game: Node
var shots_dir := "res://build/shots/"
var frame := 0
var log_lines: PackedStringArray = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = get_parent()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shots_dir))
	_run()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots_dir + name + ".png")
	print("SHOT ", name)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout

func _aim_and_fire() -> void:
	var p = game.player
	var best = null
	var bd := INF
	for d in game.drones:
		if not is_instance_valid(d) or not d.alive or d.spawn_t > 0.0: continue
		var dist: float = p.head_position().distance_to(d.global_position)
		if dist < bd:
			bd = dist
			best = d
	if best == null: return
	var to: Vector3 = best.weak_point_global() - p.head_position()
	p._yaw = atan2(-to.x, -to.z)
	p._pitch = atan2(to.y, Vector2(to.x, to.z).length())
	p.rotation = Vector3(0, p._yaw, 0)
	p.camera.rotation = Vector3(p._pitch, 0, 0)
	p.guns[0].try_fire(false)

func _physics_process(_d: float) -> void:
	frame += 1
	if game.state == "playing" and game.player.alive and not game.get_meta("let_die", false):
		game.player.hp = GameData.max_hp()
		if frame % 4 == 0: _aim_and_fire()

func _run() -> void:
	await _wait(1.0)
	for m in GameData.MAP_ORDER:
		game._on_map_pressed(m)
		await _wait(1.2)
		await _shot("menu_" + m)
		# look around the arena
		game.player._yaw = PI
		game.player.rotation.y = PI
		await _wait(0.3)
		await _shot("arena_" + m + "_back")
		game.player._yaw = 0.0
		game.player.rotation.y = 0.0
	game._on_map_pressed("yard")
	await _wait(0.5)
	game.start_game()
	GameData.credits = 0
	var t := 0.0
	var shot_combat := false
	while game.wave < 6 and t < 300.0:
		await _wait(0.25)
		t += 0.25
		if game.state == "playing" and game.drones.size() >= 3 and not shot_combat and game.wave >= 2:
			shot_combat = true
			await _shot("combat_wave%d" % game.wave)
		if game.state == "armory":
			while game.state == "armory" and game._armory_buttons.is_empty(): await _wait(0.2)
			await _wait(0.4)
			print("ARMORY UI children=", game.ui.get_child_count(), " buttons=", game._armory_buttons.size(), " state=", game.state)
			GameData.credits += 2000
			var keys: Array = game._armory_buttons.keys()
			for k in keys:
				var parts: PackedStringArray = (k as String).split(":")
				if parts[0] in ["up", "gun"]: game._on_offer(parts[0], parts[1])
			game._refresh_armory()
			if game.wave == 1: await _shot("armory")
			print("ARMORY wave=", game.wave, " levels=", GameData.levels, " owned=", GameData.owned, " weapon=", GameData.weapon)
			game._armory_done()
		if game.wave == 5 and game._boss and is_instance_valid(game._boss) and not game.has_meta("boss_shot"):
			game.set_meta("boss_shot", true)
			await _wait(2.0)
			await _shot("boss")
	print("REACHED wave=", game.wave, " score=", game.score, " kills=", game.kills, " t=", t)
	# pause round trip
	game.set_paused(true)
	await _wait(0.5)
	await _shot("pause")
	game.set_paused(false)
	game.set_meta("let_die", true)
	game.player.barrier = 0
	game.player.hurt(99999.0, Vector3.FORWARD)
	await _wait(2.5)
	await _shot("game_over")
	print("STATE ", game.state)
	game.go_menu()
	await _wait(0.5)
	print("AUTOTEST DONE")
	get_tree().quit()
