class_name Pickup
extends StaticBody3D
## Salvage dropped by drones. Walk into it, touch it with a gun, or shoot it to collect.

const KINDS := {
	"health": {"model": "res://assets/pickups/pickup_health.glb", "scale": 0.32, "color": Color(0.49, 0.88, 0.63)},
	"credits": {"model": "res://assets/pickups/pickup_bullets.glb", "scale": 0.3, "color": Color(1.0, 0.79, 0.24)},
	"overclock": {"model": "res://assets/pickups/pickup_thunder.glb", "scale": 0.3, "color": Color(0.5, 0.8, 1.0)},
}

var kind := "health"
var game: Node
var life := 16.0
var _t := 0.0
var _model: Node3D
var _base_y := 1.0
var _taken := false


func setup(p_kind: String, p_game: Node, pos: Vector3) -> void:
	kind = p_kind
	game = p_game
	collision_layer = GameData.L_PICKUP
	collision_mask = 0
	set_meta("pickup", self)
	var k: Dictionary = KINDS[kind]
	_model = (load(k.model) as PackedScene).instantiate()
	_model.scale = Vector3.ONE * float(k.scale)
	add_child(_model)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.28
	cs.shape = sh
	add_child(cs)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9)
	halo.mesh = q
	var hm := FX.additive_material(Color(k.color, 0.35), FX.glow_tex)
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	_base_y = clampf(pos.y, 0.9, 1.4)
	position = Vector3(pos.x, _base_y, pos.z)
	_t = randf() * 5.0


func collect() -> void:
	if _taken: return
	_taken = true
	game.on_pickup(kind)
	FX.sparks(global_position, Vector3.UP, KINDS[kind].color, 18)
	FX.ring(global_position, KINDS[kind].color, 0.8, 0.4)
	Sfx.play("pickup", -2.0)
	queue_free()


func _physics_process(delta: float) -> void:
	if _taken: return
	_t += delta
	life -= delta
	_model.rotation.y += delta * 2.0
	visible = life > 3.0 or fmod(_t, 0.2) < 0.12
	if life <= 0.0:
		queue_free()
		return
	var p: Node = game.player
	if not p.alive: return
	var r := GameData.magnet_radius()
	var targets: Array[Vector3] = [p.head_position() - Vector3(0, 0.5, 0)]
	for g in p.guns:
		if (g as Gun).is_visible_in_tree(): targets.append((g as Gun).global_position)
	var best := INF
	var best_p := Vector3.ZERO
	for tp in targets:
		var d := global_position.distance_to(tp)
		if d < best:
			best = d
			best_p = tp
	if best < 0.45:
		collect()
	elif best < r:
		global_position = global_position.move_toward(best_p, delta * (2.0 + 6.0 * (1.0 - best / r)))
	else:
		global_position.y = _base_y + sin(_t * 3.0) * 0.08
