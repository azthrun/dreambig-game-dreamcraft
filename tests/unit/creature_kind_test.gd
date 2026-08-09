extends "res://tests/test_case.gd"
## Tests the species table: the difficulty curve, telling the cats apart, and gaits.
##
## These assert on the numbers a player actually meets — how hard a fight is, whether two
## animals look alike — rather than on the shape of the table.

const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const Biome := preload("res://scripts/world/biome.gd")

const CATS: Array[int] = [
	CreatureKind.Kind.LEOPARD,
	CreatureKind.Kind.TIGER,
	CreatureKind.Kind.LION,
]


## Damage a species does per second of sustained contact. Two numbers make a fight, so
## comparing either alone would let a harder animal be a softer one.
func _threat(kind: int) -> float:
	return CreatureKind.attack_damage(kind) \
			/ maxf(CreatureKind.attack_interval(kind), 0.001)


func test_the_three_cats_ascend_in_difficulty() -> void:
	for index in CATS.size() - 1:
		var weaker: int = CATS[index]
		var stronger: int = CATS[index + 1]
		var names := [CreatureKind.name_of(weaker), CreatureKind.name_of(stronger)]
		assert_true(CreatureKind.health(stronger) > CreatureKind.health(weaker),
				"a %s should take more killing than a %s" % names)
		assert_true(_threat(stronger) > _threat(weaker),
				"a %s should hit harder over time than a %s" % names)
		assert_true(CreatureKind.detection_m(stronger)
						> CreatureKind.detection_m(weaker),
				"a %s should notice you from further off than a %s" % names)
		assert_true(CreatureKind.run_speed(stronger)
						> CreatureKind.run_speed(weaker),
				"a %s should run down a player a %s could not" % names)


func test_every_cat_is_more_dangerous_than_the_prey() -> void:
	# The other half of the curve: prey has to stay the safe thing to approach.
	for cat in CATS:
		assert_true(CreatureKind.health(cat) > CreatureKind.health(
						CreatureKind.Kind.DEER),
				"%s should outlast a deer" % CreatureKind.name_of(cat))
		assert_true(CreatureKind.is_predator(cat))
	assert_almost_eq(CreatureKind.attack_damage(CreatureKind.Kind.DEER), 0.0, 0.001,
			"prey does no damage at all, which is what makes it prey")


func test_the_cats_are_told_apart_by_colour_and_pattern() -> void:
	# At a distance the silhouette is too small to judge, so colour and pattern carry
	# the identification — and no two may rely on the same one.
	var patterns := {}
	for cat in CATS:
		var pattern: Array = [CreatureKind.markings(cat), CreatureKind.has_mane(cat)]
		assert_not_has(patterns, pattern,
				"%s wears the same coat as %s" % [CreatureKind.name_of(cat),
						patterns.get(pattern, "")])
		patterns[pattern] = CreatureKind.name_of(cat)

	assert_eq(CreatureKind.markings(CreatureKind.Kind.TIGER),
			CreatureKind.Marking.STRIPES, "the tiger is the striped one")
	assert_true(CreatureKind.has_mane(CreatureKind.Kind.LION),
			"the lion is the one with the mane")
	assert_false(CreatureKind.has_mane(CreatureKind.Kind.TIGER))


func test_the_cats_differ_in_colour_as_well_as_pattern() -> void:
	# Pattern alone is a few pixels at range; the body colour is the whole animal.
	for index in CATS.size():
		for other in range(index + 1, CATS.size()):
			var a: Color = CreatureKind.body(CATS[index]).get("body_colour")
			var b: Color = CreatureKind.body(CATS[other]).get("body_colour")
			var difference := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			# 0.3 rather than something token: the leopard and lion tans first chosen
			# were 0.1 apart, which is two shades of the same animal.
			assert_true(difference > 0.3,
					"%s and %s are near enough the same colour (%.2f apart)"
							% [CreatureKind.name_of(CATS[index]),
									CreatureKind.name_of(CATS[other]), difference])


func test_each_cat_is_visibly_larger_than_the_last() -> void:
	for index in CATS.size() - 1:
		var smaller: Dictionary = CreatureKind.body(CATS[index])
		var larger: Dictionary = CreatureKind.body(CATS[index + 1])
		assert_true(float(larger.get("length", 0.0))
						> float(smaller.get("length", 0.0)),
				"%s should be the longer animal" % CreatureKind.name_of(CATS[index + 1]))
		assert_true(float(larger.get("height", 0.0))
						> float(smaller.get("height", 0.0)),
				"%s should be the taller animal" % CreatureKind.name_of(CATS[index + 1]))


func test_every_species_moves_on_its_own_clips() -> void:
	# One shared gait would make three differently sized cats read as one animal
	# scaled up, which is the thing the whole cuboid style is worst at hiding.
	var seen := {}
	for kind in CreatureKind.ALL:
		var gait: Dictionary = CreatureKind.gait(kind)
		assert_false(gait.is_empty(),
				"%s has no gait of its own" % CreatureKind.name_of(kind))
		var signature: Array = [gait.get("walk_swing"), gait.get("walk_cycle"),
				gait.get("run_swing"), gait.get("run_cycle")]
		assert_not_has(seen, signature,
				"%s moves exactly like %s" % [CreatureKind.name_of(kind),
						seen.get(signature, "")])
		seen[signature] = CreatureKind.name_of(kind)
		assert_true(float(gait.get("run_cycle", 1.0))
						< float(gait.get("walk_cycle", 0.0)),
				"a run has to cycle faster than a walk")


func test_heavier_cats_take_longer_shallower_strides() -> void:
	for index in CATS.size() - 1:
		var lighter: Dictionary = CreatureKind.gait(CATS[index])
		var heavier: Dictionary = CreatureKind.gait(CATS[index + 1])
		assert_true(float(heavier.get("walk_cycle", 0.0))
						> float(lighter.get("walk_cycle", 0.0)),
				"the heavier animal should tread more slowly")
		assert_true(float(heavier.get("walk_swing", 0.0))
						< float(lighter.get("walk_swing", 0.0)),
				"and swing its legs less far")


func test_the_dangerous_species_are_the_rare_ones() -> void:
	assert_true(CreatureKind.max_population(CreatureKind.Kind.DEER)
					> CreatureKind.max_population(CreatureKind.Kind.LEOPARD),
			"prey should outnumber predators")
	for index in CATS.size() - 1:
		assert_true(CreatureKind.max_population(CATS[index + 1])
						< CreatureKind.max_population(CATS[index]),
				"a %s should be rarer than a %s" % [
						CreatureKind.name_of(CATS[index + 1]),
						CreatureKind.name_of(CATS[index])])
	for kind in CreatureKind.ALL:
		assert_true(CreatureKind.max_population(kind) > 0,
				"%s declares no cap, so it would never spawn"
						% CreatureKind.name_of(kind))


func test_where_you_go_decides_what_you_meet() -> void:
	# The point of biome weighting: no two land biomes may offer the same roster, or
	# travelling somewhere new would change nothing about the danger.
	var rosters := {}
	for biome in [Biome.Kind.PLAINS, Biome.Kind.FOREST, Biome.Kind.MOUNTAINS]:
		var roster: Array = []
		for kind in CreatureKind.ALL:
			if CreatureKind.lives_in(kind, biome):
				roster.append(kind)
		assert_false(roster.is_empty(),
				"%s is empty of animals" % Biome.name_of(biome))
		assert_not_has(rosters, roster,
				"%s holds the same species as %s" % [Biome.name_of(biome),
						rosters.get(roster, "")])
		rosters[roster] = Biome.name_of(biome)


func test_the_open_beach_holds_no_predators() -> void:
	# The player washes up here and respawns here, so it must not be a place to be
	# ambushed with nothing yet crafted.
	for kind in CreatureKind.ALL:
		if not CreatureKind.is_predator(kind):
			continue
		assert_false(CreatureKind.lives_in(kind, Biome.Kind.BEACH),
				"%s spawns on the respawn beach" % CreatureKind.name_of(kind))
		assert_false(CreatureKind.lives_in(kind, Biome.Kind.OCEAN))


func test_the_boar_is_a_gentle_step_up_from_a_deer() -> void:
	var deer := CreatureKind.Kind.DEER
	var boar := CreatureKind.Kind.BOAR
	assert_true(CreatureKind.health(boar) > CreatureKind.health(deer),
			"the fight has to be worth having")
	# Well short of the real predators: this is an intro to danger, not the danger.
	assert_true(CreatureKind.health(boar) < CreatureKind.health(CreatureKind.Kind.LEOPARD))
	assert_true(CreatureKind.attack_damage(boar) > 0.0,
			"a retaliating boar has to actually be able to hit you")
	assert_true(CreatureKind.attack_damage(boar)
					< CreatureKind.attack_damage(CreatureKind.Kind.LEOPARD),
			"survivable, not as dangerous as a real predator")


func test_the_boar_yields_more_than_a_deer() -> void:
	const ItemKind := preload("res://scripts/items/item_kind.gd")
	var deer_drops := CreatureKind.drops(CreatureKind.Kind.DEER)
	var boar_drops := CreatureKind.drops(CreatureKind.Kind.BOAR)
	assert_true(int(boar_drops.get(ItemKind.Kind.RAW_MEAT, 0))
					> int(deer_drops.get(ItemKind.Kind.RAW_MEAT, 0)),
			"the risk of a counter-attack has to pay for itself")


func test_the_boar_is_denser_in_forest_than_the_deer_is() -> void:
	const Biome := preload("res://scripts/world/biome.gd")
	assert_true(CreatureKind.biome_weight(CreatureKind.Kind.BOAR, Biome.Kind.FOREST)
					> CreatureKind.biome_weight(CreatureKind.Kind.DEER, Biome.Kind.FOREST))
	assert_true(CreatureKind.lives_in(CreatureKind.Kind.BOAR, Biome.Kind.PLAINS))
	assert_true(CreatureKind.lives_in(CreatureKind.Kind.BOAR, Biome.Kind.FOREST))
	assert_false(CreatureKind.lives_in(CreatureKind.Kind.BOAR, Biome.Kind.MOUNTAINS))


func test_only_the_boar_retaliates_among_the_ground_animals() -> void:
	for kind in CreatureKind.ALL:
		var expected := kind == CreatureKind.Kind.BOAR
		assert_eq(CreatureKind.retaliates(kind), expected,
				"%s should%s retaliate" % [CreatureKind.name_of(kind),
						"" if expected else " not"])


func test_the_boar_is_visually_distinct_from_the_deer() -> void:
	# "Stockier, darker, lower to the ground" as three separate, checkable claims.
	var deer_body := CreatureKind.body(CreatureKind.Kind.DEER)
	var boar_body := CreatureKind.body(CreatureKind.Kind.BOAR)

	assert_true(float(boar_body["width"]) > float(deer_body["width"]),
			"stockier: wider relative to its length")
	assert_true(float(boar_body["height"]) < float(deer_body["height"]),
			"lower to the ground: shorter than the deer")

	var deer_colour: Color = deer_body["body_colour"]
	var boar_colour: Color = boar_body["body_colour"]
	var difference := absf(deer_colour.r - boar_colour.r) \
			+ absf(deer_colour.g - boar_colour.g) + absf(deer_colour.b - boar_colour.b)
	assert_true(difference > 0.3, "darker: a real colour difference, not a token one")
	assert_true(boar_colour.r + boar_colour.g + boar_colour.b
					< deer_colour.r + deer_colour.g + deer_colour.b,
			"specifically darker, not just different")
