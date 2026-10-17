class_name Gun
extends Node3D
## A hand-held weapon: real gun model, keyframed fire/reload animations, hitscan with pierce,
## laser sight, muzzle flash and an ammo readout on the frame.

signal fired(gun: Gun)

var controller: XRController3D  # null in desktop mode
var aim_node: Node3D            # whose -Z is the shot direction
var stats := {}
var weapon_id := ""
var mag := 0
var cooldown := 0.0
var reload_t := 0.0
var laser_enabled := true
var shots := 0
var hits := 0

var _holder: Node3D
var _model: Node3D
var _muzzle: Node3D
var _flash: Node3D
var _flash_t := 0.0
var _anim: AnimationPlayer
var _ammo: Label3D
var _laser: MeshInstance3D
var _dot: MeshInstance3D
var _ray_ex: Array[RID] = []

const FIRE_MASK := GameData.L_WORLD | GameData.L_DRONE | GameData.L_ORB | GameData.L_UI | GameData.L_PICKUP


func _ready() -> void:
	_holder = Node3D.new()
	_holder.name = "Holder"
	add_child(_holder)
	_anim = AnimationPlayer.new()
	add_child(_anim)
	_build_animations()

	_ammo = Label3D.new()
	_ammo.font = GameData.FONT_MONO
	_ammo.font_size = 48
	_ammo.pixel_size = 0.0009
	_ammo.outline_size = 8
	_ammo.modulate = GameData.C_PAPER
	_ammo.position = Vector3(0, 0.075, 0.07)
	_ammo.rotation.x = -0.6
	_holder.add_child(_ammo)

	var lm := FX.additive_material(Color(1.0, 0.25, 0.15, 0.35))
	_laser = MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.0035, 0.0035, 1.0)
	_laser.mesh = lb
	_laser.material_override = lm
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)
	_dot = MeshInstance3D.new()
	var ds := SphereMesh.new()
	ds.radius = 0.014
	ds.height = 0.028
	_dot.mesh = ds
	_dot.material_override = FX.additive_material(Color(1.0, 0.35, 0.25, 0.95))
	_dot.top_level = true
	_dot.visible = false
	add_child(_dot)


## Smaller ammo readout for the desktop view where the gun sits close to the camera.
func compact_ammo() -> void:
	_ammo.pixel_size = 0.00035
	_ammo.position = Vector3(0.0, 0.05, 0.08)


func set_weapon(id: String) -> void:
	weapon_id = id
	stats = GameData.weapon_stats(id)
	if _model: _model.queue_free()
	var w: Dictionary = GameData.WEAPONS[id]
	_model = (load(w.model) as PackedScene).instantiate()
	var s: float = w.scale
	_model.scale = Vector3.ONE * s
	_model.rotation.y = -PI / 2
	# put the grip on the hand: model +X becomes +Z after the turn
	_model.position = Vector3(0, -0.02, (0.0 - float(w.grip_x)) * s + 0.035)
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holder.add_child(_model)
	if _muzzle: _muzzle.queue_free()
	_muzzle = Node3D.new()
	var mz: Vector3 = w.muzzle
	_muzzle.position = _model.transform * mz
	_holder.add_child(_muzzle)
	_build_flash()
	mag = int(stats.mag)
	reload_t = 0.0
	cooldown = 0.0
	_update_ammo()


func refresh_stats() -> void:
	var old_max := int(stats.get("mag", 0))
	stats = GameData.weapon_stats(weapon_id)
	if int(stats.mag) > old_max: mag += int(stats.mag) - old_max
	_update_ammo()


func refill() -> void:
	mag = int(stats.mag)
	reload_t = 0.0
	_anim.stop()
	_holder.transform = Transform3D.IDENTITY
	_update_ammo()


func _build_flash() -> void:
	if _flash: _flash.queue_free()
	_flash = Node3D.new()
	var tex := FX.radial_texture([Color(1, 0.98, 0.88, 1), Color(1, 0.75, 0.35, 0.9), Color(1, 0.45, 0.1, 0)], [0.0, 0.3, 1.0])
	var mat := FX.additive_material(Color.WHITE, tex)
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.11, 0.11) if i == 0 else Vector2(0.07, 0.2)
		q.mesh = qm
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i == 1: q.rotation = Vector3(PI / 2, 0, PI / 2)
		if i == 2: q.rotation = Vector3(0, PI / 2, PI / 2)
		if i > 0: q.position.z = -0.06
		_flash.add_child(q)
	_flash.visible = false
	_muzzle.add_child(_flash)


## Keyframed recoil and reload animations on the holder node.
func _build_animations() -> void:
	var lib := AnimationLibrary.new()
	var fire := Animation.new()
	fire.length = 0.16
	var tr := fire.add_track(Animation.TYPE_POSITION_3D)
	fire.track_set_path(tr, NodePath("Holder"))
	fire.position_track_insert_key(tr, 0.0, Vector3.ZERO)
	fire.position_track_insert_key(tr, 0.03, Vector3(0, 0.008, 0.045))
	fire.position_track_insert_key(tr, 0.16, Vector3.ZERO)
	var rr := fire.add_track(Animation.TYPE_ROTATION_3D)
	fire.track_set_path(rr, NodePath("Holder"))
	fire.rotation_track_insert_key(rr, 0.0, Quaternion.IDENTITY)
	fire.rotation_track_insert_key(rr, 0.03, Quaternion(Vector3.RIGHT, 0.32))
	fire.rotation_track_insert_key(rr, 0.16, Quaternion.IDENTITY)
	lib.add_animation("fire", fire)

	var rel := Animation.new()
	rel.length = 1.0
	var p := rel.add_track(Animation.TYPE_POSITION_3D)
	rel.track_set_path(p, NodePath("Holder"))
	rel.position_track_insert_key(p, 0.0, Vector3.ZERO)
	rel.position_track_insert_key(p, 0.2, Vector3(0, -0.04, 0.03))
	rel.position_track_insert_key(p, 0.55, Vector3(0, -0.05, 0.03))
	rel.position_track_insert_key(p, 0.62, Vector3(0, -0.02, 0.02))
	rel.position_track_insert_key(p, 1.0, Vector3.ZERO)
	var r := rel.add_track(Animation.TYPE_ROTATION_3D)
	rel.track_set_path(r, NodePath("Holder"))
	rel.rotation_track_insert_key(r, 0.0, Quaternion.IDENTITY)
	rel.rotation_track_insert_key(r, 0.2, Quaternion.from_euler(Vector3(-0.9, 0.0, 0.7)))
	rel.rotation_track_insert_key(r, 0.55, Quaternion.from_euler(Vector3(-0.95, 0.0, 0.75)))
	rel.rotation_track_insert_key(r, 0.62, Quaternion.from_euler(Vector3(-0.7, 0.0, 0.4)))
	rel.rotation_track_insert_key(r, 1.0, Quaternion.IDENTITY)
	lib.add_animation("reload", rel)
	_anim.add_animation_library("", lib)


func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position


func aim_basis() -> Basis:
	return (aim_node if aim_node else self).global_transform.basis


func try_fire(held: bool) -> void:
	if cooldown > 0.0 or reload_t > 0.0: return
	if held and not bool(stats.auto) and weapon_id != "pistol": return
	if mag <= 0:
		if not held: Sfx.play("dry_fire", -4.0)
		reload()
		return
	mag -= 1
	cooldown = float(stats.rate) * (1.0 if bool(stats.auto) or not held else 1.6)
	shots += 1
	_anim.stop()
	_anim.play("fire", -1, 1.0)
	_flash.visible = true
	_flash.rotation.z = randf() * TAU
	_flash_t = 0.045
	Sfx.play(str(stats.sfx), -3.0 if weapon_id == "rifle" else 0.0)
	if float(stats.kick) > 1.5: FX.flash(muzzle_position(), Color(1, 0.75, 0.4), 1.2, 0.08)
	_haptic(0.45 + 0.15 * float(stats.kick), 0.05)
	_shoot_ray()
	_update_ammo()
	fired.emit(self)
	if mag == 0: reload()


func _shoot_ray() -> void:
	var b := aim_basis()
	var origin := (aim_node if aim_node else self).global_position
	var dir := -b.z
	var spread := float(stats.spread)
	if spread > 0.0:
		dir = (dir + b.x * randf_range(-spread, spread) + b.y * randf_range(-spread, spread)).normalized()
	var space := get_world_3d().direct_space_state
	var pierce := int(stats.pierce)
	var dmg := float(stats.damage)
	_ray_ex.clear()
	var end := origin + dir * 120.0
	var any_hit := false
	while pierce > 0:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0, FIRE_MASK, _ray_ex)
		var r := space.intersect_ray(q)
		if r.is_empty(): break
		var col: Object = r.collider
		var pt: Vector3 = r.position
		var nrm: Vector3 = r.normal
		end = pt
		if col.has_meta("drone"):
			if get_tree().paused: break
			var d: Node = col.get_meta("drone")
			var weak := bool(col.get_meta("weak", false))
			var amount := dmg * (float(stats.crit) if weak else 1.0)
			if d and d.has_method("take_damage") and d.take_damage(amount, weak, dir, pt):
				any_hit = true
			FX.sparks(pt, nrm, Color(1, 0.95, 0.8) if weak else Color(1, 0.65, 0.25), 16 if weak else 10)
			pierce -= 1
			_ray_ex.append((col as CollisionObject3D).get_rid())
			continue
		if col.has_meta("orb"):
			var orb: Dictionary = col.get_meta("orb")
			var proj: Node = col.get_meta("owner")
			if proj: proj.kill(orb, true)
			Sfx.play("hit", -6.0, 1.4)
			any_hit = true
			pierce -= 1
			_ray_ex.append((col as CollisionObject3D).get_rid())
			continue
		if col is Button3D:
			(col as Button3D).press()
			break
		if col.has_meta("pickup"):
			var pk: Node = col.get_meta("pickup")
			if pk and pk.has_method("collect"): pk.collect()
			break
		FX.sparks(pt, nrm, Color(0.85, 0.8, 0.7), 7)
		break
	if any_hit:
		hits += 1
		Sfx.play("hit", -4.0)
		_haptic(0.3, 0.03)
	FX.tracer(muzzle_position(), end)


func reload() -> void:
	if reload_t > 0.0 or mag >= int(stats.mag): return
	reload_t = float(stats.reload)
	_anim.stop()
	_anim.play("reload", -1, 1.0 / reload_t)
	Sfx.play("reload_out", -6.0)
	_update_ammo()


func _haptic(amp: float, dur: float) -> void:
	if controller: controller.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


func _update_ammo() -> void:
	if not _ammo: return
	if reload_t > 0.0:
		_ammo.text = "RLD"
		_ammo.modulate = GameData.C_HAZARD
	else:
		_ammo.text = "%02d" % mag
		_ammo.modulate = GameData.C_ALARM if mag <= max(2, int(stats.mag) / 5) else GameData.C_PAPER


## Called every frame by the player with the real (unscaled) delta.
func tick(delta: float, show_laser: bool) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			reload_t = 0.0
			mag = int(stats.mag)
			Sfx.play("reload_in", -6.0)
			_update_ammo()
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0: _flash.visible = false
	_update_laser(show_laser and laser_enabled and reload_t <= 0.0)


func _update_laser(show: bool) -> void:
	_laser.visible = show
	_dot.visible = false
	if not show: return
	var b := aim_basis()
	var origin := muzzle_position()
	var dir := -b.z
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0, FIRE_MASK)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var end := origin + dir * 60.0
	if not r.is_empty():
		end = r.position
		_dot.visible = true
		_dot.global_position = end
		if r.collider is Button3D: (r.collider as Button3D).hover()
	var len := origin.distance_to(end)
	_laser.global_transform = Transform3D(b, origin + dir * len * 0.5)
	_laser.scale = Vector3(1, 1, len)
