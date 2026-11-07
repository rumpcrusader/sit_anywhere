extends Node
## Sit Anywhere: Z sits desktop Anon down on the ground where he stands, Z again stands him back
## up, and WASD shuffles him along the floor while seated. Q stands him up as well
## (desktop_player.gd's ordinary seat rules, with ext/desktop_player.gd suppressing its
## movement-stands-up check for this one seat).
##
## This borrows the game's own seat plumbing instead of inventing a pose: an invisible seat at
## his feet makes desktop_player.gd lower the eye to seated height, disable walking collision,
## and makes desktop_anon.gd/anon_motion.gd play the sit clip. Seating's usual accessibility ray,
## occupant claim, eye easing and stand-up exit are used unchanged, so updaters and other systems
## still see a normal seated player.
##
## Desktop only: AnonPony already sits on Z (player/pony_form.gd), and seated VR has its own rig.

## The toggle. Z is already the game's "Sit (pony)" key, so it is the natural one for Anon too.
const KEY_SIT := KEY_Z
## Standing up from a real seat places you in front of it: exit_space.gd measures that as
## depth * 0.5 + 0.55 from the seat. This seat is at his feet, so this value cancels the offset
## and lets him stand on exactly the spot he sat down.
const STAND_DEPTH := -1.1

## Anon's own sit clip is authored for a chair: its feet hang about 0.37 m below the seat.
## On a ground seat that would bury both shins, so the mod moves the game's foot IK targets
## forward and onto the floor while seated. The clip still owns the hips and upper body; only
## the feet move, and the ordinary two-bone IK bends the knees.
const FOOT_FORWARD := 0.68
const FOOT_SPREAD := 0.14
## Ankle height above the floor (model units): the game's rest foot bone sits at 0.12, and its
## toe bone about 0.09 below that. Targeting the floor directly would bury the toes.
const ANKLE_UP := 0.12
const KNEE_FORWARD := 0.28
const KNEE_UP := 0.50
## Feet slide from his standing spots to the floor-sit spots instead of snapping there.
const POSE_TIME := 0.22
## Rest-facing half turn of the model (anon_body.gd REST_FACING).
const REST_FACING := PI
## Metres of body travel per complete two-foot shuffle cycle. The stance foot is moved back
## through the seat by half this distance while the other foot swings forward, so it stays put
## on the floor instead of gliding with him.
const SHUFFLE_STEP := 0.28
## Swing foot lift above the floor (metres at scale 1).
const SHUFFLE_LIFT := 0.045
## How quickly the legs return to the ordinary seated pose when he stops.
const SHUFFLE_FADE := 8.0

var _player: Node3D
var _holder: Node3D
var _seat: Node3D
var _avatar: Node3D
var _left_foot: Node3D
var _right_foot: Node3D
var _body_ik: Node
var _pose_time := 0.0
var _from_left := Transform3D.IDENTITY
var _from_right := Transform3D.IDENTITY
var _has_from := false
## Ground-seat travel drives the shuffle: phase, fade and direction.
var _last_seat := Vector3.ZERO
var _shuffle_phase := 0.0
var _shuffle_amount := 0.0
var _shuffle_dir := Vector3.ZERO


func _ready() -> void:
	# After anon_body.gd has written the clip's foot targets: this mod replaces them while seated.
	process_priority = 1000
	set_process(false)
	Mods.player_ready.connect(_on_player_ready)
	Mods.world_closed.connect(_on_world_closed)
	# A mod switched on mid-game has missed player_ready.
	var game: Variant = Mods.game
	if game is Node:
		var player: Variant = (game as Node).get("player")
		if player is Node3D and is_instance_valid(player): _on_player_ready(player)


func _on_player_ready(player: Node) -> void:
	_discard_seat()
	_player = player as Node3D


func _on_world_closed(_game: Node) -> void:
	# The whole world is going away; do not touch its player on the way out.
	_player = null
	_discard_seat()


func _exit_tree() -> void:
	# Switched off in Settings → Mods while he is sitting: put him back on his feet first.
	if is_instance_valid(_player) and _player.is_inside_tree() and _is_ours(_player.get("seat")):
		_stand()
	else:
		_discard_seat()
	_player = null


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_SIT: return
	if not _can_toggle(): return
	get_viewport().set_input_as_handled()
	_toggle()


## True while the toggle belongs to this mod: desktop human Anon, in control, not airborne,
## swimming, knocked down or held by a wake/menu. Furniture seats keep Q/E as the game gave them.
func _can_toggle() -> bool:
	if not is_instance_valid(_player) or not _player.is_inside_tree(): return false
	if _player.get("headset_view") == true: return false
	if _player.get("form_driver") != null: return false
	if _player.get("controls_locked") == true or _player.get("view_hold") == true: return false
	if _player.get("flying") == true: return false
	var wings: Variant = _player.get("wing_flight")
	if wings is Object and bool((wings as Object).get("active")): return false
	var swimming: Variant = _player.get("swimming")
	if swimming is Object and bool((swimming as Object).get("active")): return false
	var knockdown: Variant = _player.get("knockdown")
	if knockdown is Object and bool((knockdown as Object).get("active")): return false
	if not _player.has_method("sit_on") or not _player.has_method("stand_up"): return false
	# A typing field owns the keyboard.
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return false
	# A real bench, sofa or bed: its own stand-up keys stay authoritative.
	var seat: Variant = _player.get("seat")
	if seat is Node3D and is_instance_valid(seat) and not _is_ours(seat): return false
	return true


func _toggle() -> void:
	if _is_ours(_player.get("seat")):
		_stand()
	else:
		_sit()


## Seat on the ground at his feet, facing where he looks, through the game's own sit_on().
func _sit() -> void:
	if not is_instance_valid(_player): return
	# Not in mid-air (walking off a ledge, flying is already refused above).
	var body := _player as CharacterBody3D
	if body != null and not body.is_on_floor(): return
	# Stale seat from a stand-up the game performed (movement, E, a knock): drop it first.
	if is_instance_valid(_seat) and _player.get("seat") != _seat: _discard_seat()

	var forward := -_player.global_basis.z
	var camera: Camera3D = _player.get("camera") as Camera3D
	if camera == null: camera = get_viewport().get_camera_3d()
	if camera != null: forward = -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < .0001: forward = Vector3.FORWARD
	forward = forward.normalized()

	# A dedicated parent keeps Seating's furniture filters from treating the whole scene as the
	# seat's furniture during accessibility and stand-up checks.
	var holder := Node3D.new()
	holder.name = "SitAnywhere"
	var root: Node = _player.get_tree().current_scene
	if root == null: root = _player.get_tree().root
	root.add_child(holder)
	var seat := Node3D.new()
	seat.name = "GroundSeat"
	seat.set_meta("depth", STAND_DEPTH)
	seat.set_meta("sit_anywhere", true)
	holder.add_child(seat)
	seat.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), _player.global_position)

	if not bool(_player.call("sit_on", seat)):
		holder.queue_free()
		return
	_holder = holder
	_seat = seat
	_bind_avatar()
	_pose_time = 0.0
	_last_seat = seat.global_position
	_shuffle_phase = 0.0
	_shuffle_amount = 0.0
	_shuffle_dir = Vector3.ZERO
	_has_from = is_instance_valid(_left_foot) and is_instance_valid(_right_foot)
	if _has_from:
		_from_left = _left_foot.global_transform
		_from_right = _right_foot.global_transform
	set_process(true)


func _stand() -> void:
	var player := _player
	if is_instance_valid(player):
		# force_stand_up() uses the normal exit and always puts collision back on; with the
		# depth above that exit is this very spot.
		if player.has_method("force_stand_up"): player.call("force_stand_up")
		elif player.has_method("stand_up"): player.call("stand_up")
		# If the game refused every exit, at least get him off this temporary seat safely.
		if _is_ours(player.get("seat")): _clear_direct(player)
	_discard_seat()


func _clear_direct(player: Node3D) -> void:
	var at := player.global_position
	player.set("seat", null)
	if is_instance_valid(_seat) and _seat.has_meta("occupant") and _seat.get_meta("occupant") == player:
		_seat.remove_meta("occupant")
	var collision := player.get_node_or_null("Collision") as CollisionShape3D
	if collision != null: collision.disabled = false
	player.global_position = at
	if "velocity" in player: player.set("velocity", Vector3.ZERO)


## The game may stand him up without asking (E, Q, a knockdown): release our seat then.
func _process(delta: float) -> void:
	if _seat == null: return
	if not is_instance_valid(_seat) or not is_instance_valid(_player) or _player.get("seat") != _seat:
		_discard_seat()
		return
	_pose_time = minf(_pose_time + delta, POSE_TIME)
	_update_shuffle(delta)
	_apply_floor_pose()


## The seat's actual travel is the gait clock, so the steps keep pace with the slide and stop
## when he stops. `_shuffle_phase` wraps once per two-foot cycle; the stance foot's world
## position then stays still while the body moves past it.
func _update_shuffle(delta: float) -> void:
	if not is_instance_valid(_seat): return
	var moved := _seat.global_position - _last_seat
	_last_seat = _seat.global_position
	var flat := Vector3(moved.x, 0.0, moved.z)
	var moving := flat.length_squared() > 0.0000001
	_shuffle_amount = move_toward(_shuffle_amount, 1.0 if moving else 0.0, delta * SHUFFLE_FADE)
	if not moving: return
	var direction := flat.normalized()
	if _shuffle_dir.length_squared() < 0.001:
		_shuffle_dir = direction
	else:
		_shuffle_dir = _shuffle_dir.lerp(direction, 1.0 - exp(-delta / 0.08)).normalized()
	_shuffle_phase = fposmod(_shuffle_phase + flat.length() / SHUFFLE_STEP, 1.0)


## One foot's place in the cycle: x is its offset along the travel direction, y its lift.
func _foot_step(phase: float) -> Vector2:
	var half := SHUFFLE_STEP * 0.25
	var cycle := fposmod(phase, 1.0)
	if cycle < 0.5:
		# Swing: lift the foot and carry it from back to front.
		var t := cycle / 0.5
		return Vector2(lerpf(-half, half, smoothstep(0.0, 1.0, t)), sin(PI * t) * SHUFFLE_LIFT)
	# Stance: the foot stays planted while the body travels forward over it.
	var t := (cycle - 0.5) / 0.5
	return Vector2(lerpf(half, -half, t), 0.0)


func _bind_avatar() -> void:
	_avatar = _player.find_child("AnonBody", true, false) as Node3D
	_left_foot = null; _right_foot = null; _body_ik = null
	if not is_instance_valid(_avatar): _avatar = null; return
	_left_foot = _avatar.find_child("LeftFootTarget", true, false) as Node3D
	_right_foot = _avatar.find_child("RightFootTarget", true, false) as Node3D
	_body_ik = _avatar.find_child("BodyIK", true, false)


## Keep the feet on the floor: place the IK targets in front of him at ankle height, and aim the
## knees up. Runs after anon_body.gd's own foot targets, before the skeleton's IK pass.
func _apply_floor_pose() -> void:
	if not is_instance_valid(_seat) or not is_instance_valid(_player): return
	if not is_instance_valid(_avatar) or not is_instance_valid(_left_foot) or not is_instance_valid(_right_foot): return
	var scale := 1.0
	var value: Variant = _avatar.get("model_scale")
	if value is float and float(value) > .05: scale = float(value)
	var forward := -_seat.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < .0001: forward = -_player.global_basis.z
	forward = forward.normalized()
	var right := _seat.global_basis.x
	right.y = 0.0
	if right.length_squared() < .0001: right = forward.cross(Vector3.UP)
	right = right.normalized()
	# The ankle target sits one foot-height above the floor, so the game's own foot orientation
	# puts the soles down. Spread and reach scale with Anon's chosen height.
	var ankle := _seat.global_position + forward * FOOT_FORWARD * scale + Vector3.UP * ANKLE_UP * scale
	var spread := right * FOOT_SPREAD * scale
	var basis := Basis(Vector3.UP, atan2(-forward.x, -forward.z) + REST_FACING)
	var travel := _shuffle_dir if _shuffle_dir.length_squared() > 0.001 else forward
	var left_step := _foot_step(_shuffle_phase)
	var right_step := _foot_step(_shuffle_phase + 0.5)
	var left_shift := travel * (left_step.x * _shuffle_amount * scale)
	var right_shift := travel * (right_step.x * _shuffle_amount * scale)
	var left := ankle - spread + left_shift + Vector3.UP * (left_step.y * _shuffle_amount * scale)
	var right_foot := ankle + spread + right_shift + Vector3.UP * (right_step.y * _shuffle_amount * scale)
	var left_xf := Transform3D(basis, left)
	var right_xf := Transform3D(basis, right_foot)
	if _has_from and _pose_time < POSE_TIME:
		var weight := smoothstep(0.0, POSE_TIME, _pose_time)
		left_xf = _blend_transform(_from_left, left_xf, weight)
		right_xf = _blend_transform(_from_right, right_xf, weight)
	_left_foot.global_transform = left_xf
	_right_foot.global_transform = right_xf
	if _body_ik != null and is_instance_valid(_body_ik) and "knee_hints" in _body_ik:
		var knee := _seat.global_position + forward * KNEE_FORWARD * scale + Vector3.UP * KNEE_UP * scale
		var left_knee := knee - spread + travel * (left_step.x * _shuffle_amount * scale * 0.5)
		var right_knee := knee + spread + travel * (right_step.x * _shuffle_amount * scale * 0.5)
		_body_ik.set("knee_hints", {"left": left_knee, "right": right_knee})


static func _blend_transform(from: Transform3D, to: Transform3D, weight: float) -> Transform3D:
	if weight >= 1.0: return to
	if weight <= 0.0: return from
	return Transform3D(from.basis.orthonormalized().slerp(to.basis.orthonormalized(), weight), from.origin.lerp(to.origin, weight))


func _discard_seat() -> void:
	if is_instance_valid(_holder): _holder.queue_free()
	_holder = null
	_seat = null
	_avatar = null
	_left_foot = null
	_right_foot = null
	_body_ik = null
	_pose_time = 0.0
	_has_from = false
	_last_seat = Vector3.ZERO
	_shuffle_phase = 0.0
	_shuffle_amount = 0.0
	_shuffle_dir = Vector3.ZERO
	set_process(false)


func _is_ours(value: Variant) -> bool:
	return value is Node3D and is_instance_valid(value) and bool((value as Node3D).get_meta("sit_anywhere", false))
