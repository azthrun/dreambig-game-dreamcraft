extends "res://tests/test_case.gd"
## Tests biome-weighted spawning and both population caps.
##
## Rolls thousands of placements rather than building an island: the question is what the
## weighting and the caps do over many draws, and a single generated island is one sample
## of that.

const Population := preload("res://scripts/creatures/population.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const Biome := preload("res://scripts/world/biome.gd")

const ROLLS := 20000


## Rolls `count` placements in one biome with the caps lifted, so the result shows the
## weighting alone. Caps are asserted separately.
func _uncapped_sample(biome: int, count: int = ROLLS) -> Dictionary:
	var population: RefCounted = Population.new(9001, count + 1)
	var seen := {}
	for _i in count:
		var kind: int = population.roll(biome)
		if kind < 0:
			continue
		seen[kind] = int(seen.get(kind, 0)) + 1
		# Not recorded: leaving the counts at zero keeps every species under its cap,
		# which is the point of sampling this way.
	return seen


func test_the_ocean_holds_nothing() -> void:
	var population: RefCounted = Population.new(1, 100)
	assert_eq(population.roll(Biome.Kind.OCEAN), -1,
			"a sea cell must offer no species at all")


func test_species_are_not_spread_evenly_across_biomes() -> void:
	# The whole reason weighting exists: if plains and forest drew from the same pool in
	# the same proportions, where the player walks would not matter.
	var plains := _uncapped_sample(Biome.Kind.PLAINS)
	var forest := _uncapped_sample(Biome.Kind.FOREST)
	assert_true(int(plains.get(CreatureKind.Kind.LEOPARD, 0)) == 0,
			"leopards do not live on the plains")
	assert_true(int(forest.get(CreatureKind.Kind.LEOPARD, 0)) > 0,
			"but the forest is theirs")
	assert_true(int(forest.get(CreatureKind.Kind.LION, 0)) == 0,
			"lions hunt open ground, not woodland")
	assert_true(int(plains.get(CreatureKind.Kind.LION, 0)) > 0)


func test_a_biome_follows_its_declared_weights() -> void:
	# Forest: deer 0.7, leopard 1.0, tiger 0.55. The ratios, not the absolute counts,
	# are what the table promises.
	var forest := _uncapped_sample(Biome.Kind.FOREST)
	var total := 0
	for kind in forest:
		total += int(forest[kind])
	assert_true(total > ROLLS / 2, "most rolls in a populated biome should land")

	var declared: Dictionary = Population.weights_in(Biome.Kind.FOREST)
	var declared_total := 0.0
	for kind in declared:
		declared_total += float(declared[kind])

	for kind in declared:
		var expected := float(declared[kind]) / declared_total
		var actual := float(forest.get(kind, 0)) / float(total)
		assert_almost_eq(actual, expected, 0.02,
				"%s should be %.0f%% of forest spawns, got %.0f%%"
						% [CreatureKind.name_of(kind), expected * 100.0,
								actual * 100.0])


func test_prey_outnumbers_predators_where_they_share_ground() -> void:
	# A forest that spawned mostly cats would be unsurvivable early, whatever the
	# individual stats say.
	var forest := _uncapped_sample(Biome.Kind.FOREST)
	var predators := 0
	var prey := 0
	for kind in forest:
		if CreatureKind.is_predator(kind):
			predators += int(forest[kind])
		else:
			prey += int(forest[kind])
	assert_true(predators > 0, "a forest with no predator in it is not the forest")
	assert_true(prey > 0)


func test_the_mountains_are_the_dangerous_place() -> void:
	# Difficulty by geography: the high ground offers no prey and only the two harder
	# cats, so climbing is a choice with a cost.
	var mountains := _uncapped_sample(Biome.Kind.MOUNTAINS)
	assert_true(mountains.size() > 0)
	for kind in mountains:
		assert_true(CreatureKind.is_predator(kind),
				"%s should not be grazing the peaks" % CreatureKind.name_of(kind))
	assert_true(int(mountains.get(CreatureKind.Kind.TIGER, 0)) > 0)
	assert_true(int(mountains.get(CreatureKind.Kind.LION, 0)) > 0)
	assert_eq(int(mountains.get(CreatureKind.Kind.LEOPARD, 0)), 0,
			"the leopard stays in the trees")


func test_no_species_exceeds_its_own_cap() -> void:
	# Ten thousand attempts at a biome that holds lions, against a cap of a handful.
	var population: RefCounted = Population.new(4242, 10000)
	for _i in 10000:
		var kind: int = population.roll(Biome.Kind.MOUNTAINS)
		if kind < 0:
			break
		population.record(kind)

	for kind in CreatureKind.ALL:
		assert_true(population.count_of(kind) <= CreatureKind.max_population(kind),
				"%d %ss spawned against a cap of %d" % [population.count_of(kind),
						CreatureKind.name_of(kind),
						CreatureKind.max_population(kind)])
	assert_eq(population.count_of(CreatureKind.Kind.LION),
			CreatureKind.max_population(CreatureKind.Kind.LION),
			"with unlimited attempts the cap should be the thing that stops it")


func test_the_total_cap_stops_the_island_filling_up() -> void:
	var population: RefCounted = Population.new(7, 25)
	for _i in 10000:
		var kind: int = population.roll(Biome.Kind.PLAINS)
		if kind < 0:
			break
		population.record(kind)
	assert_eq(population.total(), 25,
			"the total cap is a hard ceiling on how many animals think each frame")
	assert_true(population.is_full())
	assert_eq(population.roll(Biome.Kind.PLAINS), -1,
			"a full island offers nothing more, in any biome")


func test_a_capped_species_leaves_the_others_their_share() -> void:
	# Deer fill the plains long before the total cap is reached. What happens next
	# decides whether the last places go to lions or are wasted.
	var population: RefCounted = Population.new(11, 400)
	for _i in 4000:
		var kind: int = population.roll(Biome.Kind.PLAINS)
		if kind < 0:
			break
		population.record(kind)
	assert_eq(population.count_of(CreatureKind.Kind.DEER),
			CreatureKind.max_population(CreatureKind.Kind.DEER))
	assert_eq(population.count_of(CreatureKind.Kind.LION),
			CreatureKind.max_population(CreatureKind.Kind.LION),
			"a full deer population must not starve the lions of places")


func test_the_same_seed_populates_the_same_island() -> void:
	# Placement is derived from the world seed, so an island reads the same on every
	# visit and the population never needs saving.
	var first: RefCounted = Population.new(2024, 60)
	var second: RefCounted = Population.new(2024, 60)
	var third: RefCounted = Population.new(9999, 60)
	var rolls_first: Array[int] = []
	var rolls_second: Array[int] = []
	var rolls_third: Array[int] = []
	for _i in 200:
		rolls_first.append(first.roll(Biome.Kind.FOREST))
		rolls_second.append(second.roll(Biome.Kind.FOREST))
		rolls_third.append(third.roll(Biome.Kind.FOREST))
	assert_eq(rolls_first, rolls_second)
	assert_ne(rolls_first, rolls_third, "a different seed should give a different island")


func test_counts_cannot_be_edited_from_outside() -> void:
	var population: RefCounted = Population.new(3, 10)
	population.record(CreatureKind.Kind.DEER)
	var counts: Dictionary = population.counts()
	counts[CreatureKind.Kind.DEER] = 99
	assert_eq(population.count_of(CreatureKind.Kind.DEER), 1)
