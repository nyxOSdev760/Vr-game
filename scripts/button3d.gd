class_name Button3D
extends StaticBody3D
## A floating holo-panel you shoot (or point at and pull the trigger) to press.

signal pressed

var size := Vector2(1.0, 0.5)
var enabled := true
var selected := false
var _hover := 0.0
var _flash := 0.0
var _bg_mat: StandardMaterial3D
var _edge_mat: StandardMaterial3D
var _title: Label3D
var _sub: Label3D
var _tag: Label3D
var _accent := GameData.C_HAZARD


func setup(p_size: Vector2, title: String, sub := "", accent := GameData.C_HAZARD) -> Button3D:
	size = p_size
	_accent = accent
	collision_layer = GameData.L_UI
	collision_mask = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.08)
	shape.shape = box
	add_child(shape)

	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	bg.mesh = q
	_bg_mat = StandardMaterial3D.new()
	_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bg_mat.albedo_color = Color(GameData.C_INK, 0.82)
	bg.material_override = _bg_mat
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bg)

	# accent strip along the top edge and a thin frame
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_edge_mat.albedo_color = accent
	for e in [[Vector2(size.x, 0.035), Vector2(0, size.y / 2 - 0.0175)],
			[Vector2(size.x, 0.008), Vector2(0, -size.y / 2 + 0.004)],
			[Vector2(0.008, size.y), Vector2(-size.x / 2 + 0.004, 0)],
			[Vector2(0.008, size.y), Vector2(size.x / 2 - 0.004, 0)]]:
		var m := MeshInstance3D.new()
		var eq := QuadMesh.new()
		eq.size = e[0]
		m.mesh = eq
		m.position = Vector3(e[1].x, e[1].y, 0.002)
		m.material_override = _edge_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)

	_title = _label(GameData.FONT_HEAD, 96, GameData.C_PAPER)
	_sub = _label(GameData.FONT_MONO, 40, GameData.C_MUTED)
	_tag = _label(GameData.FONT_MONO, 40, accent)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.width = size.x / _sub.pixel_size * 0.9
	set_text(title, sub)
	return self


func _label(font: Font, fsize: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.font = font
	l.font_size = fsize
	l.pixel_size = 0.0016
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.position.z = 0.006
	l.render_priority = 2
	add_child(l)
	return l


func set_text(title: String, sub := "", tag := "") -> void:
	_title.text = title
	_sub.text = sub
	_tag.text = tag
	var scale_k := clampf(size.y / 0.5, 0.5, 1.6)
	_title.pixel_size = 0.0016 * scale_k
	# shrink long titles so they never spill past the card edge
	var tw := _title.font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, _title.font_size).x * _title.pixel_size
	if tw > size.x * 0.9: _title.pixel_size *= size.x * 0.9 / tw
	_title.width = size.x / _title.pixel_size * 0.92
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	if sub == "" and tag == "":
		_title.position.y = 0.0
	else:
		_title.position.y = size.y * 0.22
	_sub.position.y = -size.y * 0.08
	_tag.position.y = -size.y * 0.36
	_sub.width = size.x / _sub.pixel_size * 0.9


func set_enabled(v: bool) -> void:
	enabled = v
	_refresh()


func set_selected(v: bool) -> void:
	selected = v
	_refresh()


func hover() -> void:
	_hover = 0.12


func press() -> void:
	if not enabled:
		Sfx.play("ui_error", -6.0)
		_flash = 0.15
		return
	_flash = 0.25
	Sfx.play("ui_select", -2.0)
	pressed.emit()


func _refresh() -> void:
	var a := 0.82
	var c := GameData.C_INK
	if selected: c = _accent.darkened(0.55)
	if not enabled: a = 0.5
	_bg_mat.albedo_color = Color(c, a)
	_edge_mat.albedo_color = _accent if enabled else GameData.C_MUTED.darkened(0.3)
	_title.modulate = GameData.C_PAPER if enabled else GameData.C_MUTED


func _process(delta: float) -> void:
	if _hover > 0.0 or _flash > 0.0:
		_hover = maxf(0.0, _hover - delta)
		_flash = maxf(0.0, _flash - delta)
		var base := _accent.darkened(0.55) if selected else GameData.C_INK
		var k := 0.25 if _hover > 0.0 else 0.0
		if _flash > 0.0: k = 0.6 * _flash / 0.25 + 0.25
		_bg_mat.albedo_color = Color(base.lerp(_accent if enabled else GameData.C_ALARM, k), 0.88)
		if _hover <= 0.0 and _flash <= 0.0: _refresh()
