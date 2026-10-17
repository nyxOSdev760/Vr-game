extends Node
## Pooled visual effects: explosions, sparks, tracers, spawn rings and floating damage numbers.
## Autoloaded as `FX`.

var glow_tex: GradientTexture2D
var add_mat: StandardMaterial3D
var smoke_mat: StandardMaterial3D

var _explosions: Array = []
var _sparks: Array[CPUParticles3D] = []
var _tracers: Array = []
var _rings: Array = []
var _numbers: Array = []
var _flashes: Array = []
var _ei := 0
var _spi := 0
var _ti := 0
var _ri := 0
var _ni := 0
var _fi := 0


func _ready() -> void:
	glow_tex = radial_texture([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)], [0.0, 0.3, 1.0])
	add_mat = additive_material(Color.WHITE, glow_tex)
	add_mat.vertex_color_use_as_albedo = true
	add_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat = StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.albedo_texture = glow_tex
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	for i in 8: _explosions.append(_make_explosion())
	for i in 12: _sparks.append(_make_sparks())
	for i in 28: _tracers.append(_make_tracer())
	for i in 8: _rings.append(_make_ring())
	for i in 16: _numbers.append(_make_number())
	for i in 3:
		var l := OmniLight3D.new()
		l.omni_range = 7.0
		l.light_energy = 0.0
		l.visible = false
		add_child(l)
		_flashes.append({"light": l, "t": 0.0, "dur": 0.2, "e": 0.0})


static func radial_texture(colors: Array, offsets: Array, size := 64) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


static func additive_material(color: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	if tex: m.albedo_texture = tex
	return m


static func ramp(colors: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	return g


func _particles(amount: int, lifetime: float, mesh: Mesh, mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.mesh = mesh
	p.material_override = mat
	p.direction = Vector3.UP
	p.spread = 180.0
	add_child(p)
	return p


func _make_explosion() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var fire := _particles(42, 0.7, q, add_mat)
	fire.initial_velocity_min = 2.0
	fire.initial_velocity_max = 7.5
	fire.damping_min = 4.0
	fire.damping_max = 7.0
	fire.gravity = Vector3(0, 1.5, 0)
	fire.scale_amount_min = 0.6
	fire.scale_amount_max = 1.8
	fire.color_ramp = ramp([Color(1, 0.95, 0.75, 1), Color(1, 0.55, 0.12, 0.9), Color(0.6, 0.12, 0.05, 0)], [0.0, 0.35, 1.0])
	fire.reparent(root)
	var sq := QuadMesh.new()
	sq.size = Vector2(0.9, 0.9)
	var smoke := _particles(14, 1.6, sq, smoke_mat)
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 2.2
	smoke.damping_min = 1.0
	smoke.damping_max = 2.0
	smoke.gravity = Vector3(0, 0.9, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.0
	smoke.color_ramp = ramp([Color(0.25, 0.22, 0.2, 0.0), Color(0.2, 0.18, 0.17, 0.55), Color(0.3, 0.28, 0.26, 0)], [0.0, 0.15, 1.0])
	smoke.reparent(root)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.18, 0.19, 0.2)
	dm.metallic = 0.7
	dm.roughness = 0.45
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.04, 0.09)
	var debris := _particles(16, 2.2, bm, dm)
	debris.initial_velocity_min = 3.0
	debris.initial_velocity_max = 8.0
	debris.gravity = Vector3(0, -12, 0)
	debris.angular_velocity_min = -540
	debris.angular_velocity_max = 540
	debris.scale_amount_min = 0.5
	debris.scale_amount_max = 1.6
	debris.particle_flag_rotate_y = true
	debris.reparent(root)
	var base := {}
	for k in {"fire": fire, "smoke": smoke, "debris": debris}.keys():
		var p: CPUParticles3D = {"fire": fire, "smoke": smoke, "debris": debris}[k]
		base[k] = [p.scale_amount_min, p.scale_amount_max, p.initial_velocity_min, p.initial_velocity_max]
	return {"root": root, "fire": fire, "smoke": smoke, "debris": debris, "base": base}


func _make_sparks() -> CPUParticles3D:
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	var p := _particles(14, 0.35, q, add_mat)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -7, 0)
	p.spread = 70.0
	p.color_ramp = ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 0)], [0.0, 1.0])
	return p


func _make_tracer() -> Dictionary:
	var pivot := Node3D.new()
	pivot.visible = false
	add_child(pivot)
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.012, 0.012, 1.0)
	m.mesh = b
	m.position = Vector3(0, 0, -0.5)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := additive_material(Color(1.0, 0.82, 0.55, 0.9))
	m.material_override = mat
	pivot.add_child(m)
	return {"pivot": pivot, "mesh": m, "mat": mat, "life": 0.0, "dur": 0.07}


func _make_ring() -> Dictionary:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	t.rings = 32
	t.ring_segments = 4
	m.mesh = t
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := additive_material(GameData.C_HAZARD)
	m.material_override = mat
	m.visible = false
	add_child(m)
	return {"mesh": m, "mat": mat, "t": 0.0, "dur": 0.8, "max": 2.5}


func _make_number() -> Dictionary:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.pixel_size = 0.004
	l.font = GameData.FONT_HEAD
	l.font_size = 64
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.visible = false
	l.render_priority = 10
	add_child(l)
	return {"label": l, "t": 0.0, "vel": Vector3.ZERO}


# ---------------------------------------------------------------- spawning
func explode(pos: Vector3, size := 1.0, color := Color(1, 0.5, 0.15)) -> void:
	var e: Dictionary = _explosions[_ei]
	_ei = (_ei + 1) % _explosions.size()
	var root: Node3D = e.root
	root.global_position = pos
	var base: Dictionary = e.base
	for k in ["fire", "smoke", "debris"]:
		var p: CPUParticles3D = e[k]
		var b: Array = base[k]
		p.scale_amount_min = b[0] * size
		p.scale_amount_max = b[1] * size
		p.initial_velocity_min = b[2] * sqrt(size)
		p.initial_velocity_max = b[3] * sqrt(size)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.15 * size
		p.restart()
		p.emitting = true
	var fire: CPUParticles3D = e.fire
	fire.color_ramp.set_color(1, Color(color.r, color.g, color.b, 0.9))
	flash(pos, color, 3.5 * size, 0.25)


func sparks(pos: Vector3, normal: Vector3, color := Color(1, 0.7, 0.3), amount := 12) -> void:
	var p := _sparks[_spi]
	_spi = (_spi + 1) % _sparks.size()
	p.global_position = pos
	p.direction = normal if normal.length() > 0.1 else Vector3.UP
	p.amount = amount
	p.color_ramp.set_color(0, color.lightened(0.5))
	p.color_ramp.set_color(1, Color(color.r, color.g, color.b, 0))
	p.restart()
	p.emitting = true


func tracer(from: Vector3, to: Vector3, color := Color(1.0, 0.82, 0.55), width := 0.012) -> void:
	var t: Dictionary = _tracers[_ti]
	_ti = (_ti + 1) % _tracers.size()
	var d := from.distance_to(to)
	if d < 0.05: return
	var pivot: Node3D = t.pivot
	pivot.visible = true
	pivot.global_position = from
	var up := Vector3.UP if absf((to - from).normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	pivot.look_at(to, up)
	pivot.scale = Vector3(width / 0.012, width / 0.012, d)
	var mat: StandardMaterial3D = t.mat
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	t.life = t.dur


func ring(pos: Vector3, color: Color, max_scale := 2.6, dur := 0.8) -> void:
	var r: Dictionary = _rings[_ri]
	_ri = (_ri + 1) % _rings.size()
	var m: MeshInstance3D = r.mesh
	m.global_position = pos
	m.visible = true
	var mat: StandardMaterial3D = r.mat
	mat.albedo_color = color
	r.t = 0.0
	r.dur = dur
	r.max = max_scale


func number(pos: Vector3, value: float, crit := false) -> void:
	var n: Dictionary = _numbers[_ni]
	_ni = (_ni + 1) % _numbers.size()
	var l: Label3D = n.label
	l.text = str(int(round(value))) + ("!" if crit else "")
	l.modulate = GameData.C_HAZARD if crit else GameData.C_PAPER
	l.font_size = 84 if crit else 60
	l.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, randf_range(-0.15, 0.15))
	l.visible = true
	n.t = 0.0
	n.vel = Vector3(randf_range(-0.3, 0.3), 1.3, randf_range(-0.3, 0.3))


func flash(pos: Vector3, color: Color, energy := 3.0, dur := 0.15) -> void:
	var f: Dictionary = _flashes[_fi]
	_fi = (_fi + 1) % _flashes.size()
	var l: OmniLight3D = f.light
	l.global_position = pos
	l.light_color = color
	l.visible = true
	f.t = 0.0
	f.dur = dur
	f.e = energy


func _process(delta: float) -> void:
	for t in _tracers:
		if t.life <= 0.0: continue
		t.life -= delta
		var mat: StandardMaterial3D = t.mat
		if t.life <= 0.0:
			(t.pivot as Node3D).visible = false
		else:
			mat.albedo_color.a = 0.9 * t.life / t.dur
	for r in _rings:
		var m: MeshInstance3D = r.mesh
		if not m.visible: continue
		r.t += delta
		var k: float = r.t / r.dur
		if k >= 1.0:
			m.visible = false
			continue
		var s: float = 0.3 + (float(r.max) - 0.3) * (1.0 - pow(1.0 - k, 2.0))
		m.scale = Vector3(s, 1.0, s)
		(r.mat as StandardMaterial3D).albedo_color.a = 1.0 - k
	for n in _numbers:
		var l: Label3D = n.label
		if not l.visible: continue
		n.t += delta
		if n.t > 0.9:
			l.visible = false
			continue
		l.global_position += n.vel * delta
		n.vel.y -= 1.2 * delta
		l.modulate.a = clampf(1.6 - n.t * 1.8, 0.0, 1.0)
	for f in _flashes:
		var l: OmniLight3D = f.light
		if not l.visible: continue
		f.t += delta
		if f.t >= f.dur:
			l.visible = false
			continue
		l.light_energy = float(f.e) * (1.0 - f.t / f.dur)


func clear() -> void:
	for t in _tracers:
		t.life = 0.0
		(t.pivot as Node3D).visible = false
	for r in _rings: (r.mesh as MeshInstance3D).visible = false
	for n in _numbers: (n.label as Label3D).visible = false
