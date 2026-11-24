class_name KZPlayer
extends CharacterBody3D

signal speed_changed(horizontal_speed: float, pre_speed: float)
signal landed(jump_distance: float, pre_speed: float, max_speed: float, strafes: int, sync: float)
signal fell
signal status_message(text: String)
signal jumped
signal teleported(count: int)
signal checkpoint_changed(index: int, total: int)
signal attack_started

@export var mouse_sensitivity := 0.0018
@export var ground_accel := 11.0
@export var air_accel := 100.0
@export var max_ground_speed := 7.8
@export var air_wish_speed := 0.95
@export var friction := 5.2
@export var stop_speed := 2.5
@export var jump_speed := 5.25
@export var gravity := 15.5

var spawn_position := Vector3.ZERO
var spawn_yaw := 0.0
var pre_speed := 0.0
var max_jump_speed := 0.0
var jump_origin := Vector3.ZERO
var was_on_floor := false
var jump_queued := false
var crouched := false
var standing_height := 1.72
var crouched_height := 1.18
var checkpoint_positions: Array[Vector3] = []
var checkpoint_yaws: Array[float] = []
var checkpoint_pitches: Array[float] = []
var checkpoint_index := -1
var teleport_count := 0
var noclip_enabled := false
var jump_strafes := 0
var sync_samples := 0
var sync_good := 0
var last_strafe_direction := 0
var mouse_x_since_tick := 0.0

var head: Node3D
var camera: Camera3D
var collider: CollisionShape3D
var knife_root: Node3D
var viewmodel_time := 0.0
var butterfly_left: Node3D
var butterfly_right: Node3D
var inspect_time := 0.0
var inspecting := false
const INSPECT_DURATION := 1.35
var attack_time := 0.0
var attacking := false
const ATTACK_DURATION := 0.42

func _ready() -> void:
	_build_body()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spawn_position = global_position
	spawn_yaw = rotation.y

func _build_body() -> void:
	collider = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = standing_height
	collider.shape = capsule
	collider.position.y = standing_height * 0.5
	add_child(collider)
	head = Node3D.new()
	head.position.y = 1.55
	add_child(head)
	camera = Camera3D.new()
	camera.current = true
	# Counter-Strike uses a 90-degree horizontal baseline at 4:3.
	# In Godot's vertical-FOV camera this is approximately 74 degrees,
	# producing about 106 horizontal degrees on a 16:9 display.
	camera.fov = 74.0
	head.add_child(camera)
	_build_knife()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_x_since_tick += event.relative.x
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x - event.relative.y * mouse_sensitivity, -1.52, 1.52)
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			jump_queued = true
	if event.is_action_pressed("restart"):
		respawn()
	if event.is_action_pressed("set_checkpoint"):
		set_checkpoint()
	if event.is_action_pressed("go_checkpoint"):
		go_checkpoint()
	if event.is_action_pressed("prev_checkpoint"):
		change_checkpoint(-1)
	if event.is_action_pressed("next_checkpoint"):
		change_checkpoint(1)
	if event.is_action_pressed("toggle_noclip"):
		toggle_noclip()
	if event.is_action_pressed("inspect_knife") and not inspecting:
		if not attacking:
			inspecting = true
			inspect_time = 0.0
	if event.is_action_pressed("attack_knife") and not attacking:
		if not inspecting:
			attacking = true
			attack_time = 0.0
			attack_started.emit()

func _physics_process(delta: float) -> void:
	if noclip_enabled:
		_noclip_move(delta)
		_update_viewmodel(delta, false)
		speed_changed.emit(Vector2(velocity.x, velocity.z).length(), pre_speed)
		return
	var on_floor := is_on_floor()
	if Input.is_action_just_pressed("jump"):
		jump_queued = true
	_set_crouch(Input.is_action_pressed("crouch"))
	var input2 := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input2.x, 0.0, input2.y)).normalized()
	if on_floor:
		_apply_friction(delta)
		_accelerate(wish_dir, max_ground_speed, ground_accel, delta)
		if jump_queued:
			pre_speed = Vector2(velocity.x, velocity.z).length()
			velocity.y = jump_speed
			jump_origin = global_position
			max_jump_speed = pre_speed
			jump_strafes = 0
			sync_samples = 0
			sync_good = 0
			last_strafe_direction = 0
			jump_queued = false
			jumped.emit()
	else:
		velocity.y -= gravity * delta
		_accelerate(wish_dir, air_wish_speed, air_accel, delta)
		max_jump_speed = max(max_jump_speed, Vector2(velocity.x, velocity.z).length())
		_update_strafe_stats(input2.x)
	move_and_slide()
	var now_floor := is_on_floor()
	if now_floor and not was_on_floor and jump_origin != Vector3.ZERO:
		var flat_delta := Vector2(global_position.x - jump_origin.x, global_position.z - jump_origin.z).length()
		var sync := 0.0 if sync_samples == 0 else float(sync_good) / float(sync_samples) * 100.0
		landed.emit(flat_delta, pre_speed, max_jump_speed, jump_strafes, sync)
		jump_origin = Vector3.ZERO
	was_on_floor = now_floor
	if now_floor:
		jump_queued = false
	if global_position.y < -8.0:
		fell.emit()
		respawn()
	speed_changed.emit(Vector2(velocity.x, velocity.z).length(), pre_speed)
	_update_viewmodel(delta, now_floor)
	mouse_x_since_tick = 0.0

func _update_strafe_stats(strafe_input: float) -> void:
	var direction := 0
	if strafe_input > 0.1:
		direction = 1
	elif strafe_input < -0.1:
		direction = -1
	if direction != 0:
		sync_samples += 1
		if mouse_x_since_tick * float(direction) > 0.0:
			sync_good += 1
		if last_strafe_direction != 0 and direction != last_strafe_direction:
			jump_strafes += 1
		last_strafe_direction = direction

func _noclip_move(delta: float) -> void:
	var input2 := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := camera.global_basis * Vector3(input2.x, 0.0, input2.y)
	if Input.is_action_pressed("jump"):
		direction += Vector3.UP
	if Input.is_action_pressed("crouch"):
		direction -= Vector3.UP
	var noclip_speed := 12.0
	velocity = direction.normalized() * noclip_speed if direction.length() > 0.01 else Vector3.ZERO
	global_position += velocity * delta
	mouse_x_since_tick = 0.0

func _build_knife() -> void:
	knife_root = Node3D.new()
	knife_root.position = Vector3(0.52, -0.46, -0.78)
	knife_root.rotation_degrees = Vector3(-18, 162, -14)
	camera.add_child(knife_root)

	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color("#241b19")
	handle_mat.metallic = 0.28
	handle_mat.roughness = 0.5
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = Color("#e5222b")
	accent_mat.metallic = 0.62
	accent_mat.roughness = 0.25
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color("#ef202b")
	blade_mat.metallic = 0.72
	blade_mat.roughness = 0.2
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color("#08090a")
	dark_mat.metallic = 0.4
	dark_mat.roughness = 0.38
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color("#b8c0c5")
	steel_mat.metallic = 0.92
	steel_mat.roughness = 0.16
	var wood_inlay_mat := StandardMaterial3D.new()
	wood_inlay_mat.albedo_color = Color("#4a3029")
	wood_inlay_mat.metallic = 0.08
	wood_inlay_mat.roughness = 0.72

	# A real extruded silhouette gives the blade a curved spine and hooked tip.
	var blade_shape := PackedVector2Array([
		Vector2(-0.13, 0.09), Vector2(-0.17, 0.32), Vector2(-0.15, 0.55),
		Vector2(-0.09, 0.76), Vector2(0.00, 0.96), Vector2(0.15, 1.16),
		Vector2(0.25, 1.24), Vector2(0.22, 1.08), Vector2(0.15, 0.87),
		Vector2(0.11, 0.64), Vector2(0.10, 0.39), Vector2(0.13, 0.09)
	])
	_add_extruded_part(knife_root, blade_shape, 0.048, blade_mat, Vector3.ZERO)
	var spine_shape := PackedVector2Array([
		Vector2(-0.14, 0.10), Vector2(-0.18, 0.33), Vector2(-0.16, 0.56),
		Vector2(-0.10, 0.77), Vector2(-0.055, 0.75), Vector2(-0.10, 0.53),
		Vector2(-0.115, 0.31), Vector2(-0.09, 0.10)
	])
	_add_extruded_part(knife_root, spine_shape, 0.058, dark_mat, Vector3(0, 0, 0.002))
	_build_blade_web(dark_mat)

	# Two hinged handles form the butterfly grip.
	butterfly_left = Node3D.new()
	butterfly_left.position = Vector3(-0.09, 0.10, 0.015)
	knife_root.add_child(butterfly_left)
	butterfly_right = Node3D.new()
	butterfly_right.position = Vector3(0.09, 0.10, 0.015)
	knife_root.add_child(butterfly_right)
	_build_butterfly_handle(butterfly_left, -1.0, handle_mat, accent_mat, dark_mat, wood_inlay_mat, steel_mat)
	_build_butterfly_handle(butterfly_right, 1.0, handle_mat, accent_mat, dark_mat, wood_inlay_mat, steel_mat)
	_add_knife_part(knife_root, Vector3(0, 0.105, 0.01), Vector3(0.35, 0.065, 0.12), accent_mat, Vector3.ZERO)
	_add_knife_bolt(Vector3(-0.09, 0.10, -0.075), steel_mat, dark_mat)
	_add_knife_bolt(Vector3(0.09, 0.10, -0.075), steel_mat, dark_mat)

func _build_blade_web(dark_mat: Material) -> void:
	# Thin black strips sit just in front of the blade and suggest a web pattern.
	var web_lines := [
		[Vector3(-0.01, 0.26, -0.031), Vector3(0.010, 0.25, 0.010), -48.0],
		[Vector3(-0.005, 0.41, -0.031), Vector3(0.010, 0.27, 0.010), 54.0],
		[Vector3(-0.005, 0.56, -0.031), Vector3(0.010, 0.28, 0.010), -55.0],
		[Vector3(0.035, 0.71, -0.031), Vector3(0.010, 0.29, 0.010), 58.0],
		[Vector3(0.095, 0.86, -0.031), Vector3(0.010, 0.28, 0.010), -46.0],
		[Vector3(0.15, 1.04, -0.031), Vector3(0.010, 0.22, 0.010), 48.0],
		[Vector3(-0.03, 0.52, -0.033), Vector3(0.009, 0.60, 0.010), 4.0],
		[Vector3(0.055, 0.82, -0.033), Vector3(0.009, 0.46, 0.010), 18.0]
	]
	for line in web_lines:
		_add_knife_part(knife_root, line[0], line[1], dark_mat, Vector3(0, 0, line[2]))

func _build_butterfly_handle(parent: Node3D, side: float, handle_mat: Material, accent_mat: Material, dark_mat: Material, inlay_mat: Material, steel_mat: Material) -> void:
	var outline := PackedVector2Array([
		Vector2(-0.07, 0.01), Vector2(0.07, 0.01), Vector2(0.09, -0.20),
		Vector2(0.12, -0.42), Vector2(0.18, -0.68), Vector2(0.13, -0.79),
		Vector2(-0.02, -0.76), Vector2(-0.06, -0.52), Vector2(-0.075, -0.25)
	])
	if side < 0.0:
		for i in outline.size():
			outline[i].x = -outline[i].x
	_add_extruded_part(parent, outline, 0.115, handle_mat, Vector3.ZERO)
	var liner := PackedVector2Array([
		Vector2(-0.045, -0.04), Vector2(0.045, -0.04), Vector2(0.065, -0.25),
		Vector2(0.10, -0.48), Vector2(0.13, -0.67), Vector2(0.07, -0.70),
		Vector2(0.00, -0.66), Vector2(-0.025, -0.42)
	])
	if side < 0.0:
		for i in liner.size():
			liner[i].x = -liner[i].x
	_add_extruded_part(parent, liner, 0.010, accent_mat, Vector3(0, 0, -0.064))
	var inlay := PackedVector2Array([
		Vector2(-0.025, -0.12), Vector2(0.025, -0.12), Vector2(0.055, -0.31),
		Vector2(0.085, -0.52), Vector2(0.08, -0.62), Vector2(0.025, -0.59),
		Vector2(-0.005, -0.39)
	])
	if side < 0.0:
		for i in inlay.size():
			inlay[i].x = -inlay[i].x
	_add_extruded_part(parent, inlay, 0.012, inlay_mat, Vector3(0, 0, -0.071))
	# Grip grooves, end cap and secondary hardware.
	for y in [-0.22, -0.34, -0.46, -0.58]:
		_add_knife_part(parent, Vector3(side * 0.045, y, -0.080), Vector3(0.075, 0.012, 0.012), dark_mat, Vector3(0, 0, side * 9.0))
	_add_knife_part(parent, Vector3(side * 0.115, -0.75, 0), Vector3(0.16, 0.06, 0.125), accent_mat, Vector3(0, 0, side * 13.0))
	_add_small_bolt(parent, Vector3(side * 0.055, -0.61, -0.075), steel_mat, dark_mat, 0.024)

func _add_knife_bolt(pos: Vector3, material: Material, core_material: Material) -> void:
	var bolt := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.045
	mesh.bottom_radius = 0.045
	mesh.height = 0.025
	mesh.radial_segments = 16
	mesh.material = material
	bolt.mesh = mesh
	bolt.position = pos
	bolt.rotation_degrees.x = 90.0
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	knife_root.add_child(bolt)
	_add_small_bolt(knife_root, pos + Vector3(0, 0, -0.016), core_material, core_material, 0.018)

func _add_small_bolt(parent: Node3D, pos: Vector3, material: Material, core_material: Material, radius: float) -> void:
	var bolt := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.018
	mesh.radial_segments = 12
	mesh.material = material
	bolt.mesh = mesh
	bolt.position = pos
	bolt.rotation_degrees.x = 90.0
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bolt)
	var slot := MeshInstance3D.new()
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(radius * 1.2, 0.006, radius * 0.22)
	slot_mesh.material = core_material
	slot.mesh = slot_mesh
	slot.position = pos + Vector3(0, 0, -0.012)
	parent.add_child(slot)

func _add_extruded_part(parent: Node3D, points: PackedVector2Array, thickness: float, material: Material, pos: Vector3) -> void:
	var triangles := Geometry2D.triangulate_polygon(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := thickness * 0.5
	for i in range(0, triangles.size(), 3):
		var a := points[triangles[i]]
		var b := points[triangles[i + 1]]
		var c := points[triangles[i + 2]]
		surface.set_normal(Vector3(0, 0, -1))
		surface.add_vertex(Vector3(c.x, c.y, -half))
		surface.add_vertex(Vector3(b.x, b.y, -half))
		surface.add_vertex(Vector3(a.x, a.y, -half))
		surface.set_normal(Vector3(0, 0, 1))
		surface.add_vertex(Vector3(a.x, a.y, half))
		surface.add_vertex(Vector3(b.x, b.y, half))
		surface.add_vertex(Vector3(c.x, c.y, half))
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var edge := b - a
		var normal := Vector3(edge.y, -edge.x, 0).normalized()
		surface.set_normal(normal)
		surface.add_vertex(Vector3(a.x, a.y, -half))
		surface.add_vertex(Vector3(b.x, b.y, -half))
		surface.add_vertex(Vector3(b.x, b.y, half))
		surface.add_vertex(Vector3(a.x, a.y, -half))
		surface.add_vertex(Vector3(b.x, b.y, half))
		surface.add_vertex(Vector3(a.x, a.y, half))
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _add_knife_part(parent: Node3D, pos: Vector3, size: Vector3, material: Material, rot: Vector3) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	part.mesh = mesh
	part.position = pos
	part.rotation_degrees = rot
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)

func _update_viewmodel(delta: float, on_floor: bool) -> void:
	if knife_root == null:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if on_floor and horizontal_speed > 0.25:
		viewmodel_time += delta * (5.5 + horizontal_speed * 0.7)
	else:
		viewmodel_time += delta * 1.4
	var move_amount: float = clampf(horizontal_speed / max_ground_speed, 0.0, 1.25)
	var bob_x: float = sin(viewmodel_time) * 0.018 * move_amount
	var bob_y: float = absf(cos(viewmodel_time)) * 0.014 * move_amount
	var air_drop: float = clampf(-velocity.y * 0.006, -0.035, 0.045)
	var target_pos := Vector3(0.52 + bob_x, -0.46 - bob_y + air_drop, -0.78)
	knife_root.position = knife_root.position.lerp(target_pos, minf(delta * 12.0, 1.0))
	var target_roll := -14.0 + sin(viewmodel_time) * 1.8 * move_amount
	if attacking:
		attack_time += delta
		var attack_t: float = clampf(attack_time / ATTACK_DURATION, 0.0, 1.0)
		var slash: float = sin(attack_t * PI)
		var follow: float = sin(attack_t * PI * 2.0) * 0.5
		# The blade extends along local +Y, so a positive Z rotation sweeps
		# the blade through the centre of the screen while the grip trails it.
		knife_root.position = target_pos + Vector3(-slash * 0.30, slash * 0.04, -slash * 0.10)
		knife_root.rotation_degrees.x = -18.0 - slash * 18.0
		knife_root.rotation_degrees.y = 162.0 + slash * 15.0
		knife_root.rotation_degrees.z = target_roll + slash * 105.0 + follow * 6.0
		if attack_t >= 1.0:
			attacking = false
	elif inspecting:
		inspect_time += delta
		var t: float = clampf(inspect_time / INSPECT_DURATION, 0.0, 1.0)
		var flip: float = sin(t * PI)
		var handle_flip: float = sin(t * PI * 2.0) * 105.0
		knife_root.rotation_degrees.x = -18.0 + flip * 28.0
		knife_root.rotation_degrees.y = 162.0 + t * 720.0
		knife_root.rotation_degrees.z = target_roll + sin(t * PI * 4.0) * 18.0
		butterfly_left.rotation_degrees.z = -handle_flip
		butterfly_right.rotation_degrees.z = handle_flip
		if t >= 1.0:
			inspecting = false
			butterfly_left.rotation_degrees = Vector3.ZERO
			butterfly_right.rotation_degrees = Vector3.ZERO
	else:
		knife_root.rotation_degrees.x = lerpf(knife_root.rotation_degrees.x, -18.0, minf(delta * 10.0, 1.0))
		knife_root.rotation_degrees.y = lerp_angle(deg_to_rad(knife_root.rotation_degrees.y), deg_to_rad(162.0), minf(delta * 10.0, 1.0)) * 180.0 / PI
		knife_root.rotation_degrees.z = lerpf(knife_root.rotation_degrees.z, target_roll, minf(delta * 10.0, 1.0))

func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	if wish_dir == Vector3.ZERO:
		return
	var current_speed := velocity.dot(wish_dir)
	var add_speed := wish_speed - current_speed
	if add_speed <= 0.0:
		return
	var accel_speed: float = minf(accel * wish_speed * delta, add_speed)
	velocity += wish_dir * accel_speed

func _apply_friction(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if speed < 0.001:
		return
	var control: float = maxf(stop_speed, speed)
	var new_speed: float = maxf(0.0, speed - control * friction * delta)
	new_speed /= speed
	velocity.x *= new_speed
	velocity.z *= new_speed

func _set_crouch(value: bool) -> void:
	if crouched == value:
		return
	crouched = value
	var capsule := collider.shape as CapsuleShape3D
	var target := crouched_height if crouched else standing_height
	capsule.height = target
	collider.position.y = target * 0.5
	head.position.y = 1.0 if crouched else 1.55

func set_spawn(pos: Vector3, yaw: float = 0.0) -> void:
	spawn_position = pos
	spawn_yaw = yaw

func respawn() -> void:
	if noclip_enabled:
		toggle_noclip()
	global_position = spawn_position
	rotation.y = spawn_yaw
	head.rotation.x = 0.0
	velocity = Vector3.ZERO
	jump_origin = Vector3.ZERO
	jump_queued = false
	teleport_count = 0

func set_checkpoint() -> void:
	if not is_on_floor() and not noclip_enabled:
		status_message.emit("Checkpoint можно поставить только на платформе")
		return
	if checkpoint_index < checkpoint_positions.size() - 1:
		checkpoint_positions.resize(checkpoint_index + 1)
		checkpoint_yaws.resize(checkpoint_index + 1)
		checkpoint_pitches.resize(checkpoint_index + 1)
	checkpoint_positions.append(global_position + Vector3.UP * 0.08)
	checkpoint_yaws.append(rotation.y)
	checkpoint_pitches.append(head.rotation.x)
	checkpoint_index = checkpoint_positions.size() - 1
	checkpoint_changed.emit(checkpoint_index + 1, checkpoint_positions.size())
	status_message.emit("CHECKPOINT %d СОХРАНЁН" % (checkpoint_index + 1))

func go_checkpoint() -> void:
	if checkpoint_index < 0:
		status_message.emit("Сначала поставь checkpoint клавишей Q")
		return
	global_position = checkpoint_positions[checkpoint_index]
	rotation.y = checkpoint_yaws[checkpoint_index]
	head.rotation.x = checkpoint_pitches[checkpoint_index]
	velocity = Vector3.ZERO
	jump_origin = Vector3.ZERO
	jump_queued = false
	teleport_count += 1
	teleported.emit(teleport_count)
	status_message.emit("ВОЗВРАТ НА CHECKPOINT %d" % (checkpoint_index + 1))

func change_checkpoint(offset: int) -> void:
	if checkpoint_positions.is_empty():
		status_message.emit("Нет сохранённых checkpoints")
		return
	checkpoint_index = clampi(checkpoint_index + offset, 0, checkpoint_positions.size() - 1)
	checkpoint_changed.emit(checkpoint_index + 1, checkpoint_positions.size())
	go_checkpoint()

func toggle_noclip() -> void:
	noclip_enabled = not noclip_enabled
	collision_layer = 0 if noclip_enabled else 1
	collision_mask = 0 if noclip_enabled else 1
	velocity = Vector3.ZERO
	status_message.emit("NOCLIP: %s" % ("ВКЛ" if noclip_enabled else "ВЫКЛ"))

