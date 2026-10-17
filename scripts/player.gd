extends XROrigin3D
## The player rig: headset camera, two tracked hands each holding a gun, wrist HUD,
## locomotion, health and the Overclock ability. Falls back to mouse + keyboard without a headset.

var game: Node
var vr := false
var camera: XRCamera3D
var left: XRController3D
var right: XRController3D
var guns: Array = []
var alive := true
var hp := 100.0
var since_hurt := 99.0
var barrier := 0
var head_velocity := Vector3.ZERO
var input_enabled := true

var overclock_t := 0.0
var overclock_cd := 0.0
const OVERCLOCK_TIME := 4.0

var _prev_head := Vector3.ZERO
var _snapped := false
var _btn := {}
var _hurt_v := 0.0
var _hurt_mat: StandardMaterial3D
var _hurt_shell: MeshInstance3D
var _banner_title: Label3D
var _banner_sub: Label3D
var _banner_t := 0.0
var _hud: Label3D
var _hud_t := 0.0
var _shake := 0.0

# desktop
var _yaw := 0.0
var _pitch := 0.0
var _crouch := false
var _mouse_down := false
var _overlay: CanvasLayer
var _hint: Label


func setup(p_game: Node, p_vr: bool) -> void:
	game = p_game
	vr = p_vr
	process_mode = Node.PROCESS_MODE_ALWAYS
	camera = XRCamera3D.new()
	camera.name = "Camera"
	camera.near = 0.03
	camera.far = 600.0
	camera.position = Vector3(0, 1.6, 0)
	add_child(camera)
	camera.current = true

	left = XRController3D.new()
	left.name = "Left"
	left.tracker = &"left_hand"
	left.pose = &"aim"
	add_child(left)
	right = XRController3D.new()
	right.name = "Right"
	right.tracker = &"right_hand"
	right.pose = &"aim"
	add_child(right)

	for c in [right, left]:
		var g := Gun.new()
		g.name = "Gun"
		g.controller = c if vr else null
		(c as XRController3D).add_child(g)
		g.aim_node = c
		guns.append(g)
	if not vr:
		var g0: Gun = guns[0]
		g0.reparent(camera, false)
		g0.position = Vector3(0.2, -0.22, -0.4)
		g0.rotation = Vector3(0, 0.03, 0)
		g0.aim_node = camera
		g0.laser_enabled = false
		g0.compact_ammo()
		var g1: Gun = guns[1]
		g1.visible = false
		g1.process_mode = Node.PROCESS_MODE_DISABLED
		guns = [g0]

	_build_feedback()
	_build_hud()
	if not vr: _build_desktop_overlay()


func _build_feedback() -> void:
	_hurt_shell = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 16
	sm.rings = 8
	sm.flip_faces = true
	_hurt_shell.mesh = sm
	_hurt_mat = StandardMaterial3D.new()
	_hurt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hurt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hurt_mat.no_depth_test = true
	_hurt_mat.render_priority = 100
	_hurt_mat.albedo_color = Color(GameData.C_ALARM, 0.0)
	_hurt_shell.material_override = _hurt_mat
	_hurt_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hurt_shell.visible = false
	camera.add_child(_hurt_shell)

	_banner_title = Label3D.new()
	_banner_title.font = GameData.FONT_STENCIL
	_banner_title.font_size = 160
	_banner_title.pixel_size = 0.0022
	_banner_title.modulate = GameData.C_HAZARD
	_banner_title.outline_size = 24
	_banner_title.outline_modulate = Color(0, 0, 0, 0.65)
	_banner_title.no_depth_test = true
	_banner_title.render_priority = 50
	_banner_title.outline_render_priority = 49
	_banner_title.position = Vector3(0, 0.32, -2.2)
	_banner_title.visible = false
	camera.add_child(_banner_title)
	_banner_sub = Label3D.new()
	_banner_sub.font = GameData.FONT_MONO
	_banner_sub.font_size = 56
	_banner_sub.pixel_size = 0.0022
	_banner_sub.modulate = GameData.C_PAPER
	_banner_sub.outline_size = 16
	_banner_sub.outline_modulate = Color(0, 0, 0, 0.65)
	_banner_sub.no_depth_test = true
	_banner_sub.render_priority = 50
	_banner_sub.outline_render_priority = 49
	_banner_sub.position = Vector3(0, 0.1, -2.2)
	_banner_sub.visible = false
	camera.add_child(_banner_sub)


func _build_hud() -> void:
	_hud = Label3D.new()
	_hud.font = GameData.FONT_MONO
	_hud.font_size = 40
	_hud.pixel_size = 0.0008
	_hud.outline_size = 8
	_hud.outline_modulate = Color(0, 0, 0, 0.8)
	_hud.modulate = GameData.C_PAPER
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hud.line_spacing = 2
	if vr:
		left.add_child(_hud)
		_hud.position = Vector3(0.0, 0.06, 0.1)
		_hud.rotation = Vector3(-1.0, 0, 0)
	else:
		camera.add_child(_hud)
		_hud.pixel_size = 0.00055
		_hud.position = Vector3(-0.42, -0.24, -0.6)
		_hud.no_depth_test = true
		_hud.render_priority = 40


func _build_desktop_overlay() -> void:
	_overlay = CanvasLayer.new()
	add_child(_overlay)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 32)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-8, -24)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(cross)
	_hint = Label.new()
	_hint.text = "Desktop mode · click to aim · WASD move · Shift sprint · C crouch · R reload · Q weapon · E overclock · Esc release"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.position = Vector2(16, 8)
	_overlay.add_child(_hint)


# ---------------------------------------------------------------- queries
func head_position() -> Vector3:
	return camera.global_position


func hit_test(a: Vector3, b: Vector3, r: float) -> bool:
	var h := head_position()
	var bottom := Vector3(h.x, maxf(0.25, h.y * 0.45), h.z)
	var pts := Geometry3D.get_closest_points_between_segments(a, b, bottom, h)
	return pts[0].distance_to(pts[1]) < r + 0.24


# ---------------------------------------------------------------- state
func reset_for_run() -> void:
	alive = true
	hp = GameData.max_hp()
	since_hurt = 99.0
	barrier = GameData.lvl("barrier")
	overclock_t = 0.0
	overclock_cd = 0.0
	_hurt_v = 0.0
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	equip(GameData.weapon)


func equip(id: String) -> void:
	GameData.weapon = id
	for g in guns: (g as Gun).set_weapon(id)


func refresh_weapon_stats() -> void:
	for g in guns: (g as Gun).refresh_stats()


func refill() -> void:
	for g in guns: (g as Gun).refill()


func cycle_weapon() -> void:
	var owned: Array = GameData.owned
	if owned.size() < 2: return
	var i := owned.find(GameData.weapon)
	equip(owned[(i + 1) % owned.size()])
	Sfx.play("reload_in", -4.0, 1.2)
	banner(GameData.WEAPONS[GameData.weapon].name.to_upper(), "", 1.0)


func hurt(dmg: float, _dir: Vector3) -> void:
	if not alive or game.state != "playing": return
	if barrier > 0:
		barrier -= 1
		Sfx.play("shield", 0.0)
		FX.ring(head_position() - Vector3(0, 0.3, 0), GameData.C_SIGNAL, 1.2, 0.4)
		_hurt_v = 0.3
		return
	hp -= dmg
	since_hurt = 0.0
	_hurt_v = minf(1.0, _hurt_v + 0.45 + dmg / 40.0)
	_shake = 0.25
	Sfx.play("hurt", 0.0)
	for c in [left, right]: (c as XRController3D).trigger_haptic_pulse("haptic", 0.0, 1.0, 0.12, 0.0)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		end_overclock()
		game.on_player_dead()


func heal(amount: float) -> void:
	hp = minf(GameData.max_hp(), hp + amount)


func banner(title: String, sub := "", dur := 2.5) -> void:
	_banner_title.text = title
	_banner_sub.text = sub
	_banner_title.visible = true
	_banner_sub.visible = sub != ""
	_banner_t = dur


func clear_banner() -> void:
	_banner_t = 0.0
	_banner_title.visible = false
	_banner_sub.visible = false


func try_overclock() -> void:
	if GameData.lvl("overclock") <= 0 or overclock_t > 0.0 or overclock_cd > 0.0: return
	if game.state != "playing": return
	overclock_t = OVERCLOCK_TIME
	overclock_cd = GameData.overclock_cooldown()
	Engine.time_scale = 0.35
	AudioServer.playback_speed_scale = 0.7
	Sfx.play("slowmo", 0.0)
	banner("OVERCLOCK", "", 1.0)


func end_overclock() -> void:
	overclock_t = 0.0
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0


# ---------------------------------------------------------------- input
func _pressed_edge(key: String, down: bool) -> bool:
	var was: bool = _btn.get(key, false)
	_btn[key] = down
	return down and not was


func _unhandled_input(event: InputEvent) -> void:
	if vr: return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mouse_down = mb.pressed
			if mb.pressed:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				if input_enabled: (guns[0] as Gun).try_fire(false)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0022
		_pitch = clampf(_pitch - mm.relative.y * 0.0022, -1.45, 1.45)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		match k:
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else: game.toggle_pause()
			KEY_P: game.toggle_pause()
			KEY_R: (guns[0] as Gun).reload()
			KEY_Q: cycle_weapon()
			KEY_E, KEY_F: try_overclock()
			KEY_C: _crouch = not _crouch


# ---------------------------------------------------------------- update
func _physics_process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	if game.paused: real = delta
	var h := head_position()
	if real > 0.0:
		var hv := (h - _prev_head) / real
		head_velocity = hv if hv.length() < 10.0 else Vector3.ZERO
	_prev_head = h

	if overclock_t > 0.0:
		overclock_t -= real
		if overclock_t <= 0.0: end_overclock()
	elif overclock_cd > 0.0:
		overclock_cd -= real

	if vr: _update_vr(real)
	else: _update_desktop(real)
	_collide()

	if alive and game.state == "playing":
		since_hurt += real
		if since_hurt > GameData.regen_delay() and hp < GameData.max_hp():
			hp = minf(GameData.max_hp(), hp + GameData.regen_rate() * real)

	var show_laser := vr and input_enabled
	for g in guns: (g as Gun).tick(real, show_laser)
	_update_feedback(real)


func _update_vr(dt: float) -> void:
	var move := Vector2.ZERO
	for c in [left, right]:
		var ctl := c as XRController3D
		var gun: Gun = guns[0] if ctl == right else guns[1]
		var id := String(ctl.tracker)
		if not ctl.get_has_tracking_data():
			gun.visible = false
			continue
		gun.visible = true
		var stick := ctl.get_vector2("primary")
		if ctl == right:
			if absf(stick.x) > 0.7 and not _snapped:
				_snap_turn(-signf(stick.x) * PI / 6.0)
				_snapped = true
			elif absf(stick.x) < 0.3:
				_snapped = false
		else:
			move = stick
		if not input_enabled: continue
		var trig := ctl.get_float("trigger") > 0.55
		if trig: gun.try_fire(not _pressed_edge(id + "trig", true))
		else: _pressed_edge(id + "trig", false)
		if _pressed_edge(id + "ax", ctl.is_button_pressed("ax_button")): gun.reload()
		if _pressed_edge(id + "by", ctl.is_button_pressed("by_button")): cycle_weapon()
		if _pressed_edge(id + "grip", ctl.get_float("grip") > 0.75): try_overclock()
		if _pressed_edge(id + "menu", ctl.is_button_pressed("menu_button")): game.toggle_pause()
		# point the gun at the floor to reload, like holstering a mag
		if (-ctl.global_transform.basis.z).y < -0.92 and gun.mag < int(gun.stats.mag): gun.reload()
	if move.length() > 0.15 and alive:
		var fwd := -camera.global_transform.basis.z
		fwd.y = 0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		var rgt := Vector3(-fwd.z, 0, fwd.x)
		var v := (rgt * move.x + fwd * move.y) * 3.0
		global_position += v * dt


func _snap_turn(angle: float) -> void:
	var h := head_position()
	var t := global_transform
	t.origin -= h
	t = t.rotated(Vector3.UP, angle)
	t.origin += h
	global_transform = t


func _update_desktop(dt: float) -> void:
	var f := 0.0
	var s := 0.0
	if input_enabled and alive:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): f += 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): f -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): s += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): s -= 1.0
	var sprint := Input.is_physical_key_pressed(KEY_SHIFT) and not _crouch and f > 0.0
	var sp := 2.2 if _crouch else (7.0 if sprint else 4.5)
	var basis_y := Basis(Vector3.UP, _yaw)
	var v := (basis_y * Vector3(s, 0, -f)).limit_length(1.0) * sp
	global_position += v * dt
	rotation = Vector3(0, _yaw, 0)
	var eye := 1.0 if _crouch else 1.6
	_shake = maxf(0.0, _shake - dt)
	var sh := _shake * 0.06
	camera.position = camera.position.lerp(Vector3(0, eye, 0), clampf(dt * 10.0, 0.0, 1.0)) + Vector3(randf_range(-sh, sh), randf_range(-sh, sh), 0)
	camera.rotation = Vector3(_pitch, 0, 0)
	if _mouse_down and input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		(guns[0] as Gun).try_fire(true)


## Keeps the head out of solid props and inside the arena by shifting the whole rig.
func _collide() -> void:
	var h := head_position()
	var p := h
	for ob in game.map.obstacles:
		var box: AABB = ob
		if box.size.y < 0.45: continue
		var r := 0.25 if box.end.y > 1.25 else 0.12
		var cx := clampf(p.x, box.position.x, box.end.x)
		var cz := clampf(p.z, box.position.z, box.end.z)
		var dx := p.x - cx
		var dz := p.z - cz
		var d2 := dx * dx + dz * dz
		if d2 < r * r:
			if d2 > 1e-8:
				var d := sqrt(d2)
				p.x = cx + dx / d * r
				p.z = cz + dz / d * r
			else:
				var c := box.get_center()
				var px := box.size.x * 0.5 - absf(p.x - c.x)
				var pz := box.size.z * 0.5 - absf(p.z - c.z)
				if px < pz: p.x = c.x + (signf(p.x - c.x) if p.x != c.x else 1.0) * (box.size.x * 0.5 + r)
				else: p.z = c.z + (signf(p.z - c.z) if p.z != c.z else 1.0) * (box.size.z * 0.5 + r)
	var L := GameData.ARENA - 0.5
	p.x = clampf(p.x, -L, L)
	p.z = clampf(p.z, -L, L)
	global_position += Vector3(p.x - h.x, 0, p.z - h.z)


func _update_feedback(dt: float) -> void:
	_hurt_v = maxf(0.0, _hurt_v - dt * 1.6)
	var low := 0.0
	if alive and game.state == "playing" and hp <= 30.0:
		low = 0.22 + 0.12 * sin(Time.get_ticks_msec() * 0.006)
	var hv := maxf(_hurt_v, low)
	_hurt_shell.visible = hv > 0.01
	_hurt_mat.albedo_color = Color(GameData.C_ALARM, hv * 0.38) if overclock_t <= 0.0 else Color(0.3, 0.6, 1.0, 0.12 + hv * 0.3)
	if overclock_t > 0.0: _hurt_shell.visible = true
	if _banner_t > 0.0 and _banner_t != INF:
		_banner_t -= dt
		if _banner_t <= 0.0:
			_banner_title.visible = false
			_banner_sub.visible = false
	_hud_t -= dt
	if _hud_t <= 0.0:
		_hud_t = 0.1
		_draw_hud()


func _draw_hud() -> void:
	if game.state == "menu":
		_hud.text = ""
		return
	var mx := GameData.max_hp()
	var cells := 10
	var on := int(ceil(hp / mx * cells))
	var bar := ""
	for i in cells: bar += "|" if i < on else "."
	var lines := PackedStringArray()
	lines.append("HP %s %3d" % [bar, int(ceil(hp))])
	if barrier > 0: lines.append("BARRIER " + "+".repeat(barrier))
	lines.append("WAVE %-3d %s" % [game.wave, game.left_text()])
	lines.append("CR %-6d SCORE %s" % [GameData.credits, game.fmt(game.score)])
	if GameData.lvl("overclock") > 0:
		if overclock_t > 0.0: lines.append("OVERCLOCK ACTIVE")
		elif overclock_cd > 0.0: lines.append("OVERCLOCK %ds" % int(ceil(overclock_cd)))
		else: lines.append("OVERCLOCK READY · GRIP")
	var g: Gun = guns[0]
	lines.append("%s %s" % [GameData.WEAPONS[g.weapon_id].name.to_upper() if g.weapon_id != "" else "", "· B/Y SWAP" if GameData.owned.size() > 1 and vr else ""])
	_hud.text = "\n".join(lines)
	_hud.modulate = GameData.C_ALARM if hp <= 30.0 else GameData.C_PAPER
