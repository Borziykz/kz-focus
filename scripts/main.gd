extends Node3D

var player: KZPlayer
var timer_label: Label
var speed_label: Label
var message_label: Label
var help_label: Label
var records_label: Label
var jump_stats_label: Label
var checkpoint_label: Label
var ghost_status_label: Label
var pause_panel: ColorRect
var settings_box: VBoxContainer
var music_player: AudioStreamPlayer
var music_enabled := true
var run_started := false
var run_finished := false
var run_time := 0.0
var best_time := INF
var records: Array[float] = []
var tp_records: Array[float] = []
var message_serial := 0
var current_tps := 0
var ghost: MeshInstance3D
var ghost_positions: Array[Vector3] = []
var ghost_yaws: Array[float] = []
var current_positions: Array[Vector3] = []
var current_yaws: Array[float] = []
var ghost_cursor := 0
var ghost_best_time := INF
var menu_open := false

const WHITE := Color("#f4f5f3")
const DARK := Color("#32383d")
const GREEN := Color("#42c47a")
const ORANGE := Color("#ff8a3d")
const BLUE := Color("#43a6d9")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_actions()
	_build_environment()
	_build_training_complex()
	_build_course()
	_build_player()
	_build_ghost()
	_load_ghost()
	_load_records()
	_build_ui()
	_build_music()
	_load_settings()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause_menu"):
		_toggle_pause_menu()
	if menu_open:
		return
	if Input.is_action_just_pressed("toggle_music"):
		music_enabled = not music_enabled
		if music_enabled:
			music_player.play(0.0)
		else:
			music_player.stop()
		_show_message("МУЗЫКА: %s" % ("ВКЛ" if music_enabled else "ВЫКЛ"))
	if run_started and not run_finished:
		run_time += delta
		timer_label.text = _format_time(run_time)
	if player and player.global_position.z < -1.0 and not run_started:
		run_started = true
		run_finished = false
		run_time = 0.0
		current_tps = 0
		current_positions.clear()
		current_yaws.clear()
		ghost_cursor = 0
		ghost_status_label.text = "GHOST: %s" % ("ГОТОВ" if not ghost_positions.is_empty() else "ЗАПИСЬ")
		message_label.text = ""
	if player and player.global_position.z > 0.5 and (run_started or run_finished):
		_reset_run()

func _physics_process(_delta: float) -> void:
	if menu_open or not run_started or run_finished or player == null:
		return
	current_positions.append(player.global_position)
	current_yaws.append(player.rotation.y)
	if not ghost_positions.is_empty():
		var index := mini(ghost_cursor, ghost_positions.size() - 1)
		ghost.global_position = ghost_positions[index] + Vector3.UP * 0.86
		ghost.rotation.y = ghost_yaws[index]
		ghost.visible = true
		ghost_cursor += 1

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#d8dcde")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#cbd2d6")
	env.fog_light_energy = 0.65
	env.fog_density = 0.006
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

func _build_training_complex() -> void:
	# Large architectural shell. These meshes are decorative and have no collision.
	_add_decor_box(Vector3(0, -6.8, -68), Vector3(26, 0.4, 155), Color("#242b30"))
	_add_decor_box(Vector3(-12.0, 3.6, -68), Vector3(0.35, 14, 155), Color("#e5e8e8"))
	_add_decor_box(Vector3(12.0, 3.6, -68), Vector3(0.35, 14, 155), Color("#e5e8e8"))
	_add_decor_box(Vector3(0, 10.3, -68), Vector3(26, 0.35, 155), Color("#d9ddde"))

	# Structural beams and soft ceiling lights create rhythm along the route.
	for z in range(6, -151, -12):
		_add_decor_box(Vector3(0, 8.9, float(z)), Vector3(24.2, 0.28, 0.42), Color("#343b40"))
		_add_emissive_box(Vector3(0, 9.85, float(z) - 4.5), Vector3(7.0, 0.08, 2.4), Color("#eaf8ff"), 1.5)
		_add_decor_box(Vector3(-11.65, 3.2, float(z)), Vector3(0.42, 10.8, 0.55), Color("#343b40"))
		_add_decor_box(Vector3(11.65, 3.2, float(z)), Vector3(0.42, 10.8, 0.55), Color("#343b40"))

	# Zone navigation strips on both walls.
	_add_zone_lighting(-7.0, 13.0, GREEN)
	_add_zone_lighting(-31.0, 23.0, BLUE)
	_add_zone_lighting(-58.0, 24.0, Color("#c8d2d8"))
	_add_zone_lighting(-85.0, 23.0, Color("#9a78dc"))
	_add_zone_lighting(-120.0, 33.0, Color("#f1cf56"))
	_add_zone_lighting(-139.0, 6.0, ORANGE)

	# Glass safety panels around the start and rest platforms.
	_add_glass_panel(Vector3(-3.05, 1.2, 3.5), Vector3(0.08, 2.4, 5.0))
	_add_glass_panel(Vector3(3.05, 1.2, 3.5), Vector3(0.08, 2.4, 5.0))
	_add_glass_panel(Vector3(-2.55, 1.0, -42.2), Vector3(0.08, 2.0, 3.0))
	_add_glass_panel(Vector3(2.55, 1.0, -42.2), Vector3(0.08, 2.0, 3.0))
	_add_glass_panel(Vector3(-2.3, 1.0, -99.0), Vector3(0.08, 2.0, 2.8))
	_add_glass_panel(Vector3(2.3, 1.0, -99.0), Vector3(0.08, 2.0, 2.8))

	# Entrance and finish gates.
	_add_gate(Vector3(0, 0, 0.8), GREEN, "KZ // FOCUS")
	_add_gate(Vector3(0, 0, -136.5), ORANGE, "FINISH")
	_add_wall_screen(Vector3(-11.75, 3.6, -18.0), 90.0, "MOVEMENT LAB\nAIR • SPEED • PRECISION", BLUE)
	_add_wall_screen(Vector3(11.75, 3.6, -101.0), -90.0, "KEEP MOMENTUM\nSTAY FOCUSED", Color("#f1cf56"))

func _add_decor_box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	mesh.material = material
	instance.mesh = mesh
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	return instance

func _add_emissive_box(pos: Vector3, size: Vector3, color: Color, energy: float) -> void:
	var instance := _add_decor_box(pos, size, color)
	var material := instance.mesh.material as StandardMaterial3D
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _add_zone_lighting(z: float, length: float, color: Color) -> void:
	_add_emissive_box(Vector3(-11.78, 0.15, z), Vector3(0.08, 0.12, length), color, 2.2)
	_add_emissive_box(Vector3(11.78, 0.15, z), Vector3(0.08, 0.12, length), color, 2.2)

func _add_glass_panel(pos: Vector3, size: Vector3) -> void:
	var instance := _add_decor_box(pos, size, Color(0.50, 0.78, 0.90, 0.18))
	var material := instance.mesh.material as StandardMaterial3D
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.metallic = 0.15
	material.roughness = 0.1
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _add_gate(pos: Vector3, color: Color, text: String) -> void:
	_add_decor_box(pos + Vector3(-4.2, 3.0, 0), Vector3(0.45, 6.0, 0.6), Color("#30373c"))
	_add_decor_box(pos + Vector3(4.2, 3.0, 0), Vector3(0.45, 6.0, 0.6), Color("#30373c"))
	_add_decor_box(pos + Vector3(0, 5.8, 0), Vector3(8.8, 0.45, 0.6), Color("#30373c"))
	_add_emissive_box(pos + Vector3(0, 5.45, -0.32), Vector3(7.8, 0.10, 0.08), color, 3.0)
	var label := Label3D.new()
	label.text = text
	label.font_size = 54
	label.modulate = color
	label.outline_size = 7
	label.outline_modulate = Color("#20262a")
	label.position = pos + Vector3(0, 6.35, 0)
	add_child(label)

func _add_wall_screen(pos: Vector3, yaw: float, text: String, accent: Color) -> void:
	var screen := _add_decor_box(pos, Vector3(4.8, 2.3, 0.12), Color("#182026"))
	screen.rotation_degrees.y = yaw
	var label := Label3D.new()
	label.text = text
	label.font_size = 34
	label.modulate = accent
	label.outline_size = 5
	label.outline_modulate = Color("#101416")
	label.position = pos + Vector3(0.0, 0.0, 0.10 if yaw > 0 else -0.10)
	label.rotation_degrees.y = yaw
	add_child(label)

func _build_player() -> void:
	player = KZPlayer.new()
	player.position = Vector3(0, 0.35, 3.5)
	player.set_spawn(player.position, 0.0)
	player.speed_changed.connect(_on_speed_changed)
	player.landed.connect(_on_landed)
	player.status_message.connect(_show_message)
	player.jumped.connect(func(): _play_tone(520.0, 0.055, -22.0))
	player.teleported.connect(_on_teleported)
	player.checkpoint_changed.connect(_on_checkpoint_changed)
	player.attack_started.connect(func(): _play_tone(170.0, 0.09, -18.0))
	add_child(player)

func _build_ghost() -> void:
	ghost = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.32
	mesh.height = 1.72
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.68, 0.95, 0.58)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.12, 0.65, 1.0)
	material.emission_energy_multiplier = 1.8
	mesh.material = material
	ghost.mesh = mesh
	ghost.position.y = 0.86
	ghost.visible = false
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ghost)
	var head_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.24
	sphere.height = 0.48
	sphere.material = material
	head_mesh.mesh = sphere
	head_mesh.position = Vector3(0, 0.78, 0)
	head_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(head_mesh)

func _build_course() -> void:
	# ZONE 1 — warm-up.
	_add_block(Vector3(0, -0.25, 3.5), Vector3(6, 0.5, 5), GREEN, "START")
	_add_zone_sign(Vector3(0, 2.8, -0.5), "РАЗМИНКА")
	_add_block(Vector3(0, 0.0, -3.0), Vector3(3.2, 0.5, 2.4), WHITE, "180")
	_add_block(Vector3(2.4, 0.25, -7.0), Vector3(2.6, 0.5, 2.0), WHITE, "200")
	_add_block(Vector3(-0.6, 0.55, -11.0), Vector3(2.2, 0.5, 1.8), WHITE, "220")
	_add_block(Vector3(-3.0, 0.2, -15.2), Vector3(2.0, 0.5, 1.8), WHITE, "230")

	# ZONE 2 — long jumps with increasing gaps.
	_add_zone_sign(Vector3(0, 3.2, -19.0), "LONGJUMP")
	_add_block(Vector3(0, 0.0, -20.0), Vector3(4.0, 0.5, 3.0), BLUE, "230")
	_add_block(Vector3(0, 0.0, -25.5), Vector3(3.5, 0.5, 2.2), BLUE, "240")
	_add_block(Vector3(2.0, 0.15, -31.1), Vector3(3.0, 0.5, 2.0), BLUE, "250")
	_add_block(Vector3(-1.6, 0.3, -36.8), Vector3(2.8, 0.5, 1.9), BLUE, "260")
	_add_block(Vector3(0, 0.0, -42.2), Vector3(5.0, 0.5, 3.0), BLUE, "SAFE")

	# ZONE 3 — precision on small offset blocks.
	_add_zone_sign(Vector3(0, 3.0, -47.0), "ТОЧНОСТЬ")
	var precision := [
		[Vector3(-2.0, 0.1, -49.0), Vector3(1.25, 0.45, 1.25)],
		[Vector3(0.4, 0.55, -52.0), Vector3(1.05, 0.45, 1.05)],
		[Vector3(2.7, 0.0, -55.0), Vector3(0.95, 0.45, 0.95)],
		[Vector3(0.5, 0.8, -58.0), Vector3(0.9, 0.45, 0.9)],
		[Vector3(-2.1, 0.25, -61.0), Vector3(0.85, 0.45, 0.85)],
		[Vector3(-0.2, 1.0, -64.0), Vector3(0.8, 0.45, 0.8)],
		[Vector3(2.3, 0.4, -67.0), Vector3(0.75, 0.45, 0.75)],
		[Vector3(0.0, 0.0, -70.8), Vector3(4.5, 0.5, 2.5)]
	]
	for item in precision:
		_add_block(item[0], item[1], WHITE, "")

	# ZONE 4 — height changes and crouch landings.
	_add_zone_sign(Vector3(0, 3.7, -75.0), "ВЫСОТА")
	_add_block(Vector3(-2.2, 0.6, -77.0), Vector3(2.2, 0.5, 1.8), Color("#d9dce0"), "+")
	_add_block(Vector3(0.8, 1.25, -81.0), Vector3(2.0, 0.5, 1.7), Color("#d9dce0"), "+")
	_add_block(Vector3(3.0, 2.0, -85.0), Vector3(1.8, 0.5, 1.6), Color("#d9dce0"), "+")
	_add_block(Vector3(0.0, 0.6, -89.5), Vector3(2.0, 0.5, 1.7), Color("#bfc5ca"), "DROP")
	_add_block(Vector3(-3.0, 1.5, -94.0), Vector3(1.7, 0.5, 1.5), Color("#d9dce0"), "+")
	_add_block(Vector3(0.0, -0.2, -99.0), Vector3(4.5, 0.5, 2.8), Color("#bfc5ca"), "SAFE")

	# ZONE 5 — long bhop chain.
	_add_zone_sign(Vector3(0, 3.0, -104.0), "BHOP")
	var bhops := [
		Vector3(-2.5, 0.05, -106.0), Vector3(0.0, 0.05, -109.0),
		Vector3(2.4, 0.05, -112.0), Vector3(3.2, 0.05, -115.0),
		Vector3(0.5, 0.05, -118.0), Vector3(-2.2, 0.05, -121.0),
		Vector3(-3.0, 0.05, -124.0), Vector3(-0.4, 0.05, -127.0),
		Vector3(2.3, 0.05, -130.0), Vector3(0.0, 0.05, -133.0)
	]
	for i in bhops.size():
		var block_size := 1.35 - float(i) * 0.035
		_add_block(bhops[i], Vector3(block_size, 0.45, block_size), Color("#f1cf56"), "")
	_add_block(Vector3(0.0, 0.0, -139.0), Vector3(5.0, 0.5, 4.0), ORANGE, "FINISH")
	var finish := Area3D.new()
	finish.position = Vector3(0, 1.0, -139.0)
	var finish_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 2.2, 4.0)
	finish_shape.shape = box
	finish.add_child(finish_shape)
	finish.body_entered.connect(_on_finish_entered)
	add_child(finish)

func _add_block(pos: Vector3, size: Vector3, color: Color, text: String) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	mesh.material = mat
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mesh_instance)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	if text != "":
		var label := Label3D.new()
		label.text = text
		label.font_size = 38
		label.modulate = DARK
		label.position = pos + Vector3(0, size.y * 0.5 + 0.015, 0)
		label.rotation_degrees = Vector3(-90, 0, 0)
		label.outline_size = 4
		label.outline_modulate = Color(1, 1, 1, 0.65)
		add_child(label)

func _add_zone_sign(pos: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 72
	label.modulate = DARK
	label.outline_size = 8
	label.outline_modulate = Color(1, 1, 1, 0.75)
	label.position = pos
	add_child(label)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	timer_label = _label(Vector2(24, 20), 30, "00:00.000")
	layer.add_child(timer_label)
	speed_label = _label(Vector2(24, 58), 18, "0 u/s")
	layer.add_child(speed_label)
	message_label = _label(Vector2.ZERO, 24, "")
	message_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	message_label.position = Vector2(-230, 28)
	message_label.size = Vector2(460, 60)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(message_label)
	help_label = _label(Vector2(24, -74), 16, "WASD  движение   КОЛЕСО/SPACE  прыжок   ЛКМ  атака   F  нож-бабочка   Q/E  checkpoint   M  музыка")
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	layer.add_child(help_label)
	var cross := _label(Vector2.ZERO, 22, "+")
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-7, -15)
	layer.add_child(cross)
	records_label = _label(Vector2(-285, 20), 17, "")
	records_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	records_label.size = Vector2(260, 230)
	records_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(records_label)
	_refresh_records_label()
	jump_stats_label = _label(Vector2(24, 92), 17, "ПОСЛЕДНИЙ ПРЫЖОК\n—")
	layer.add_child(jump_stats_label)
	checkpoint_label = _label(Vector2(-285, 255), 16, "PRO • CP 0/0 • TP 0")
	checkpoint_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	checkpoint_label.size = Vector2(260, 40)
	checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(checkpoint_label)
	ghost_status_label = _label(Vector2(-285, 290), 16, "GHOST: %s" % ("ГОТОВ" if not ghost_positions.is_empty() else "НЕТ ЗАПИСИ"))
	ghost_status_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ghost_status_label.size = Vector2(260, 35)
	ghost_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ghost_status_label.add_theme_color_override("font_color", BLUE)
	layer.add_child(ghost_status_label)
	_build_pause_menu(layer)

func _label(pos: Vector2, size: int, value: String) -> Label:
	var label := Label.new()
	label.position = pos
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", DARK)
	label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _build_pause_menu(layer: CanvasLayer) -> void:
	pause_panel = ColorRect.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.color = Color(0.08, 0.10, 0.12, 0.88)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(pause_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-190, -250)
	box.size = Vector2(380, 500)
	box.add_theme_constant_override("separation", 12)
	pause_panel.add_child(box)
	var title := _label(Vector2.ZERO, 34, "KZ // FOCUS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "ПРОДОЛЖИТЬ"
	resume.custom_minimum_size = Vector2(380, 46)
	resume.pressed.connect(_toggle_pause_menu)
	box.add_child(resume)
	var restart := Button.new()
	restart.text = "НАЧАТЬ ЗАНОВО"
	restart.custom_minimum_size = Vector2(380, 42)
	restart.pressed.connect(func():
		player.respawn()
		_reset_run()
		_toggle_pause_menu()
	)
	box.add_child(restart)
	settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 5)
	box.add_child(settings_box)
	_add_setting_slider("Чувствительность", 0.5, 4.0, player.mouse_sensitivity * 1000.0, 0.1, func(v: float):
		player.mouse_sensitivity = v / 1000.0
		_save_settings()
	)
	_add_setting_slider("FOV", 60.0, 100.0, player.camera.fov, 1.0, func(v: float):
		player.camera.fov = v
		_save_settings()
	)
	_add_setting_slider("Громкость музыки", -30.0, 0.0, -11.0, 1.0, func(v: float):
		if music_player: music_player.volume_db = v
		_save_settings()
	)
	var exit_button := Button.new()
	exit_button.text = "ВЫХОД"
	exit_button.custom_minimum_size = Vector2(380, 42)
	exit_button.pressed.connect(func(): get_tree().quit())
	box.add_child(exit_button)
	var hint := _label(Vector2.ZERO, 15, "ESC — закрыть меню")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

func _add_setting_slider(title: String, minimum: float, maximum: float, value: float, step: float, callback: Callable) -> void:
	var label := _label(Vector2.ZERO, 16, "%s: %.1f" % [title, value])
	settings_box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(380, 28)
	slider.value_changed.connect(func(v: float):
		label.text = "%s: %.1f" % [title, v]
		callback.call(v)
	)
	settings_box.add_child(slider)

func _toggle_pause_menu() -> void:
	menu_open = not menu_open
	pause_panel.visible = menu_open
	get_tree().paused = menu_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED

func _save_settings() -> void:
	if player == null:
		return
	var config := ConfigFile.new()
	config.set_value("settings", "sensitivity", player.mouse_sensitivity)
	config.set_value("settings", "fov", player.camera.fov)
	if music_player:
		config.set_value("settings", "music_db", music_player.volume_db)
	config.save("user://settings.cfg")

func _build_music() -> void:
	music_player = AudioStreamPlayer.new()
	var music := load("res://audio/background_music.mp3") as AudioStreamMP3
	if music == null:
		push_warning("Не удалось загрузить фоновую музыку")
		return
	music.loop = true
	music_player.stream = music
	music_player.volume_db = -11.0
	add_child(music_player)
	music_player.play()

func _on_speed_changed(speed: float, pre: float) -> void:
	# 1 Godot metre is presented as 32 familiar KZ units.
	speed_label.text = "%d u/s   PRE %d" % [roundi(speed * 32.0), roundi(pre * 32.0)]

func _on_landed(distance: float, pre: float, max_speed: float, strafes: int, sync: float) -> void:
	jump_stats_label.text = "ПОСЛЕДНИЙ ПРЫЖОК\n%.1f u  •  PRE %d\nMAX %d  •  STRAFE %d  •  SYNC %.0f%%" % [distance * 32.0, roundi(pre * 32.0), roundi(max_speed * 32.0), strafes, sync]
	_play_tone(260.0 if distance < 5.0 else 340.0, 0.045, -25.0)
	if distance > 2.5:
		message_label.text = "%.1f u   PRE %d   MAX %d   %d STR   %.0f%% SYNC" % [distance * 32.0, roundi(pre * 32.0), roundi(max_speed * 32.0), strafes, sync]
		get_tree().create_timer(1.8).timeout.connect(func():
			if not run_finished: message_label.text = ""
		)

func _on_finish_entered(body: Node3D) -> void:
	if body != player or not run_started or run_finished:
		return
	run_finished = true
	var is_personal_best := run_time < ghost_best_time
	best_time = min(best_time, run_time)
	_add_record(run_time, current_tps > 0)
	if is_personal_best or ghost_positions.is_empty():
		ghost_positions = current_positions.duplicate()
		ghost_yaws = current_yaws.duplicate()
		ghost_best_time = run_time
		_save_ghost()
		ghost_status_label.text = "GHOST: СОХРАНЁН • R ДЛЯ ГОНКИ"
	message_label.text = "ФИНИШ  %s   •   %s   •   TP %d" % [_format_time(run_time), "НОВЫЙ PB" if is_personal_best else "ЗАВЕРШЕНО", current_tps]
	_play_tone(660.0, 0.22, -15.0)

func _reset_run() -> void:
	run_started = false
	run_finished = false
	run_time = 0.0
	current_tps = 0
	ghost_cursor = 0
	current_positions.clear()
	current_yaws.clear()
	timer_label.text = _format_time(0.0)
	ghost.visible = false
	checkpoint_label.text = "PRO • CP 0/0 • TP 0"
	var ghost_text := "НЕТ ЗАПИСИ"
	if not ghost_positions.is_empty():
		ghost_text = "ГОТОВ"
		if ghost_best_time != INF:
			ghost_text += " • %s" % _format_time(ghost_best_time)
	ghost_status_label.text = "GHOST: %s" % ghost_text

func _format_time(value: float) -> String:
	var minutes := int(value) / 60
	var seconds := int(value) % 60
	var millis := int(fmod(value, 1.0) * 1000.0)
	return "%02d:%02d.%03d" % [minutes, seconds, millis]

func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("crouch", KEY_SHIFT)
	_add_key_action("crouch", KEY_C)
	_add_key_action("restart", KEY_R)
	_add_key_action("release_mouse", KEY_ESCAPE)
	_add_key_action("pause_menu", KEY_ESCAPE)
	_add_key_action("set_checkpoint", KEY_Q)
	_add_key_action("go_checkpoint", KEY_E)
	_add_key_action("toggle_music", KEY_M)
	_add_key_action("inspect_knife", KEY_F)
	_add_key_action("prev_checkpoint", KEY_Z)
	_add_key_action("next_checkpoint", KEY_X)
	_add_key_action("toggle_noclip", KEY_N)
	if not InputMap.has_action("attack_knife"):
		InputMap.add_action("attack_knife")
	var attack_click := InputEventMouseButton.new()
	attack_click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack_knife", attack_click)
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	InputMap.action_add_event("jump", wheel_down)
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	InputMap.action_add_event("jump", wheel_up)

func _add_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)

func _show_message(text: String) -> void:
	message_serial += 1
	var serial := message_serial
	message_label.text = text
	get_tree().create_timer(1.8).timeout.connect(func():
		if serial == message_serial and not run_finished:
			message_label.text = ""
	)

func _on_teleported(count: int) -> void:
	current_tps = count
	checkpoint_label.text = "TP RUN • TP %d" % current_tps
	_play_tone(210.0, 0.08, -20.0)

func _on_checkpoint_changed(index: int, total: int) -> void:
	checkpoint_label.text = "%s • CP %d/%d • TP %d" % ["PRO" if current_tps == 0 else "TP RUN", index, total, current_tps]
	_play_tone(440.0, 0.07, -20.0)

func _play_tone(frequency: float, duration: float, volume_db: float) -> void:
	var rate := 22050
	var sample_count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	for i in sample_count:
		var fade := 1.0 - float(i) / float(sample_count)
		var sample := sin(TAU * frequency * float(i) / float(rate)) * fade * 0.35
		bytes.encode_s16(i * 2, int(sample * 32767.0))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = rate
	wave.stereo = false
	wave.data = bytes
	var sound := AudioStreamPlayer.new()
	sound.stream = wave
	sound.volume_db = volume_db
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func _save_ghost() -> void:
	var file := FileAccess.open("user://best_ghost.save", FileAccess.WRITE)
	if file:
		file.store_var(ghost_positions)
		file.store_var(ghost_yaws)
		file.store_var(ghost_best_time)

func _load_ghost() -> void:
	if not FileAccess.file_exists("user://best_ghost.save"):
		return
	var file := FileAccess.open("user://best_ghost.save", FileAccess.READ)
	if file:
		var positions: Variant = file.get_var()
		var yaws: Variant = file.get_var()
		if positions is Array and yaws is Array:
			for value in positions:
				ghost_positions.append(value)
			for value in yaws:
				ghost_yaws.append(float(value))
			if file.get_position() < file.get_length():
				var stored_time: Variant = file.get_var()
				if stored_time is float or stored_time is int:
					ghost_best_time = float(stored_time)
	if not ghost_positions.is_empty() and ghost_status_label:
		ghost_status_label.text = "GHOST: ГОТОВ"

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return
	player.mouse_sensitivity = float(config.get_value("settings", "sensitivity", player.mouse_sensitivity))
	player.camera.fov = float(config.get_value("settings", "fov", player.camera.fov))
	music_player.volume_db = float(config.get_value("settings", "music_db", music_player.volume_db))

func _load_records() -> void:
	var config := ConfigFile.new()
	if config.load("user://records.cfg") != OK:
		return
	var stored: Array = config.get_value("records", "pro_times", config.get_value("records", "times", []))
	for value in stored:
		records.append(float(value))
	var stored_tp: Array = config.get_value("records", "tp_times", [])
	for value in stored_tp:
		tp_records.append(float(value))
	records.sort()
	tp_records.sort()
	if not records.is_empty():
		best_time = records[0]

func _add_record(value: float, is_tp: bool) -> void:
	var target: Array[float] = tp_records if is_tp else records
	target.append(value)
	target.sort()
	if target.size() > 10:
		target.resize(10)
	var config := ConfigFile.new()
	config.set_value("records", "pro_times", records)
	config.set_value("records", "tp_times", tp_records)
	config.save("user://records.cfg")
	_refresh_records_label()

func _refresh_records_label() -> void:
	if records_label == null:
		return
	var text := "ЛУЧШИЕ ЗАБЕГИ\nPRO\n"
	if records.is_empty():
		text += "—\n"
	else:
		for i in mini(records.size(), 3):
			text += "%d.  %s\n" % [i + 1, _format_time(records[i])]
	text += "TP\n"
	if tp_records.is_empty():
		text += "—"
	else:
		for i in mini(tp_records.size(), 3):
			text += "%d.  %s\n" % [i + 1, _format_time(tp_records[i])]
	records_label.text = text

