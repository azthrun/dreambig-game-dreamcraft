extends RefCounted
## Every species, and the numbers that make one different from another.
##
## One table, so a creature's speed, health, drops and where it lives are stated once.
## The ground animals share a body plan and differ only by these values, which is what
## makes adding the next one an entry rather than a new file.

const Biome := preload("res://scripts/world/biome.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

enum Kind {
	DEER,
	BOAR,
	LEOPARD,
	TIGER,
	LION,
	DRAGON,
}

## Prey flee; predators hunt. The brain is chosen from this rather than from the species,
## so a new prey animal needs no new behaviour.
enum Role { PREY, PREDATOR }

## Coat pattern. Three cats of similar shape have to be told apart at a distance, and
## the pattern is what does it once the silhouette is too small to judge.
enum Marking { NONE, SPOTS, STRIPES }

const SPECIES := {
	Kind.DEER: {
		"name": "deer",
		"role": Role.PREY,
		"health": 30.0,
		"walk_speed": 2.2,
		"run_speed": 8.4,
		## How far off it notices the player standing upright.
		"detection_m": 26.0,
		"body": {
			"height": 1.5, "length": 1.7, "width": 0.7,
			"body_colour": Color(0.55, 0.38, 0.22),
			"head_colour": Color(0.48, 0.32, 0.18),
			"leg_colour": Color(0.34, 0.23, 0.13),
		},
		"drops": {ItemKind.Kind.RAW_MEAT: 2, ItemKind.Kind.HIDE: 1},
		## Relative spawn weight per biome. Absent means it does not live there.
		"biomes": {
			Biome.Kind.PLAINS: 1.0,
			Biome.Kind.FOREST: 0.7,
		},
		## Most of the island's animals: prey has to be the common sight, or the
		## predators have nothing to hunt and the player nothing to eat. Deliberately
		## below the total, so filling the plains with deer cannot crowd the cats out
		## of the places that are left.
		"max_population": 40,
		## Light and quick: a short, fast stride with plenty of swing.
		"gait": {
			"walk_swing": 24.0, "run_swing": 46.0,
			"walk_cycle": 0.82, "run_cycle": 0.38,
		},
	},
	Kind.BOAR: {
		"name": "boar",
		"role": Role.PREY,
		## Enough more than a deer's 30 that the fight is worth having, well short of a
		## leopard's 55 — this is a gentle intro to danger, not the real thing.
		"health": 42.0,
		"walk_speed": 2.0,
		"run_speed": 7.6,
		## Less flighty than a deer: it does not notice you from quite as far.
		"detection_m": 21.0,
		## Read only while retaliating — see `retaliates` below. Deliberately mild: a
		## boar has to be survivable to fight, or "gentle intro to danger" is a lie.
		"attack_damage": 8.0,
		"attack_interval": 1.6,
		## The one thing that makes this species different from a deer mechanically:
		## cornered or struck, it turns and fights instead of only running. Read by
		## `PreyBrain`, which every other prey animal shares unchanged.
		"retaliates": true,
		"body": {
			## Lower to the ground and stockier than the deer it stands beside —
			## shorter, wider, and noticeably heavier-looking despite the smaller frame.
			"height": 1.05, "length": 1.55, "width": 0.92,
			## Dark rather than tan: nothing else on the island reads this close to
			## black, which is what tells it apart from a deer at a glance before the
			## proportions do.
			"body_colour": Color(0.20, 0.15, 0.11),
			"head_colour": Color(0.16, 0.12, 0.09),
			"leg_colour": Color(0.10, 0.08, 0.06),
			## A pair of tusks are the one feature the deer has nothing like, so a boar
			## reads as a boar head-on — which is exactly the angle a player sees it
			## from once it turns to fight.
			"tusks": true,
			"tusk_colour": Color(0.88, 0.85, 0.76),
		},
		## Double the deer's, so a hunt that risks a counter-attack pays for the risk.
		"drops": {ItemKind.Kind.RAW_MEAT: 4, ItemKind.Kind.HIDE: 2},
		## Forest first — denser there than the deer's own 0.7 — with plains too, so
		## the two prey species overlap rather than sorting the island between them.
		"biomes": {
			Biome.Kind.PLAINS: 0.6,
			Biome.Kind.FOREST: 0.9,
		},
		"max_population": 20,
		## Heavier tread than the deer: shorter swing, slower cycle.
		"gait": {
			"walk_swing": 19.0, "run_swing": 38.0,
			"walk_cycle": 0.95, "run_cycle": 0.44,
		},
	},
	Kind.LEOPARD: {
		"name": "leopard",
		"role": Role.PREDATOR,
		## Roughly two stone-tool hits more than a deer: a real fight without a stalemate.
		"health": 55.0,
		"walk_speed": 2.6,
		"run_speed": 9.6,
		## Sees further than a deer notices you, so it finds you before you find it.
		"detection_m": 30.0,
		"attack_damage": 14.0,
		"attack_interval": 1.3,
		"body": {
			"height": 1.05, "length": 1.9, "width": 0.66,
			"body_colour": Color(0.78, 0.62, 0.30),
			"head_colour": Color(0.72, 0.56, 0.26),
			"leg_colour": Color(0.62, 0.48, 0.22),
			## Spots are what make it read as a leopard rather than a tan deer.
			"markings": Marking.SPOTS,
			"marking_colour": Color(0.20, 0.15, 0.10),
		},
		"drops": {ItemKind.Kind.RAW_MEAT: 3, ItemKind.Kind.HIDE: 2},
		"biomes": {
			Biome.Kind.FOREST: 1.0,
		},
		## The one predator the player is expected to meet early, so it is the least
		## rare of the three cats.
		"max_population": 12,
		"gait": {
			"walk_swing": 22.0, "run_swing": 42.0,
			"walk_cycle": 0.9, "run_cycle": 0.42,
		},
	},
	Kind.TIGER: {
		"name": "tiger",
		"role": Role.PREDATOR,
		## Half again the leopard's, so a fight that was winnable with a stone tool is
		## not winnable with the same kit.
		"health": 85.0,
		"walk_speed": 2.8,
		"run_speed": 10.0,
		"detection_m": 34.0,
		"attack_damage": 20.0,
		"attack_interval": 1.25,
		"body": {
			## Visibly bigger than a leopard from across a clearing, which is the only
			## warning the player gets before it is in charge range.
			"height": 1.3, "length": 2.3, "width": 0.82,
			"body_colour": Color(0.86, 0.44, 0.11),
			"head_colour": Color(0.80, 0.40, 0.10),
			"leg_colour": Color(0.70, 0.34, 0.08),
			"markings": Marking.STRIPES,
			"marking_colour": Color(0.10, 0.07, 0.05),
		},
		"drops": {ItemKind.Kind.RAW_MEAT: 4, ItemKind.Kind.HIDE: 3},
		## Forest first, but it climbs — which is what puts a predator on the way to
		## the mountains rather than only in the trees.
		"biomes": {
			Biome.Kind.FOREST: 0.55,
			Biome.Kind.MOUNTAINS: 0.8,
		},
		"max_population": 7,
		## Heavier than a leopard: a longer, shallower stride.
		"gait": {
			"walk_swing": 19.0, "run_swing": 37.0,
			"walk_cycle": 1.02, "run_cycle": 0.5,
		},
	},
	Kind.LION: {
		"name": "lion",
		"role": Role.PREDATOR,
		## The top of the ground roster. Bare hands are not a plan against this.
		"health": 120.0,
		"walk_speed": 3.0,
		"run_speed": 10.4,
		"detection_m": 38.0,
		"attack_damage": 26.0,
		"attack_interval": 1.2,
		"body": {
			"height": 1.4, "length": 2.45, "width": 0.9,
			## Pale sand rather than the leopard's gold: the first colours tried were
			## close enough to each other that only the spots told them apart.
			"body_colour": Color(0.87, 0.75, 0.53),
			"head_colour": Color(0.83, 0.71, 0.49),
			"leg_colour": Color(0.75, 0.63, 0.43),
			## No coat pattern at all: tan, and the mane does the identifying.
			"markings": Marking.NONE,
			"mane": true,
			"mane_colour": Color(0.33, 0.20, 0.09),
		},
		"drops": {ItemKind.Kind.RAW_MEAT: 5, ItemKind.Kind.HIDE: 3},
		## Open ground, where the deer are — and where there is nothing to hide behind.
		"biomes": {
			Biome.Kind.PLAINS: 0.35,
			Biome.Kind.MOUNTAINS: 0.4,
		},
		## The rarest of the three: meeting one should be an event.
		"max_population": 4,
		## Heaviest tread of the three.
		"gait": {
			"walk_swing": 17.0, "run_swing": 33.0,
			"walk_cycle": 1.12, "run_cycle": 0.56,
		},
	},
	## The apex encounter, sequenced with the gadgets rather than with the rest of the
	## bestiary — see SPEC. It never enters the general biome-weighted population roll:
	## no `biomes` entry means `biome_weight` is zero everywhere, so this species is
	## placed only by `dragon_nest.gd`, deliberately, at mountain sites in the island's
	## north. `max_population` is read by that placement as how many nests to try for.
	Kind.DRAGON: {
		"name": "dragon",
		"role": Role.PREDATOR,
		## Far beyond the lion's 120: a fight meant to need firearms and flight, not a
		## stone tool with more swings.
		"health": 450.0,
		## "walk" is the patrol cruise; "run" is the dive.
		"walk_speed": 7.0,
		"run_speed": 16.0,
		## Spots the player from well past a lion's own 38 m — an apex flying predator
		## sees further than anything grounded.
		"detection_m": 70.0,
		"attack_damage": 30.0,
		"attack_interval": 1.6,
		"body": {
			## Substantially larger than the big cats in every dimension, not just
			## scaled up — a lion standing beside this should look like prey.
			"height": 3.2, "length": 7.5, "width": 2.4,
			"body_colour": Color(0.16, 0.30, 0.20),
			"head_colour": Color(0.12, 0.24, 0.16),
			"leg_colour": Color(0.09, 0.17, 0.11),
			## The one feature nothing else on the island has — see `creature_factory.gd`
			## for the wing geometry and its own flap animation.
			"wings": true,
			"wing_colour": Color(0.11, 0.23, 0.15),
		},
		## The best drop table in the game: DRAGON_SCALE exists nowhere else, and every
		## other yield is the largest of its kind — see the drop-table test.
		"drops": {
			ItemKind.Kind.DRAGON_SCALE: 6,
			ItemKind.Kind.HIDE: 5,
			ItemKind.Kind.RAW_MEAT: 10,
		},
		## One or two nests — see `dragon_nest.gd`, which reads this as how many sites to
		## place rather than a population density.
		"max_population": 2,
		## Heavy and slow-legged on the ground; the wings are what do the actual moving.
		"gait": {
			"walk_swing": 14.0, "run_swing": 22.0,
			"walk_cycle": 1.3, "run_cycle": 0.75,
		},
	},
}

## Order matters only for reporting; spawn weighting reads the table, not this list.
const ALL: Array[int] = [
	Kind.DEER, Kind.BOAR, Kind.LEOPARD, Kind.TIGER, Kind.LION, Kind.DRAGON,
]


static func data(kind: int) -> Dictionary:
	return SPECIES.get(kind, {})


static func name_of(kind: int) -> String:
	return String(data(kind).get("name", "unknown"))


static func role(kind: int) -> int:
	return int(data(kind).get("role", Role.PREY))


static func health(kind: int) -> float:
	return float(data(kind).get("health", 10.0))


static func walk_speed(kind: int) -> float:
	return float(data(kind).get("walk_speed", 2.0))


static func run_speed(kind: int) -> float:
	return float(data(kind).get("run_speed", 6.0))


static func detection_m(kind: int) -> float:
	return float(data(kind).get("detection_m", 20.0))


## Damage one strike does, and how long between strikes. Prey have neither, which is
## what makes them prey.
static func attack_damage(kind: int) -> float:
	return float(data(kind).get("attack_damage", 0.0))


static func attack_interval(kind: int) -> float:
	return float(data(kind).get("attack_interval", 1.5))


static func is_predator(kind: int) -> bool:
	return role(kind) == Role.PREDATOR


## Whether this prey species turns and fights when cornered or struck, instead of only
## ever running. Meaningless for a predator, which always fights — read only by
## `PreyBrain`.
static func retaliates(kind: int) -> bool:
	return bool(data(kind).get("retaliates", false))


static func body(kind: int) -> Dictionary:
	return data(kind).get("body", {})


static func drops(kind: int) -> Dictionary:
	return data(kind).get("drops", {})


## Coat pattern, from the body description. Read by the factory only.
static func markings(kind: int) -> int:
	return int(body(kind).get("markings", Marking.NONE))


static func has_mane(kind: int) -> bool:
	return bool(body(kind).get("mane", false))


static func has_wings(kind: int) -> bool:
	return bool(body(kind).get("wings", false))


## Swing angles and cycle times for this species' walk and run clips. A heavier animal
## takes a longer, shallower stride, which is what stops three cats sharing one gait.
static func gait(kind: int) -> Dictionary:
	return data(kind).get("gait", {})


## Most of this species the island will ever hold at once.
##
## Per species rather than only in total, because a total cap alone would let a bad roll
## fill the island with lions. Zero — the default for a species that has not declared one
## — means it never spawns.
static func max_population(kind: int) -> int:
	return int(data(kind).get("max_population", 0))


## Relative likelihood of this species spawning in a biome. Zero means never.
static func biome_weight(kind: int, biome: int) -> float:
	return float(data(kind).get("biomes", {}).get(biome, 0.0))


static func lives_in(kind: int, biome: int) -> bool:
	return biome_weight(kind, biome) > 0.0
