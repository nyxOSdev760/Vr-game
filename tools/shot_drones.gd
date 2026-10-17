extends SceneTree
# Lines up the drone models facing -Z and renders them from the front.
func _init():
	var paths = ["res://assets/drones/Enemy_EyeDrone.gltf", "res://assets/drones/bee_bot.glb", "res://assets/drones/bicopter.glb", "res://assets/drones/recon_drone.glb", "res://assets/drones/Enemy_Trilobite.gltf"]
	var scales = [1.0, 0.8, 2.0, 0.45, 0.4]
	var yaws = [PI, PI, 0.0, 0.0, PI]
	var x := -4.0
	for i in paths.size():
		var n: Node3D = load(paths[i]).instantiate()
		n.scale = Vector3.ONE * scales[i]
		n.position = Vector3(x, 1, 0)
		n.rotation.y = yaws[i]
		x += 2.0
		root.add_child(n)
	for j in 4:
		var g: Node3D = load(["res://assets/guns/Gun_Pistol.gltf","res://assets/guns/Gun_Revolver.gltf","res://assets/guns/Gun_Rifle.gltf","res://assets/guns/Gun_Sniper.gltf"][j]).instantiate()
		g.rotation.y = -PI / 2
		g.position = Vector3(-5.5, 2.6 - j * 0.45, -1.5)
		root.add_child(g)
	var cam := Camera3D.new(); root.add_child(cam)
	var l := DirectionalLight3D.new(); l.rotation_degrees = Vector3(-40, 160, 0); root.add_child(l)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(0.4, 0.45, 0.5); env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = 0.6; env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; root.add_child(env)
	await process_frame
	cam.look_at_from_position(Vector3(0, 1.5, -7), Vector3(0, 1, 0))
	cam.make_current()
	await process_frame; await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://build/drones_front.png")
	quit()
