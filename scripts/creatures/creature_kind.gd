extends RefCounted
## Every species, and the numbers that make one different from another.
##
## One table, so a creature's speed, health, drops and where it lives are stated once.
## The five ground animals share a body plan and differ only by these values, which is
## what makes adding the next one an entry rather than a new file.

const Biome := preload("res://scripts/world/biome.gd")
const ItemKind := preload("res://scripts/items/item_kind.gd")

enum Kind {
	DEER,
	BOAR,
	LEOPARD,
	TIGER,
	LION,
}

## Prey flee; predators hunt. The brain is chosen from this rather than from the species,
## so a new prey animal needs no new behaviour.
enum Role { PREY, PREDATOR }

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
			"spots": true,
			"spot_colour": Color(0.20, 0.15, 0.10),
		},
		"drops": {ItemKind.Kind.RAW_MEAT: 3, ItemKind.Kind.HIDE: 2},
		"biomes": {
			Biome.Kind.FOREST: 1.0,
		},
	},
}

const ALL: Array[int] = [Kind.DEER, Kind.LEOPARD]


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


static func body(kind: int) -> Dictionary:
	return data(kind).get("body", {})


static func drops(kind: int) -> Dictionary:
	return data(kind).get("drops", {})


## Relative likelihood of this species spawning in a biome. Zero means never.
static func biome_weight(kind: int, biome: int) -> float:
	return float(data(kind).get("biomes", {}).get(biome, 0.0))


static func lives_in(kind: int, biome: int) -> bool:
	return biome_weight(kind, biome) > 0.0
