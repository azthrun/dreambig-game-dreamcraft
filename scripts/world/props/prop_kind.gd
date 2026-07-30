extends RefCounted
## Prop kinds and what each yields when harvested.
##
## Kept separate from placement and construction so nothing needs to depend on either
## just to ask what a prop is worth.

enum Kind {
	TREE,
	ROCK_OUTCROP,
	BERRY_BUSH,
	OVERHANG,
	CAVE_MOUTH,
	THICKET,
}

## What harvesting a prop produces. NONE means the prop is not harvestable.
enum Yield {
	NONE,
	WOOD,
	STONE,
	BERRIES,
}

## Props that give up a resource when harvested.
const HARVESTABLE: Array[int] = [
	Kind.TREE,
	Kind.ROCK_OUTCROP,
	Kind.BERRY_BUSH,
]

## Props that shelter the player from the weather. These yield nothing — they are
## worth something for standing under, not for taking apart.
const COVER: Array[int] = [
	Kind.OVERHANG,
	Kind.CAVE_MOUTH,
	Kind.THICKET,
]

const ALL: Array[int] = [
	Kind.TREE,
	Kind.ROCK_OUTCROP,
	Kind.BERRY_BUSH,
	Kind.OVERHANG,
	Kind.CAVE_MOUTH,
	Kind.THICKET,
]


static func name_of(kind: int) -> String:
	match kind:
		Kind.TREE:
			return "tree"
		Kind.ROCK_OUTCROP:
			return "rock_outcrop"
		Kind.BERRY_BUSH:
			return "berry_bush"
		Kind.OVERHANG:
			return "overhang"
		Kind.CAVE_MOUTH:
			return "cave_mouth"
		Kind.THICKET:
			return "thicket"
	return "unknown"


## The resource this prop gives up. Declared here rather than at the harvest site so
## the harvesting code never needs a per-kind branch.
static func yield_of(kind: int) -> int:
	match kind:
		Kind.TREE:
			return Yield.WOOD
		Kind.ROCK_OUTCROP:
			return Yield.STONE
		Kind.BERRY_BUSH:
			return Yield.BERRIES
	return Yield.NONE


static func yield_name(resource: int) -> String:
	match resource:
		Yield.WOOD:
			return "wood"
		Yield.STONE:
			return "stone"
		Yield.BERRIES:
			return "berries"
	return "none"


## Whether the player is blocked by this prop. Bushes are pushed through; everything
## else has some solid part.
static func is_solid(kind: int) -> bool:
	return kind != Kind.BERRY_BUSH


## Whether standing inside this prop shelters the player from the weather.
##
## Cover exists because cold damage needs counter-play and this game has no building:
## a player caught in a storm must be able to get out of it using the landscape.
static func is_cover(kind: int) -> bool:
	return COVER.has(kind)
