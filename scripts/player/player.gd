extends CharacterBody3D
## First-person player controller.
##
## Terraced terrain makes step-up load-bearing rather than a nicety: every slope on
## this island is either flat or a vertical face, so without automatic step-up the
## player would have to jump at every single 1 m terrace edge. With it, 1 m ledges
## are walked over and anything taller is a genuine wall — which is also how slope
## refusal manifests here, since there are no intermediate gradients to refuse.
##
## No player model or animation: the first-person decision means there is no body to
## see, so there is nothing to animate.

## Movement speeds in metres per second.
const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.8
const CROUCH_SPEED := 2.1

## Ground acceleration and air control, in metres per second squared.
const ACCELERATION := 45.0
const AIR_ACCELERATION := 8.0
const FRICTION := 55.0

const GRAVITY := 24.0
const JUMP_HEIGHT_M := 1.25

## Tallest ledge the player walks up without jumping. Just over a terrace so a 1 m
## step always clears and a 2 m step never does.
const MAX_STEP_HEIGHT := 1.05

## Steepest walkable surface. Terrace tops are flat and skirts are vertical, so this
## chiefly decides that skirts are walls rather than ramps.
const MAX_SLOPE_DEGREES := 50.0

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const STAND_EYE_HEIGHT := 1.65
const CROUCH_EYE_HEIGHT := 1.05

const MOUSE_SENSITIVITY := 0.0022
const PITCH_LIMIT_DEGREES := 89.0

# --- swimming -----------------------------------------------------------------

const SWIM_SPEED := 3.2

## Swimming begins once the feet are this far under the surface. Wading with the chest
## clear stays walking, which is what keeps a beach walkable and a 0.6 m river
## crossable on foot.
const SWIM_SUBMERGE_HEIGHT := 1.25

## Swimming ends only once the player is this shallow — deliberately much less than
## the depth needed to start.
##
## The hysteresis is required, not cosmetic. Buoyancy holds the player at
## SWIM_FLOAT_DEPTH, which is shallower than the depth that starts a swim; with a
## single threshold the player would surface, stop swimming, fall under gravity, start
## swimming again, and oscillate every few frames.
const SWIM_EXIT_DEPTH := 0.5

## How deep the feet float below the surface once swimming, so the head stays clear.
const SWIM_FLOAT_DEPTH := 1.05

## How hard buoyancy pulls the body back to floating depth, per second.
const BUOYANCY := 6.0
const MAX_BUOYANT_SPEED := 4.0

## Vertical speed when deliberately diving or surfacing.
const SWIM_VERTICAL_SPEED := 2.6

# --- flight --------------------------------------------------------------------

const FLIGHT_SPEED := 9.0
const FLIGHT_ACCELERATION := 20.0

## Y of the ocean surface. Set by the world so the player does not have to know how
## the sea was built.
var water_level_y: float = 0.0

var _swimming := false

## Whether a flying suit has been equipped. Equipping consumes it from the inventory the
## same way wearing armour does, so a found suit is either in the pack or in use, never
## both — and, unlike the hotbar-selected firearms, it stays equipped while the player
## selects a gun to fight from the air.
var _flight_suit_equipped := false
var _flying := false
var _flight_fuel: RefCounted = FlightFuel.new()

const SurvivalStats := preload("res://scripts/player/survival_stats.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const FlightFuel := preload("res://scripts/player/flight_fuel.gd")

signal died

## One-off things the player should be told: the suit was equipped, the tank is full,
## there is no fuel left to fly on. Mirrors `Firearm.refused` and `ItemPlacer.message` —
## the HUD listens the same way.
signal message(text: String)

## Where death returns the player to. Set by the world once the island exists.
var respawn_point := Vector3.ZERO

var _stats: RefCounted = SurvivalStats.new()
var _inventory: RefCounted = Inventory.new()

## Counts overlapping shelter volumes rather than a plain flag.
##
## A counter matters wherever cover props overlap — a thicket beside an overhang, say.
## With a boolean, stepping out of one volume while still inside the other would clear
## the state and expose the player to weather they are plainly standing out of.
var _shelter_count := 0

## What is being worn. Armour is worn rather than carried, so it keeps working while the
## hotbar holds something else.
var _worn := ItemKind.Kind.NONE

var _jump_velocity: float = sqrt(2.0 * GRAVITY * JUMP_HEIGHT_M)
var _crouching := false

var _camera: Camera3D
var _collision: CollisionShape3D
var _capsule: CapsuleShape3D


func _ready() -> void:
	_camera = get_node_or_null(^"Camera3D") as Camera3D
	_collision = get_node_or_null(^"Collision") as CollisionShape3D

	# Sub-resources are shared between scene instances unless duplicated, and
	# crouching mutates the capsule. Without this, two players would resize each
	# other.
	if _collision != null and _collision.shape is CapsuleShape3D:
		_capsule = _collision.shape.duplicate()
		_collision.shape = _capsule

	floor_max_angle = deg_to_rad(MAX_SLOPE_DEGREES)
	# Long enough to settle onto a terrace after a step-up, and to hold the player
	# on the ground when walking off a 1 m lip rather than launching them.
	floor_snap_length = 0.6

	for component_path in [^"Harvester", ^"Melee", ^"Firearm"]:
		var component := get_node_or_null(component_path)
		if component != null and component.has_method(&"bind"):
			component.bind(self, _camera)

	# The viewmodel hangs off the camera and only needs to know what is being held.
	if _camera != null:
		var viewmodel := _camera.get_node_or_null(^"Viewmodel")
		if viewmodel != null and viewmodel.has_method(&"bind"):
			viewmodel.bind(self)

	capture_mouse()


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func is_crouching() -> bool:
	return _crouching


## Exposed because predators notice a sprinting player from further away. Crouching hides
## you, running advertises you.
func is_sprinting() -> bool:
	return _is_sprinting()


func is_swimming() -> bool:
	return _swimming


## The player's condition. Read by the HUD and the overlay; mutated through eat/damage.
func stats() -> RefCounted:
	return _stats


## Uses the held item. Bound by the world, which supplies where fires are parented and
## which climate registers them.
func item_placer() -> Node:
	return get_node_or_null(^"ItemPlacer")


## The harvest interaction, so the HUD can show its prompt.
func harvester() -> Node:
	return get_node_or_null(^"Harvester")


## What the player is carrying. Harvesting, crafting and the HUD all go through this.
func inventory() -> RefCounted:
	return _inventory


## Eats the held item if it is food. Returns whether anything was eaten, so the caller
## can give feedback rather than the action failing silently.
func eat_selected() -> bool:
	var item: int = _inventory.selected_item()
	if not ItemKind.is_food(item):
		return false
	# Refused only when there is nothing at all to gain. A partial top-up is allowed:
	# refusing it because some nutrition would be wasted would stop a player eating
	# before heading somewhere dangerous, which is worse than the waste.
	if _stats.eat(ItemKind.nutrition(item)) <= 0.0:
		return false
	# Raw meat feeds you and makes you ill. The cost is what makes a fire worth building
	# rather than an optional flourish.
	var cost := ItemKind.health_cost(item)
	if cost > 0.0:
		_stats.damage(cost)
	_inventory.remove_from_slot(_inventory.selected_slot(), 1)
	return true


## Degrees of warmth from what the player is wearing. Read by the climate.
func insulation_c() -> float:
	return ItemKind.insulation(_worn)


func worn_item() -> int:
	return _worn


## Wears the held item if it is armour. Returns whether anything changed, so the caller
## can report rather than failing silently.
func wear_selected() -> bool:
	var item: int = _inventory.selected_item()
	if not ItemKind.is_wearable(item) or item == _worn:
		return false
	# The old garment comes back to the pack rather than vanishing.
	if _worn != ItemKind.Kind.NONE:
		_inventory.add(_worn, 1)
	_inventory.remove_from_slot(_inventory.selected_slot(), 1)
	_worn = item
	return true


func has_flight_suit() -> bool:
	return _flight_suit_equipped


func is_flying() -> bool:
	return _flying


## The suit's fuel tank. Read by the HUD and by tests, which cannot see the screen.
func flight_fuel() -> RefCounted:
	return _flight_fuel


## Equips the flying suit if it is what is selected. Returns whether anything changed,
## the same shape as `wear_selected`.
func equip_selected_flight_suit() -> bool:
	var item: int = _inventory.selected_item()
	if item != ItemKind.Kind.FLYING_SUIT or _flight_suit_equipped:
		return false
	_inventory.remove_from_slot(_inventory.selected_slot(), 1)
	_flight_suit_equipped = true
	return true


## Empties the held fuel item into the suit's tank. Refused only once the tank is
## already full, so a near-full tank does not waste a whole found item's worth of fuel.
func refuel_flight_suit() -> bool:
	if not _flight_suit_equipped or _flight_fuel.is_full():
		return false
	if _inventory.remove_from_slot(_inventory.selected_slot(), 1) <= 0:
		return false
	_flight_fuel.add(FlightFuel.FUEL_PER_ITEM)
	return true


## Toggles flight. Starting requires the suit and fuel; stopping is always allowed, so
## the player can choose to land as well as run dry.
func toggle_flight() -> void:
	if _flying:
		_flying = false
		return
	if not _flight_suit_equipped:
		message.emit("no flying suit equipped")
		return
	if _flight_fuel.is_empty():
		message.emit("the flying suit is out of fuel")
		return
	_swimming = false
	_flying = true


func status_line() -> String:
	var worn := "" if _worn == ItemKind.Kind.NONE \
			else " | wearing: %s" % ItemKind.name_of(_worn)
	var suit := "" if not _flight_suit_equipped \
			else " | %s%s" % [_flight_fuel.status_line(), " FLYING" if _flying else ""]
	return "%s\n%s%s%s" % [_stats.status_line(), _inventory.status_line(), worn, suit]


## Returns the player to the shore with their condition reset. Progress is kept; only
## position is lost.
func respawn() -> void:
	_stats.revive()
	_swimming = false
	_flying = false
	_shelter_count = 0
	velocity = Vector3.ZERO
	set_crouching(false)
	global_position = respawn_point


## True while inside at least one cover prop's shelter volume.
func is_sheltered() -> bool:
	return _shelter_count > 0


## Called by a shelter volume when the player walks in.
func enter_shelter() -> void:
	_shelter_count += 1


## Called by a shelter volume when the player walks out.
func exit_shelter() -> void:
	_shelter_count = maxi(0, _shelter_count - 1)


## How far the feet are below the water surface. Negative when out of the water.
func depth_in_water() -> float:
	return water_level_y - global_position.y


## True once enough of the body is under the surface to begin swimming.
func submerged() -> bool:
	return depth_in_water() > SWIM_SUBMERGE_HEIGHT


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if mouse_captured():
			release_mouse()
		else:
			capture_mouse()
		return

	# Clicking back into the window recaptures, so the player is not stuck with a
	# free cursor after alt-tabbing.
	if event is InputEventMouseButton and not mouse_captured():
		capture_mouse()
		return

	if event is InputEventMouseMotion and mouse_captured():
		_look(event.relative)
		return

	if event.is_action_pressed(&"activate_flight"):
		toggle_flight()
		return

	_handle_hotbar_input(event)


## Scroll wheel cycles the hotbar; number keys jump straight to a slot.
func _handle_hotbar_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"hotbar_next"):
		_inventory.cycle_selection(1)
	elif event.is_action_pressed(&"hotbar_prev"):
		_inventory.cycle_selection(-1)
	else:
		for slot in Inventory.HOTBAR_SLOTS:
			if event.is_action_pressed(StringName("hotbar_%d" % (slot + 1))):
				_inventory.select(slot)
				return


## Kicks the aim up by `pitch_radians`, or back down for a negative value.
##
## Goes through the player rather than the firearm touching the camera directly, because
## the pitch limit lives here — a burst fired at the sky must not roll the view over.
func apply_recoil(pitch_radians: float) -> void:
	if _camera == null:
		return
	var limit := deg_to_rad(PITCH_LIMIT_DEGREES)
	_camera.rotation.x = clampf(_camera.rotation.x + pitch_radians, -limit, limit)


func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENSITIVITY)
	if _camera == null:
		return
	var limit := deg_to_rad(PITCH_LIMIT_DEGREES)
	_camera.rotation.x = clampf(
			_camera.rotation.x - relative.y * MOUSE_SENSITIVITY, -limit, limit)


func _physics_process(delta: float) -> void:
	# Sprinting is what the player is actually doing, not what they are asking for, so
	# stamina is only spent on movement that happened.
	_stats.tick(delta, _is_sprinting())
	if _stats.is_dead():
		died.emit()
		respawn()
		return

	_update_swim_state()
	if _swimming:
		_swim(delta)
		return

	if _flying:
		_fly(delta)
		return

	_update_crouch(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed(&"jump") and not _crouching:
		velocity.y = _jump_velocity

	var wish := _wish_direction()
	var target := wish * current_speed()
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish.is_zero_approx() and is_on_floor():
		horizontal = horizontal.move_toward(Vector3.ZERO, FRICTION * delta)
	else:
		horizontal = horizontal.move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	try_step_up(horizontal * delta)
	move_and_slide()


## Enters and leaves the swim state on two different thresholds, so floating at the
## surface cannot bounce the player in and out of swimming.
func _update_swim_state() -> void:
	var depth := depth_in_water()
	if _swimming:
		_swimming = depth > SWIM_EXIT_DEPTH
	else:
		_swimming = depth > SWIM_SUBMERGE_HEIGHT


## Swimming: no ground contact, no gravity. Buoyancy holds the body at floating depth
## so the player surfaces on their own, and jump/crouch override it to rise or dive.
func _swim(delta: float) -> void:
	if _crouching:
		set_crouching(false)

	var wish := _wish_direction()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(wish * SWIM_SPEED, ACCELERATION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if Input.is_action_pressed(&"jump"):
		velocity.y = SWIM_VERTICAL_SPEED
	elif Input.is_action_pressed(&"crouch"):
		velocity.y = -SWIM_VERTICAL_SPEED
	else:
		# Settle towards floating depth rather than snapping, so the surface is not a
		# hard ceiling the player sticks to.
		var target_y := water_level_y - SWIM_FLOAT_DEPTH
		velocity.y = clampf((target_y - global_position.y) * BUOYANCY,
				-MAX_BUOYANT_SPEED, MAX_BUOYANT_SPEED)

	move_and_slide()


## Flying: full three-dimensional movement steered by mouselook, fuel spent whether or
## not the player is actually moving. Fuel exhaustion drops `_flying` without touching
## velocity itself, so the very next `_physics_process` call falls through to the
## ordinary ground/air branch and gravity takes over — a fall, not a stop.
func _fly(delta: float) -> void:
	if _crouching:
		set_crouching(false)

	_flight_fuel.drain(delta)
	if _flight_fuel.is_empty():
		_flying = false
		message.emit("the flying suit is out of fuel")
	else:
		var wish := _flight_wish_direction()
		velocity = velocity.move_toward(wish * FLIGHT_SPEED, FLIGHT_ACCELERATION * delta)

	move_and_slide()


## Forward/back and strafe follow the camera's full look direction, pitch included —
## looking up and holding forward climbs — while jump/crouch add a straight vertical
## component, the same keys that dive and surface while swimming.
func _flight_wish_direction() -> Vector3:
	var input := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	var vertical := 0.0
	if Input.is_action_pressed(&"jump"):
		vertical += 1.0
	if Input.is_action_pressed(&"crouch"):
		vertical -= 1.0

	if input.is_zero_approx() and vertical == 0.0:
		return Vector3.ZERO

	var basis := _camera.global_transform.basis if _camera != null else transform.basis
	var wish := basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * vertical
	return Vector3.ZERO if wish.is_zero_approx() else wish.normalized()


## Movement input as a unit vector in world space, relative to where the player is
## facing.
func _wish_direction() -> Vector3:
	var input := Input.get_vector(
			&"move_left", &"move_right", &"move_forward", &"move_back")
	if input.is_zero_approx():
		return Vector3.ZERO
	# Godot's -Z is forward, and get_vector's Y axis is forward/back.
	var direction := (transform.basis * Vector3(input.x, 0.0, input.y))
	direction.y = 0.0
	return direction.normalized()


func current_speed() -> float:
	if _swimming:
		return SWIM_SPEED
	if _crouching:
		return CROUCH_SPEED
	if _is_sprinting():
		return SPRINT_SPEED
	return WALK_SPEED


## Sprinting requires the input, contact with the ground, and stamina left. An exhausted
## player drops to a walk rather than sprinting on fumes.
func _is_sprinting() -> bool:
	return Input.is_action_pressed(&"sprint") \
			and is_on_floor() \
			and not _crouching \
			and not _swimming \
			and _stats.can_sprint()


func _update_crouch(_delta: float) -> void:
	var wants_crouch := Input.is_action_pressed(&"crouch")
	if wants_crouch == _crouching:
		return
	if not wants_crouch and not _has_headroom():
		return  # stuck under something; stay down
	set_crouching(wants_crouch)


func set_crouching(crouching: bool) -> void:
	_crouching = crouching
	var height := CROUCH_HEIGHT if crouching else STAND_HEIGHT
	if _capsule != null:
		_capsule.height = height
	if _collision != null:
		_collision.position.y = height * 0.5
	if _camera != null:
		_camera.position.y = CROUCH_EYE_HEIGHT if crouching else STAND_EYE_HEIGHT


func _has_headroom() -> bool:
	var needed := STAND_HEIGHT - CROUCH_HEIGHT
	return not test_move(global_transform, Vector3.UP * needed)


## Lifts the body onto a ledge when one is blocking the way and is low enough to
## step. Returns true when a step was taken.
##
## Runs before move_and_slide so the horizontal move happens from the raised
## position, and floor snapping settles the player back down onto the terrace.
func try_step_up(motion: Vector3) -> bool:
	if not is_on_floor():
		return false

	var horizontal := Vector3(motion.x, 0.0, motion.z)
	if horizontal.length() < 0.0001:
		return false

	# Only intervene when something is genuinely in the way.
	if not test_move(global_transform, horizontal):
		return false

	# Would the same move be clear from a step higher up? If not, this is a wall,
	# not a step, and refusing it is what makes tall terraces into cliffs.
	var lifted := global_transform
	lifted.origin.y += MAX_STEP_HEIGHT
	if test_move(lifted, horizontal):
		return false

	# There has to be ground to land on, or the player would be stepping into air.
	var landed := lifted
	landed.origin += horizontal
	if not test_move(landed, Vector3.DOWN * (MAX_STEP_HEIGHT + 0.05)):
		return false

	global_position.y += MAX_STEP_HEIGHT
	if velocity.y < 0.0:
		velocity.y = 0.0
	return true
