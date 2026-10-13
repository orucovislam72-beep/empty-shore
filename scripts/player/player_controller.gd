class_name PlayerController
extends CharacterBody3D
## Персонаж от первого лица. Ввод: действия InputMap (клавиатура, геймпад и сенсорный стик
## через Input.action_press), обзор — мышь, правый стик геймпада и свайп (Events.look_input).

## Приземление: скорость падения в момент касания земли, м/с (для урона от падения).
signal landed(fall_speed: float)

const CONFIG_PATH: String = "res://data/balance/player.json"

@export var head_path: NodePath = ^"Head"

var autorun: bool = false
var crouching: bool = false

var _cfg: Dictionary = {}
var _walk_speed: float = 4.0
var _run_speed: float = 6.5
var _crouch_speed: float = 2.0
var _jump_velocity: float = 5.0
var _accel: float = 30.0
var _air_control: float = 0.3
var _eye_height: float = 1.65
var _crouch_eye_height: float = 1.0
var _pitch_limit: float = deg_to_rad(85.0)
var _touch_deg_per_px: float = 0.15
var _pad_deg_per_sec: float = 160.0
var _mouse_deg_per_px: float = 0.12
var _gravity: float = 9.8
var _pending_look: Vector2 = Vector2.ZERO
var _active: bool = false

@onready var _head: Node3D = get_node(head_path) as Node3D


func _ready() -> void:
	_cfg = JsonData.load_dict(CONFIG_PATH)
	_walk_speed = JsonData.get_float(_cfg, "walk_speed", _walk_speed)
	_run_speed = JsonData.get_float(_cfg, "run_speed", _run_speed)
	_crouch_speed = JsonData.get_float(_cfg, "crouch_speed", _crouch_speed)
	_jump_velocity = JsonData.get_float(_cfg, "jump_velocity", _jump_velocity)
	_accel = JsonData.get_float(_cfg, "acceleration", _accel)
	_air_control = JsonData.get_float(_cfg, "air_control", _air_control)
	_eye_height = JsonData.get_float(_cfg, "eye_height", _eye_height)
	_crouch_eye_height = JsonData.get_float(_cfg, "crouch_eye_height", _crouch_eye_height)
	_pitch_limit = deg_to_rad(JsonData.get_float(_cfg, "pitch_limit_deg", 85.0))
	_touch_deg_per_px = JsonData.get_float(_cfg, "touch_look_deg_per_px", _touch_deg_per_px)
	_pad_deg_per_sec = JsonData.get_float(_cfg, "gamepad_look_deg_per_sec", _pad_deg_per_sec)
	_mouse_deg_per_px = JsonData.get_float(_cfg, "mouse_look_deg_per_px", _mouse_deg_per_px)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	floor_max_angle = deg_to_rad(JsonData.get_float(_cfg, "floor_max_angle_deg", 45.0))
	_head.position.y = _eye_height
	Events.look_input.connect(_on_look_input)
	Events.autorun_toggle_requested.connect(_on_autorun_toggle)


## Включить физику персонажа (после того как ландшафт построен).
func activate_at(spawn: Vector3) -> void:
	global_position = spawn
	velocity = Vector3.ZERO
	_active = true


## Остановить персонажа (гибель): ни движения, ни физики.
func deactivate() -> void:
	_active = false
	velocity = Vector3.ZERO
	_set_autorun(false)


func is_active() -> bool:
	return _active


## Поворот игрока (рысканье) и наклон головы, радианы.
func set_look(yaw: float, pitch: float) -> void:
	rotation.y = yaw
	_head.rotation.x = clampf(pitch, -_pitch_limit, _pitch_limit)


func get_pitch() -> float:
	return _head.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event
		_pending_look += mm.relative * (_mouse_deg_per_px / _touch_deg_per_px)
	elif event.is_action_pressed("toggle_autorun"):
		_on_autorun_toggle()


func _on_look_input(relative: Vector2) -> void:
	_pending_look += relative


func _on_autorun_toggle() -> void:
	_set_autorun(not autorun)


func _set_autorun(value: bool) -> void:
	if autorun == value:
		return
	autorun = value
	Events.autorun_changed.emit(autorun)


func _sensitivity() -> float:
	var s: GameSettings = Settings.data
	return s.aim_sensitivity if Input.is_action_pressed("aim") else s.look_sensitivity


func _process(delta: float) -> void:
	var sens: float = _sensitivity()
	var invert: float = -1.0 if Settings.data.invert_y else 1.0
	# Свайп и мышь: накопленные пиксели.
	var yaw_deg: float = -_pending_look.x * _touch_deg_per_px * sens
	var pitch_deg: float = -_pending_look.y * _touch_deg_per_px * sens * invert
	_pending_look = Vector2.ZERO
	# Правый стик геймпада.
	var pad: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw_deg -= pad.x * _pad_deg_per_sec * sens * delta
	pitch_deg -= pad.y * _pad_deg_per_sec * sens * delta * invert
	rotate_y(deg_to_rad(yaw_deg))
	_head.rotation.x = clampf(_head.rotation.x + deg_to_rad(pitch_deg), -_pitch_limit, _pitch_limit)
	var target_eye: float = _crouch_eye_height if crouching else _eye_height
	_head.position.y = move_toward(_head.position.y, target_eye, 4.0 * delta)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	crouching = Input.is_action_pressed("crouch")
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if autorun:
		if input.y > 0.5:
			_set_autorun(false)
		elif input.y > -0.5:
			input.y = -1.0
	var speed: float = _walk_speed
	if crouching:
		speed = _crouch_speed
	elif autorun:
		speed = _run_speed
	var wish: Vector3 = (transform.basis * Vector3(input.x, 0.0, input.y))
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var target: Vector3 = wish * speed
	var control: float = 1.0 if is_on_floor() else _air_control
	velocity.x = move_toward(velocity.x, target.x, _accel * control * delta)
	velocity.z = move_toward(velocity.z, target.z, _accel * control * delta)
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not crouching:
			velocity.y = _jump_velocity
	else:
		velocity.y -= _gravity * delta
	var was_on_floor: bool = is_on_floor()
	var fall_speed: float = -velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor() and fall_speed > 0.0:
		landed.emit(fall_speed)
