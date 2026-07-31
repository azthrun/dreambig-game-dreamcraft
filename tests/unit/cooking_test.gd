extends "res://tests/test_case.gd"
## Tests cooking and hide armour: the two things that turn a kill into survival.

const Campfire := preload("res://scripts/world/props/campfire.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const Inventory := preload("res://scripts/items/inventory.gd")
const TemperatureModel := preload("res://scripts/world/temperature_model.gd")
const Weather := preload("res://scripts/world/weather_model.gd")
const Biome := preload("res://scripts/world/biome.gd")
const SurvivalStats := preload("res://scripts/player/survival_stats.gd")

var _made: Array[Node] = []


func after_each() -> void:
	for node in _made:
		if is_instance_valid(node):
			node.free()
	_made.clear()


func _fire() -> Node3D:
	var fire: Node3D = Campfire.new()
	_made.append(fire)
	# _ready has not run outside the tree, so build the rack and light it explicitly.
	fire._build()
	fire.light(Campfire.INITIAL_FUEL_SECONDS)
	return fire


func test_raw_meat_can_be_put_on_a_lit_fire() -> void:
	var fire := _fire()
	assert_eq(fire.add_raw_meat(2), 2)
	assert_eq(fire.cooking_count(), 2)
	assert_false(fire.is_cooked(), "it should not be done instantly")


func test_a_dead_fire_refuses_meat() -> void:
	# Refusing rather than accepting silently: the meat must not vanish into a cold fire.
	var fire := _fire()
	fire.tick(Campfire.INITIAL_FUEL_SECONDS + 1.0)
	assert_false(fire.is_burning())
	assert_eq(fire.add_raw_meat(2), 0)
	assert_eq(fire.cooking_count(), 0)


func test_a_busy_fire_refuses_more_meat() -> void:
	var fire := _fire()
	fire.add_raw_meat(2)
	assert_eq(fire.add_raw_meat(3), 0, "one batch at a time")
	assert_eq(fire.cooking_count(), 2)


func test_meat_cooks_after_the_configured_time() -> void:
	var fire := _fire()
	fire.add_raw_meat(1)
	fire.tick(Campfire.COOK_SECONDS * 0.5)
	assert_false(fire.is_cooked(), "still raw at the halfway point")
	fire.tick(Campfire.COOK_SECONDS * 0.5 + 0.1)
	assert_true(fire.is_cooked())
	assert_false(fire.is_burnt())


func test_cooked_meat_appears_on_the_rack_to_be_taken() -> void:
	# The rack is the corpse's Lootable, so taking food off a fire is the same verb and
	# the same code as looting a kill.
	var fire := _fire()
	fire.add_raw_meat(2)
	fire.tick(Campfire.COOK_SECONDS + 0.1)

	var inventory: RefCounted = Inventory.new()
	var taken: Dictionary = fire.rack().loot(inventory)
	assert_eq(int(taken.get(ItemKind.Kind.COOKED_MEAT, 0)), 2)
	assert_eq(inventory.total_of(ItemKind.Kind.COOKED_MEAT), 2)
	assert_eq(fire.cooking_count(), 0, "the fire should be free again")


func test_nothing_can_be_taken_while_it_is_still_cooking() -> void:
	var fire := _fire()
	fire.add_raw_meat(1)
	fire.tick(Campfire.COOK_SECONDS * 0.4)
	assert_false(fire.rack().can_loot(), "half-cooked meat is not ready")


func test_meat_left_too_long_burns() -> void:
	var fire := _fire()
	fire.add_raw_meat(1)
	fire.tick(Campfire.BURN_SECONDS + 0.1)
	assert_true(fire.is_burnt())

	var inventory: RefCounted = Inventory.new()
	fire.rack().loot(inventory)
	assert_eq(inventory.total_of(ItemKind.Kind.COOKED_MEAT), 0)
	assert_eq(inventory.total_of(ItemKind.Kind.BURNT_MEAT), 1)


func test_the_burn_window_is_forgiving() -> void:
	# Losing a kill because you looked away feels worse than a fire that forgives you.
	var window := Campfire.BURN_SECONDS - Campfire.COOK_SECONDS
	assert_true(window >= Campfire.COOK_SECONDS * 0.5,
			"there should be real time to collect, got %.0fs" % window)


func test_cooking_is_worth_the_fire_it_costs() -> void:
	assert_true(ItemKind.nutrition(ItemKind.Kind.COOKED_MEAT)
			> ItemKind.nutrition(ItemKind.Kind.RAW_MEAT) * 2.0,
			"cooked meat should be markedly better than raw")
	assert_true(ItemKind.nutrition(ItemKind.Kind.BURNT_MEAT)
			< ItemKind.nutrition(ItemKind.Kind.RAW_MEAT),
			"burning it should be worse than not cooking at all")


func test_raw_meat_costs_health_and_cooked_meat_does_not() -> void:
	assert_true(ItemKind.health_cost(ItemKind.Kind.RAW_MEAT) > 0.0)
	assert_almost_eq(ItemKind.health_cost(ItemKind.Kind.COOKED_MEAT), 0.0, 0.001)
	assert_almost_eq(ItemKind.health_cost(ItemKind.Kind.BERRIES), 0.0, 0.001,
			"foraged food should not make you ill")


func test_eating_raw_meat_feeds_you_but_hurts() -> void:
	var stats: RefCounted = SurvivalStats.new()
	stats.tick(300.0, false)
	var hunger_before: float = stats.hunger()
	var health_before: float = stats.health()

	stats.eat(ItemKind.nutrition(ItemKind.Kind.RAW_MEAT))
	stats.damage(ItemKind.health_cost(ItemKind.Kind.RAW_MEAT))

	assert_true(stats.hunger() < hunger_before, "it should still feed you")
	assert_true(stats.health() < health_before, "and still cost you")


func test_hide_armour_is_wearable_and_nothing_else_is() -> void:
	assert_true(ItemKind.is_wearable(ItemKind.Kind.HIDE_ARMOUR))
	for item in [ItemKind.Kind.WOOD, ItemKind.Kind.STONE, ItemKind.Kind.RAW_MEAT,
			ItemKind.Kind.STONE_TOOL, ItemKind.Kind.CAMPFIRE]:
		assert_false(ItemKind.is_wearable(item),
				"%s should not be wearable" % ItemKind.name_of(item))


func test_armour_measurably_raises_the_temperature() -> void:
	var bare := TemperatureModel.temperature_c(
			Biome.Kind.PLAINS, 20, 0.0, Weather.State.RAIN, false)
	var clothed := TemperatureModel.temperature_c(
			Biome.Kind.PLAINS, 20, 0.0, Weather.State.RAIN, false, 0.0,
			ItemKind.insulation(ItemKind.Kind.HIDE_ARMOUR))
	assert_almost_eq(clothed - bare,
			ItemKind.insulation(ItemKind.Kind.HIDE_ARMOUR), 0.001)
	assert_true(clothed > bare)


func test_armour_alone_can_turn_a_damaging_night_survivable() -> void:
	# Armour is the third answer to cold, alongside shelter and fire, so it has to do
	# something on its own rather than only in combination.
	var insulation: float = ItemKind.insulation(ItemKind.Kind.HIDE_ARMOUR)
	# Modest altitude on an overcast night: 3.3 C, just the wrong side of the threshold.
	# Sea level would have been 6 C and not cold at all, which would have made this test
	# pass while proving nothing.
	var exposed := TemperatureModel.temperature_c(
			Biome.Kind.PLAINS, 25, 0.0, Weather.State.OVERCAST, false)
	assert_true(TemperatureModel.is_cold(exposed),
			"the scenario must be cold without it, got %.1f" % exposed)
	var clothed := TemperatureModel.temperature_c(
			Biome.Kind.PLAINS, 25, 0.0, Weather.State.OVERCAST, false, 0.0,
			insulation)
	assert_false(TemperatureModel.is_cold(clothed),
			"armour should carry that night, got %.1f" % clothed)


func test_armour_is_weaker_than_shelter_or_fire() -> void:
	# It should help everywhere without making the other two pointless.
	const CampfireScript := preload("res://scripts/world/props/campfire.gd")
	var insulation: float = ItemKind.insulation(ItemKind.Kind.HIDE_ARMOUR)
	assert_true(insulation < TemperatureModel.SHELTER_BONUS_C,
			"shelter should beat clothing")
	assert_true(insulation < CampfireScript.HEAT_STRENGTH_C,
			"a fire should beat clothing")
	assert_true(insulation > 0.0)
