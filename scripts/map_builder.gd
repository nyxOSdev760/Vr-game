extends Node3D
## Builds each arena out of real kit models (Sci-Fi Essentials, Quaternius, Kenney), gives every
## solid prop a matching collider, and sets the sky, fog and light for the map.

var id := ""
var obstacles: Array[AABB] = []
var env: Environment
var sun: DirectionalLight3D
var _scene_cache := {}
var _aabb_cache := {}

const P := "res://assets/props/"
const O := "res://assets/outpost/"
const LU := "res://assets/lunar/"
const ST := "res://assets/station/"


func build(map_id: String, world_env: WorldEnvironment, p_sun: DirectionalLight3D) -> void:
	id = map_id
	env = world_env.environment
	sun = p_sun
	for c in get_children(): c.free()
	obstacles.clear()
	match map_id:
		"outpost": _outpost()
		"lunar": _lunar()
		_: _yard()


# ---------------------------------------------------------------- helpers
func _scene(path: String) -> PackedScene:
	if not _scene_cache.has(path): _scene_cache[path] = load(path)
	return _scene_cache[path]


static func mesh_aabb(n: Node, xf: Transform3D) -> AABB:
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
			else: out = out.merge(b)
		var sub := mesh_aabb(c, ct)
		if sub.size != Vector3.ZERO:
			if first:
				out = sub
				first = false
			else: out = out.merge(sub)
	return out


func _model_aabb(path: String) -> AABB:
	if not _aabb_cache.has(path):
		var n := _scene(path).instantiate()
		_aabb_cache[path] = mesh_aabb(n, Transform3D.IDENTITY)
		n.free()
	return _aabb_cache[path]


## Places one model. `recenter` moves the model so its footprint is centred on the point and it
## sits on the ground (the Kenney kit pieces are authored off-centre).
func place(path: String, x: float, z: float, yaw_deg := 0.0, s := 1.0, solid := true, y := 0.0, recenter := false, shadows := true) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(x, y, z)
	root.rotation.y = deg_to_rad(yaw_deg)
	add_child(root)
	var inst: Node3D = _scene(path).instantiate()
	inst.scale = Vector3.ONE * s
	var box := _model_aabb(path)
	if recenter:
		var c := box.get_center()
		inst.position = Vector3(-c.x, -box.position.y, -c.z) * s
	root.add_child(inst)
	if not shadows:
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if solid:
		var lb := AABB(inst.position + box.position * s, box.size * s)
		_add_collider(root, lb)
	return root


func _add_collider(root: Node3D, local_box: AABB) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = GameData.L_WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = local_box.size.max(Vector3(0.05, 0.05, 0.05))
	cs.shape = bs
	cs.position = local_box.get_center()
	body.add_child(cs)
	root.add_child(body)
	# world-space footprint for player push-out
	var xf := root.global_transform if root.is_inside_tree() else root.transform
	obstacles.append(xf * local_box)


## A straight run of identical pieces drawn with MultiMesh (one draw per surface) and a single
## long collider.
func row(path: String, a: Vector3, b: Vector3, count: int, s := 1.0, yaw_deg := 0.0, solid := true, recenter := true) -> void:
	var proto: Node3D = _scene(path).instantiate()
	var box := _model_aabb(path)
	var offset := Vector3.ZERO
	if recenter:
		var c := box.get_center()
		offset = Vector3(-c.x, -box.position.y, -c.z) * s
	var xfs: Array[Transform3D] = []
	for i in count:
		var k := 0.5 if count == 1 else float(i) / float(count - 1)
		var p := a.lerp(b, k)
		var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * s)
		xfs.append(Transform3D(basis, p + Basis(Vector3.UP, deg_to_rad(yaw_deg)) * offset))
	for mi in proto.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.mesh: continue
		var local := _relative_xf(proto, m)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m.mesh
		mm.instance_count = count
		for i in count: mm.set_instance_transform(i, xfs[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if m.material_override: mmi.material_override = m.material_override
		add_child(mmi)
	proto.free()
	if solid:
		var lb := AABB(box.position * s + offset, box.size * s)
		var r0 := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), a) * lb
		var r1 := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), b) * lb
		var full := r0.merge(r1)
		var holder := Node3D.new()
		add_child(holder)
		_add_collider(holder, full)


func _relative_xf(root: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur := n
	while cur and cur != root:
		if cur is Node3D: xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _ground(tex: String, tile: float, tint := Color.WHITE, size := 220.0) -> void:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	m.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ground/%s_color.jpg" % tex)
	mat.albedo_color = tint
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/ground/%s_normal.jpg" % tex)
	mat.normal_scale = 0.8
	mat.roughness_texture = load("res://assets/ground/%s_rough.jpg" % tex)
	mat.roughness = 1.0
	mat.uv1_scale = Vector3(size / tile, size / tile, 1)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	var body := StaticBody3D.new()
	body.collision_layer = GameData.L_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)


func _sky(top: Color, horizon: Color, ground_bottom: Color, ground_horizon: Color, sun_curve := 0.15) -> void:
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = top
	sm.sky_horizon_color = horizon
	sm.ground_bottom_color = ground_bottom
	sm.ground_horizon_color = ground_horizon
	sm.sun_curve = sun_curve
	var sky := Sky.new()
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky


func _starfield() -> void:
	var img := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color(0.004, 0.006, 0.014))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2600:
		var x := rng.randi_range(0, 2047)
		var y := rng.randi_range(0, 560)
		var b := pow(rng.randf(), 3.0) * 0.9 + 0.08
		var c := Color(b, b, b * 1.08)
		img.set_pixel(x, y, c)
		if b > 0.7:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px := clampi(x + o.x, 0, 2047)
				var py := clampi(y + o.y, 0, 1023)
				img.set_pixel(px, py, c * 0.4)
	var tex := ImageTexture.create_from_image(img)
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = tex
	var sky := Sky.new()
	sky.sky_material = pm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky


func _no_fog(n: Node) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is BaseMaterial3D:
				var d := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.disable_fog = true
				d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.set_surface_override_material(i, d)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _fog(color: Color, density: float, sky_affect := 0.6) -> void:
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = color
	env.fog_density = density
	env.fog_sky_affect = sky_affect
	env.fog_aerial_perspective = 0.0


func _light(dir_deg: Vector3, color: Color, energy: float, ambient: Color, ambient_energy: float) -> void:
	sun.rotation_degrees = dir_deg
	sun.light_color = color
	sun.light_energy = energy
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0


func _perimeter(path: String, s: float, piece: float, inset := 0.6, yaw_off := 0.0) -> void:
	var L := GameData.ARENA + inset
	var n := int(ceil(2.0 * L / piece)) + 1
	row(path, Vector3(-L, 0, -L), Vector3(L, 0, -L), n, s, 0.0 + yaw_off)
	row(path, Vector3(-L, 0, L), Vector3(L, 0, L), n, s, 180.0 + yaw_off)
	row(path, Vector3(-L, 0, -L), Vector3(-L, 0, L), n, s, 90.0 + yaw_off)
	row(path, Vector3(L, 0, -L), Vector3(L, 0, L), n, s, -90.0 + yaw_off)


# ---------------------------------------------------------------- Drone Yard
func _yard() -> void:
	_sky(Color(0.106, 0.157, 0.188), Color(0.64, 0.55, 0.44), Color(0.27, 0.26, 0.23), Color(0.6, 0.53, 0.43))
	_fog(Color(0.52, 0.47, 0.4), 0.012)
	_light(Vector3(-38, 35, 0), Color(1.0, 0.86, 0.7), 1.25, Color(0.72, 0.74, 0.76), 0.55)
	_ground("Concrete034", 4.0, Color(0.86, 0.83, 0.78))
	_perimeter(ST + "structure-barrier-high.glb", 2.5, 2.75)

	# low cover: big crates you can crouch behind
	for c in [[0, -6, 0], [-6, 1.5, 90], [6, 2.5, 90], [0.5, 8, 0], [-10, 6, 0], [10, -6, 0]]:
		place(P + "Prop_Crate_Large.gltf", c[0], c[1], c[2], 0.75)
	place(P + "Prop_Crate_Tarp_Large.gltf", -3, -11.5, 8, 0.8)
	place(P + "Prop_Crate_Tarp_Large.gltf", 4, 12, -6, 0.8)
	# crate stacks
	for c in [[-12.5, -2.0, 0], [-12.5, -0.4, 4], [12.5, 1.5, -3], [12.5, 3.1, 0], [3, -12.5, 0], [4.6, -12.5, 6],
			[-4, 12.5, 2], [-2.4, 12.5, -5], [-14, -13, 15], [14, 13, -20]]:
		place(P + "Prop_Crate.gltf", c[0], c[1], c[2], 0.9)
	place(P + "Prop_Crate.gltf", -12.5, -1.2, 40, 0.75, true, 1.35)
	place(P + "Prop_Crate.gltf", 3.8, -12.5, -25, 0.75, true, 1.35)
	place(P + "Prop_Crate_Tarp.gltf", 12.5, 2.3, 10, 0.8, true, 1.35)
	# tall towers drones like to hide behind
	for c in [[-9, -9, 45], [9, -9, -45], [-9, 9, 135], [9, 9, -135]]:
		place(P + "Prop_SatelliteDish.gltf", c[0], c[1], c[2], 1.0)
	# locker walls
	row(P + "Prop_Locker.gltf", Vector3(-9, 0, -16), Vector3(-3, 0, -16), 7, 1.0, 0.0, true, false)
	row(P + "Prop_Locker.gltf", Vector3(4, 0, 16), Vector3(10, 0, 16), 7, 1.0, 180.0, true, false)
	row(P + "Prop_Locker.gltf", Vector3(16, 0, -11), Vector3(16, 0, -5), 7, 1.0, -90.0, true, false)
	row(P + "Prop_Locker.gltf", Vector3(-16, 0, 5), Vector3(-16, 0, 11), 7, 1.0, 90.0, true, false)
	place(P + "Prop_Shelves_WideTall.gltf", -16.2, -4, 90)
	place(P + "Prop_Shelves_WideTall.gltf", 16.2, 5, -90)
	place(P + "Prop_Shelves_WideShort.gltf", -1, -17.5, 0)
	# barrels
	for c in [[7, -2], [7.7, -1.4], [7.2, -0.6], [-8, -6], [-8.6, -5.3], [11, 9], [11.6, 9.6], [-11, 11], [2, -17], [-17, -2], [17.3, -1]]:
		place(P + ("Prop_Barrel1.gltf" if randf() < 0.5 else "Prop_Barrel2_Closed.gltf"), c[0], c[1], randf() * 360.0)
	place(P + "Prop_Chest.gltf", -4.5, -14, 30)
	place(P + "Prop_Chest.gltf", 15, -14.5, -60)
	place(P + "Prop_Ammo.gltf", 13.3, 0.4, 20)
	for c in [[17.4, -17.4, 0], [-17.4, 17.4, 90], [17.5, 14.5, 0], [-17.5, -15, 0], [-15.6, -17.4, 0]]:
		place(ST + "container-tall.glb", c[0], c[1], c[2], 3.0, true, 0.0, true)
	place(ST + "container-wide.glb", 14.5, 17.4, 0, 3.0, true, 0.0, true)
	# skyline beyond the wall
	place(LU + "hangar_largeA.glb", -30, -36, 15, 6.0, false, 0.0, true)
	place(LU + "hangar_largeB.glb", 36, -30, -30, 6.0, false, 0.0, true)
	place(LU + "machine_generatorLarge.glb", 42, 10, 80, 7.0, false, 0.0, true)
	place(LU + "satelliteDish_large.glb", -40, 18, 120, 11.0, false, 0.0, true)
	place(LU + "supports_high.glb", 24, 40, 0, 9.0, false, 0.0, true)
	place(LU + "hangar_roundA.glb", -18, 44, 180, 6.0, false, 0.0, true)
	place(LU + "structure_detailed.glb", 46, -4, 10, 8.0, false, 0.0, true)


# ---------------------------------------------------------------- Red Outpost
func _outpost() -> void:
	_sky(Color(0.32, 0.17, 0.14), Color(0.86, 0.58, 0.4), Color(0.35, 0.2, 0.13), Color(0.78, 0.5, 0.34), 0.2)
	_fog(Color(0.74, 0.47, 0.32), 0.014)
	_light(Vector3(-30, -50, 0), Color(1.0, 0.8, 0.62), 1.3, Color(0.8, 0.6, 0.5), 0.55)
	_ground("Ground078", 5.0, Color(1.0, 0.7, 0.55))

	place(O + "base_large.glb", -13, -13, 30)
	place(O + "geodesic_dome.glb", 13, -12.5, 0)
	place(O + "building_l.glb", 13, 12.5, 180, 1.0, true, 0.0, true)
	place(O + "house_cylinder.glb", -13, 12.5, 20)
	place(O + "house_long.glb", 0, -16, 90, 1.0, true, 0.0, true)
	place(O + "house_open.glb", -16.5, 0, 90, 1.0, true, 0.0, true)
	place(O + "house_single.glb", 16.5, 0.5, -90, 1.0, true, 0.0, true)
	place(O + "solar_panel_structure.glb", -6, 9.5, 15)
	for c in [[5, -6, 0], [6.5, -6, 0], [-5, -5.5, 90], [-5, -4, 90], [9, 4, 30]]:
		place(O + "solar_panel_ground.glb", c[0], c[1], c[2], 1.0)
	place(O + "rover.glb", 6.5, 8, 40, 0.75, true, 0.0, true)
	place(O + "round_rover.glb", -8.5, -8.5, -20, 0.7, true, 0.0, true)
	# low rocks for cover
	for c in [[0, -7, 0, 0.55], [-6.5, 2, 70, 0.6], [6.5, 2.5, 140, 0.55], [1, 9, 200, 0.6], [-10, 5.5, 20, 0.7], [10.5, -5.5, 300, 0.7], [-2.5, 15.5, 90, 0.8]]:
		place(O + "rock.glb", c[0], c[1], c[2], c[3], true, 0.0, true)
	# alien flora
	var flora := [["tree_spikes", -3, -10.5], ["tree_lava", 9, -1], ["tree_floating", -9.5, -2], ["tree_blob", 4, 15], ["tree_swirl", -5.5, 16.5],
			["tree_spiral", 16, -5], ["tree_light", -15.5, -6], ["tree_lava", 3, -3.5], ["tree_light", -1.5, 4.5], ["tree_spikes", 17, 16.5]]
	for f in flora: place(O + f[0] + ".glb", f[1], f[2], randf() * 360.0, randf_range(0.85, 1.15), false)
	for i in 34:
		var a := randf() * TAU
		var r := randf_range(4.0, 18.0)
		var k: String = ["plant", "bush", "grass", "grass"][i % 4]
		place(O + k + ".glb", cos(a) * r, sin(a) * r, randf() * 360.0, randf_range(0.6, 1.1), false, 0.0, false, false)
	# rock wall around the arena
	var L := GameData.ARENA + 3.5
	for i in 28:
		var t := float(i) / 28.0 * 4.0
		var side := int(t)
		var f := t - side
		var p := Vector3.ZERO
		match side:
			0: p = Vector3(-L + 2 * L * f, 0, -L)
			1: p = Vector3(L, 0, -L + 2 * L * f)
			2: p = Vector3(L - 2 * L * f, 0, L)
			_: p = Vector3(-L, 0, L - 2 * L * f)
		place(O + "rock_large.glb", p.x + randf_range(-1, 1), p.z + randf_range(-1, 1), randf() * 360.0, randf_range(1.0, 1.4), false, -0.4, true)
	# horizon
	place(O + "spaceship.glb", 34, -8, 25, 1.3, false, 0.0, true)
	place(O + "geodesic_dome.glb", -34, 28, 0, 1.4, false)
	place(O + "base_large.glb", 38, 30, 0, 1.2, false)
	place(O + "house_cylinder.glb", -40, -22, 0, 1.3, false)
	var planet := place(O + "planet.glb", -150, -230, 30, 34.0, false, 95.0, false, false)
	_no_fog(planet)


# ---------------------------------------------------------------- Lunar Hangar
func _lunar() -> void:
	_starfield()
	env.fog_enabled = false
	_light(Vector3(-24, 140, 0), Color(1.0, 0.98, 0.94), 1.6, Color(0.42, 0.47, 0.6), 0.45)
	_ground("Moon", 6.0, Color(0.78, 0.79, 0.84))
	_perimeter(LU + "structure_detailed.glb", 2.4, 2.4, 1.2)

	# the rocket on the pad
	var rx := 0.0
	var rz := -14.0
	place(LU + "rocket_baseA.glb", rx, rz, 0, 3.0, true, 0.0, true)
	place(LU + "rocket_fuelA.glb", rx, rz, 0, 3.0, false, 4.8, true)
	place(LU + "rocket_sidesA.glb", rx, rz, 0, 3.0, false, 6.3, true)
	place(LU + "rocket_fuelB.glb", rx, rz, 0, 3.0, false, 9.3, true)
	place(LU + "rocket_topA.glb", rx, rz, 0, 3.0, false, 12.3, true)
	place(LU + "platform_large.glb", rx, rz, 0, 4.0, false, 0.0, true)

	place(LU + "hangar_largeA.glb", -15.5, -12, 90, 3.6, true, 0.0, true)
	place(LU + "hangar_largeB.glb", 15.5, -12.5, -90, 3.4, true, 0.0, true)
	place(LU + "hangar_roundGlass.glb", 14, 13.5, 180, 3.2, true, 0.0, true)
	place(LU + "hangar_smallA.glb", -14.5, 13.5, 0, 3.4, true, 0.0, true)
	place(LU + "machine_generatorLarge.glb", -6, -5.5, 0, 2.2, true, 0.0, true)
	place(LU + "machine_generatorLarge.glb", 6.5, 3, 90, 2.2, true, 0.0, true)
	for c in [[0, 7.5, 0], [-10, 5.5, 20], [10, -5.5, -10], [4.5, -8, 45]]:
		place(LU + "structure_closed.glb", c[0], c[1], c[2], 2.0, true, 0.0, true)
	place(LU + "turret_double.glb", 9.5, 7.5, -120, 2.5, true, 0.0, true)
	place(LU + "turret_single.glb", -9.5, -9.5, 45, 2.5, true, 0.0, true)
	for c in [[-9, 9, 0, "rock_largeA"], [8.5, -9.5, 90, "rock_largeB"], [-3, 12, 30, "rock_largeB"], [2.5, -4.5, 200, "rock_largeA"]]:
		place(LU + c[3] + ".glb", c[0], c[1], c[2], 2.8, true, 0.0, true)
	place(LU + "meteor_detailed.glb", -12, 0.5, 0, 3.0, true, 0.0, true)
	place(LU + "meteor_detailed.glb", 12.5, 1, 140, 2.6, true, 0.0, true)
	place(LU + "rock_crystalsLargeA.glb", 3.5, 11.5, 0, 3.0, true, 0.0, true)
	place(LU + "rock_crystalsLargeB.glb", -3.5, -9.5, 60, 3.0, true, 0.0, true)
	place(LU + "barrels.glb", -2, -6, 0, 3.0, true, 0.0, true)
	place(LU + "barrels.glb", 7, -9, 70, 3.0, true, 0.0, true)
	place(LU + "machine_barrelLarge.glb", -7, 10.5, 0, 3.0, true, 0.0, true)
	place(LU + "satelliteDish_large.glb", 17.5, -2, -90, 5.0, true, 0.0, true)
	place(LU + "craft_miner.glb", -17, -1, 10, 3.0, true, 0.0, true)
	place(LU + "rover.glb", 4, 4.5, 30, 6.0, true, 0.0, true)
	place(LU + "crater.glb", 6, -2.5, 0, 6.0, false, -0.05, true, false)
	place(LU + "crater.glb", -7, 6, 90, 5.0, false, -0.05, true, false)
	# horizon
	place(LU + "rock_largeB.glb", -45, 30, 0, 14.0, false, -1.0, true)
	place(LU + "rock_largeA.glb", 48, -20, 70, 16.0, false, -1.0, true)
	place(LU + "rock_largeB.glb", 30, 50, 150, 12.0, false, -1.0, true)
	place(LU + "hangar_largeA.glb", -35, -38, 30, 5.0, false, 0.0, true)
	place(LU + "satelliteDish_detailed.glb", 40, 26, 220, 10.0, false, 0.0, true)
	place(LU + "craterLarge.glb", 0, 46, 0, 30.0, false, -0.3, true, false)
	var earth := place(O + "planet.glb", 170, -260, 0, 18.0, false, 70.0, false, false)
	_no_fog(earth)
