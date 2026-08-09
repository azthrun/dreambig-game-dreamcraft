extends "res://tests/test_case.gd"
## Encounter tuning: melee is confined to the one range band the breath cone can always
## reach, firearms are not, a single breath is a real threat rather than chip damage, and
## the dragon is decisively tougher than anything else on the island. Numeric proof
## against the declared constants, the same reasoning `dragon_kind_test.gd` already uses
## for size and health, rather than a played-out fight.

const Brain := preload("res://scripts/creatures/dragon_brain.gd")
const CreatureKind := preload("res://scripts/creatures/creature_kind.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")
const Melee := preload("res://scripts/player/melee.gd")
const SurvivalStats := preload("res://scripts/player/survival_stats.gd")

const DRAGON := CreatureKind.Kind.DRAGON
const LION := CreatureKind.Kind.LION


func test_melee_reach_never_escapes_the_breath_cone() -> void:
	# The structural reason melee alone is not a realistic win: every range a melee
	# fighter can stand at is a range the cone can always reach.
	assert_true(Melee.REACH_M < Brain.BREATH_RANGE_M,
			"melee reach (%.1f m) should be well inside breath range (%.1f m)"
					% [Melee.REACH_M, Brain.BREATH_RANGE_M])


func test_firearms_outrange_the_breath_cone() -> void:
	# The other half: a firearm lets the player fight from a band the cone cannot touch
	# at all, which is what "firearms make it winnable" actually means mechanically.
	assert_true(ItemKind.ranged_reach_m(ItemKind.Kind.PISTOL) > Brain.BREATH_RANGE_M)
	assert_true(ItemKind.ranged_reach_m(ItemKind.Kind.MACHINE_GUN)
			> Brain.BREATH_RANGE_M)


func test_a_single_breath_is_a_serious_threat_not_chip_damage() -> void:
	var stats: RefCounted = SurvivalStats.new()
	var breath_damage := Brain.BREATH_DAMAGE_PER_SECOND * Brain.BREATH_DURATION_SECONDS
	assert_true(breath_damage >= stats.rate("max_health") * 0.25,
			"one breath (%.1f) should cost at least a quarter of max health (%.1f)"
					% [breath_damage, stats.rate("max_health")])


func test_the_dragon_is_decisively_tougher_than_the_lion() -> void:
	assert_true(CreatureKind.health(DRAGON) >= CreatureKind.health(LION) * 2.0,
			"the dragon should be at least twice the lion's health, not just more of it")


func test_the_breath_cooldown_prevents_a_permanent_no_go_zone() -> void:
	# Tuning has to cut both ways: a cone with no cooldown at all would make the whole
	# territory unapproachable rather than a fight with an opening.
	assert_true(Brain.BREATH_COOLDOWN_SECONDS > 0.0)
	assert_true(Brain.BREATH_COOLDOWN_SECONDS > Brain.BREATH_DURATION_SECONDS,
			"there should be more downtime after a breath than the breath itself lasts")


func test_the_telegraph_gives_real_warning_not_an_instant_snap() -> void:
	# If the windup were shorter than a couple of physics decisions, "avoided by moving
	# out of it" would be theoretical — there has to be enough time to actually react.
	assert_true(Brain.TELEGRAPH_SECONDS >= 0.5)
