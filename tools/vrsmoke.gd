extends Node
## Fake-VR smoke run: start a game, let drones attack for a while, open the armory, quit.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var g := get_parent()
	await get_tree().create_timer(1.0).timeout
	g.start_game()
	await get_tree().create_timer(14.0).timeout
	print("VRSMOKE state=", g.state, " wave=", g.wave, " hp=", g.player.hp, " drones=", g.drones.size())
	g.set_paused(true)
	await get_tree().create_timer(0.5, true).timeout
	g.set_paused(false)
	g._open_armory()
	await get_tree().create_timer(3.0).timeout
	print("VRSMOKE armory buttons=", g._armory_buttons.size())
	get_tree().quit()
