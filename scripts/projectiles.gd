extends Node3D
## Pool of drone rounds. Heavy rounds can be shot out of the air.

var player: Node  # player.gd
var _pool: Array = []
var _sphere: SphereMesh


func _ready() -> void:
	_sphere = SphereMesh.new()
	_sphere.radius = 1.0
	_sphere.height = 2.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	for i in 64: _pool.append(_make())


func _make() -> Dictionary:
	var node := Node3D.new()
	node.visible = false
	add_child(node)
	var core := MeshInstance3D.new()
	core.mesh = _sphere
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(core)
	var halo := MeshInstance3D.new()
	halo.mesh = _sphere
	var hm := FX.additive_material(Color(1, 0.4, 0.2, 0.45))
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.add_child(halo)
	var body := StaticBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	cs.shape = sh
	body.add_child(cs)
	node.add_child(body)
	var o := {"node": node, "core": core, "halo": halo, "cmat": cm, "hmat": hm, "body": body, "shape": sh,
		"alive": false, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "r": 0.1, "dmg": 0.0, "life": 0.0,
		"shootable": false, "kind": "", "seed": randf() * 10.0}
	body.set_meta("orb", o)
	body.set_meta("owner", self)
	return o


func fire(from: Vector3, vel: Vector3, r: float, dmg: float, color: Color, shootable := false, kind := "orb") -> void:
	var o: Dictionary = {}
	for p in _pool:
		if not p.alive:
			o = p
			break
	if o.is_empty(): return
	o.alive = true
	o.pos = from
	o.vel = vel
	o.r = r
	o.dmg = dmg
	o.life = 7.0
	o.shootable = shootable
	o.kind = kind
	var node: Node3D = o.node
	node.visible = true
	node.global_position = from
	var core: MeshInstance3D = o.core
	if kind == "bolt":
		core.scale = Vector3(r, r, r * 7.0)
		node.look_at(from + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)
	else:
		core.scale = Vector3.ONE * r
		node.rotation = Vector3.ZERO
	(o.cmat as StandardMaterial3D).albedo_color = color.lerp(Color.WHITE, 0.55)
	(o.hmat as StandardMaterial3D).albedo_color = Color(color, 0.45)
	var body: StaticBody3D = o.body
	body.collision_layer = GameData.L_ORB if shootable else 0
	(o.shape as SphereShape3D).radius = r * 1.8


func kill(o: Dictionary, fx := true) -> void:
	if not o.alive: return
	o.alive = false
	(o.node as Node3D).visible = false
	(o.body as StaticBody3D).collision_layer = 0
	if fx:
		var c: Color = (o.hmat as StandardMaterial3D).albedo_color
		FX.sparks(o.pos, Vector3.UP, Color(c, 1.0), 10)


func clear() -> void:
	for o in _pool: kill(o, false)


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var t := Time.get_ticks_msec() * 0.001
	for o in _pool:
		if not o.alive: continue
		o.life -= delta
		var old: Vector3 = o.pos
		var nw: Vector3 = old + (o.vel as Vector3) * delta
		o.pos = nw
		var node: Node3D = o.node
		node.global_position = nw
		if o.kind != "bolt":
			(o.halo as MeshInstance3D).scale = Vector3.ONE * (1.7 + sin(t * 30.0 + float(o.seed)) * 0.25)
		var q := PhysicsRayQueryParameters3D.create(old, nw, GameData.L_WORLD)
		var hit := space.intersect_ray(q)
		if o.life <= 0.0 or not hit.is_empty() or absf(nw.x) > GameData.ARENA + 8.0 or absf(nw.z) > GameData.ARENA + 8.0:
			if not hit.is_empty(): o.pos = hit.position
			if player and (o.pos as Vector3).distance_to(player.head_position()) < 6.0:
				Sfx.play_at("impact_world", o.pos, -10.0, 1.6)
			kill(o, true)
			continue
		if player and player.alive and player.hit_test(old, nw, float(o.r)):
			player.hurt(float(o.dmg), (o.vel as Vector3).normalized())
			kill(o, true)
