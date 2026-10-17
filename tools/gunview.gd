extends Node3D
## Side view of each gun as mounted in a hand (origin = aim pose, -Z forward) with markers.
func _ready() -> void:
	var main := get_parent()
	main.ui.visible = false
	main.player.visible = false
	for d in main.drones: d.queue_free()
	main.drones.clear()
	var ids := ["pistol", "revolver", "rifle", "sniper"]
	for i in ids.size():
		var hand := Node3D.new()
		add_child(hand)
		hand.global_position = Vector3(0, 10.6 - i * 0.4, 0)
		var g := Gun.new()
		hand.add_child(g)
		g.aim_node = hand
		g.set_weapon(ids[i])
		var m := MeshInstance3D.new()
		var s := SphereMesh.new(); s.radius = 0.012; s.height = 0.024
		m.mesh = s
		hand.add_child(m)
		var fwd := MeshInstance3D.new()
		var b := BoxMesh.new(); b.size = Vector3(0.004, 0.004, 0.6)
		fwd.mesh = b; fwd.position = Vector3(0, 0, -0.3)
		hand.add_child(fwd)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 35
	cam.look_at_from_position(Vector3(2.2, 10.0, -0.25), Vector3(0, 10.0, -0.25))
	cam.make_current()
	for k in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://build/guns_side.png")
	get_tree().quit()
