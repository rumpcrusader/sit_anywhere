extends "res://player/desktop_player.gd"
## Sit Anywhere: WASD shuffles the temporary ground seat instead of standing Anon up.
##
## The game's seated branch stands the player on any movement input. The entry script cannot
## suppress that, so this extension runs that branch with controls_locked for the duration of the
## tick; only the mod's own ground seat gets the treatment. Real furniture seats, VR and AnonPony
## keep the game's normal stand-up rules.

const SIT_ANYWHERE := "sit_anywhere"
const SHUFFLE_SPEED := 0.55
const FLOOR_PROBE_UP := 0.5
const FLOOR_PROBE_DOWN := 1.5
const GROUND_NORMAL := 0.85
const FOOT_CLEARANCE := 0.04


func _physics_process(delta: float) -> void:
	if not _own_ground_seat() or headset_view or controls_locked:
		super(delta)
		return
	var was_locked := controls_locked
	controls_locked = true
	_shuffle(delta)
	super(delta)
	controls_locked = was_locked


func _own_ground_seat() -> bool:
	return seat is Node3D and is_instance_valid(seat) and bool(seat.get_meta(SIT_ANYWHERE, false))


## Hold WASD to slide along the floor in the direction he is looking. Movement stops at walls,
## furniture and ledges; diagonals slide along the blocking side instead of stopping dead.
func _shuffle(delta: float) -> void:
	if not is_instance_valid(seat): return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length_squared() < 0.02: return
	var move := global_basis * Vector3(input.x, 0.0, input.y)
	move.y = 0.0
	if move.length_squared() < 0.000001: return
	move = move.normalized() * SHUFFLE_SPEED * delta
	if _step_seat(move): return
	# Slide along a wall: try each world axis on its own.
	if not _step_seat(Vector3(move.x, 0.0, 0.0)):
		_step_seat(Vector3(0.0, 0.0, move.z))


func _step_seat(offset: Vector3) -> bool:
	if offset.length_squared() < 0.0000001: return false
	var at := seat.global_position + offset
	var floor := _floor_at(at)
	if not floor.is_finite(): return false
	at.y = floor.y
	if not _clear_at(at): return false
	seat.global_position = at
	# Fallback exit if the game cannot find a clear spot when standing later.
	_seat_return = at
	return true


func _floor_at(at: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * FLOOR_PROBE_UP,
		at + Vector3.DOWN * FLOOR_PROBE_DOWN,
		collision_mask,
		[get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty(): return Vector3.INF
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if normal.y < GROUND_NORMAL: return Vector3.INF
	var out: Vector3 = hit["position"]
	return out + Vector3.UP * FOOT_CLEARANCE


func _clear_at(at: Vector3) -> bool:
	var holder := get_node_or_null("Collision") as CollisionShape3D
	var capsule: CapsuleShape3D = null
	if holder != null: capsule = holder.shape as CapsuleShape3D
	if capsule == null: return false
	var shape := capsule.duplicate() as CapsuleShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (shape.height * 0.5 + FOOT_CLEARANCE))
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
