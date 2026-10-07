extends CharacterBody3D
## 1.8 m capsule. Feet at local origin. Same controller runs physics acceptance.
var service: Node
var camera: Camera3D
var speed := 4.0
var shape: CapsuleShape3D
func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	shape = CapsuleShape3D.new()
	shape.radius = 0.30
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.92
	add_child(collider)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.current = true
	camera.fov = 78
	add_child(camera)
	floor_snap_length = 0.25
func _unhandled_input(event: InputEvent) -> void:
	if service == null or not service.world_enabled(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.0025)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.0025, -1.3, 1.3)
func _physics_process(delta: float) -> void:
	if service == null: return
	if not service.world_enabled():
		velocity = Vector3.ZERO
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (basis * Vector3(input.x, 0.0, input.y)).normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor(): velocity.y -= 18.0 * delta
	elif Input.is_action_just_pressed("jump"): velocity.y = 5.0
	else: velocity.y = 0.0
	move_and_slide()
