extends "res://tests/test_case.gd"
## The dragon's entry in the species table: size, health, wings, and the drop table.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const Biome := preload("res://scripts/world/biome.gd")

const DRAGON := CreatureKind.Kind.DRAGON
const LION := CreatureKind.Kind.LION


func test_the_dragon_is_a_predator_with_the_largest_health_pool() -> void:
	assert_true(CreatureKind.is_predator(DRAGON))
	for kind in CreatureKind.ALL:
		if kind == DRAGON:
			continue
		assert_true(CreatureKind.health(DRAGON) > CreatureKind.health(kind),
				"the dragon should outlast %s" % CreatureKind.name_of(kind))


func test_the_dragon_is_substantially_larger_than_the_lion() -> void:
	var dragon_body := CreatureKind.body(DRAGON)
	var lion_body := CreatureKind.body(LION)
	for dimension in ["height", "length", "width"]:
		var dragon_size := float(dragon_body[dimension])
		var lion_size := float(lion_body[dimension])
		assert_true(dragon_size > lion_size * 1.5,
				"dragon %s (%.1f) is not substantially larger than the lion's (%.1f)"
						% [dimension, dragon_size, lion_size])


func test_only_the_dragon_has_wings() -> void:
	for kind in CreatureKind.ALL:
		var expected := kind == DRAGON
		assert_eq(CreatureKind.has_wings(kind), expected,
				"%s should%s have wings" % [CreatureKind.name_of(kind),
						"" if expected else " not"])


func test_the_dragon_does_not_enter_the_general_biome_roll() -> void:
	# Placed deliberately at nest sites instead — see `dragon_nest.gd`. A biome weight
	# would let the ordinary population system spawn one anywhere mountains occur.
	for biome in Biome.ALL:
		assert_false(CreatureKind.lives_in(DRAGON, biome),
				"the dragon should not live in %s via the general roll"
						% Biome.name_of(biome))


func test_the_dragon_still_declares_a_population_cap() -> void:
	# Read by `dragon_nest.gd` as how many nests to try for, not as a roll cap — but
	# AGENTS.md is clear that no cap means no spawn at all, so it still needs one.
	assert_true(CreatureKind.max_population(DRAGON) > 0)
	assert_true(CreatureKind.max_population(DRAGON) <= 2,
			"one or two dragons, not a population")


func test_the_dragon_has_the_richest_drop_table_in_the_game() -> void:
	var dragon_drops := CreatureKind.drops(DRAGON)
	var dragon_total := 0
	for count in dragon_drops.values():
		dragon_total += int(count)

	for kind in CreatureKind.ALL:
		if kind == DRAGON:
			continue
		var total := 0
		for count in CreatureKind.drops(kind).values():
			total += int(count)
		assert_true(dragon_total > total,
				"the dragon's drop table (%d items) should beat %s's (%d)"
						% [dragon_total, CreatureKind.name_of(kind), total])


func test_dragon_scale_drops_from_nothing_else() -> void:
	for kind in CreatureKind.ALL:
		var expected := kind == DRAGON
		var drops: Dictionary = CreatureKind.drops(kind)
		assert_eq(drops.has(ItemKind.Kind.DRAGON_SCALE), expected,
				"%s should%s drop dragon scale" % [CreatureKind.name_of(kind),
						"" if expected else " not"])


func test_the_dragon_sees_further_and_flies_faster_than_the_lion() -> void:
	# Damage-per-hit is not a comparable number any more — the dragon does not use
	# `attack_damage`/`attack_interval` at all; see `dragon_breath_test.gd` for the
	# fire-breath equivalent of "hits harder than the lion".
	assert_true(CreatureKind.detection_m(DRAGON) > CreatureKind.detection_m(LION))
	assert_true(CreatureKind.run_speed(DRAGON) > CreatureKind.run_speed(LION))


func test_the_dragon_declares_no_per_interval_attack() -> void:
	# Confirms the table entry itself, not just the body's override: a stray
	# `attack_damage` left in the table would be dead data nothing reads.
	assert_almost_eq(CreatureKind.attack_damage(DRAGON), 0.0, 0.001)
