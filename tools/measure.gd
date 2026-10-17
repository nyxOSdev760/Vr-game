extends SceneTree
# Prints AABB size/offset and animations for every model under res://assets.
func _init():
	for dir in ["drones", "guns", "props", "outpost", "lunar", "station", "pickups"]:
		var d := DirAccess.open("res://assets/" + dir)
		for f in d.get_files():
			if not (f.ends_with(".glb") or f.ends_with(".gltf")): continue
			var p := "res://assets/%s/%s" % [dir, f]
			var s: PackedScene = load(p)
			var n: Node3D = s.instantiate()
			root.add_child(n)
			var box := _aabb(n, Transform3D.IDENTITY)
			var anims := []
			var ap: AnimationPlayer = n.find_child("AnimationPlayer", true, false)
			if ap: anims = ap.get_animation_list()
			print("%s size=(%.2f,%.2f,%.2f) min=(%.2f,%.2f,%.2f) anims=%s" % [p.trim_prefix("res://assets/"), box.size.x, box.size.y, box.size.z, box.position.x, box.position.y, box.position.z, ",".join(anims)])
			n.queue_free()
	quit()

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D: t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b := t * (n as MeshInstance3D).get_aabb()
		out = b; first = false
	for c in n.get_children():
		var cb := _aabb(c, t)
		if cb.size == Vector3.ZERO: continue
		if first: out = cb; first = false
		else: out = out.merge(cb)
	return out
