extends RefCounted
## Prop kinds and what each yields when harvested.
##
## Kept separate from placement and construction so nothing needs to depend on either
## just to ask what a prop is worth.

enum Kind {
	TREE,
	ROCK_OUTCROP,
	BERRY_BUSH,
}

## What harvesting a prop produces. NONE means the prop is not harvestable.
enum Yield {
	NONE,
	WOOD,
	STONE,
	BERRIES,
}

const ALL: Array[int] = [
	Kind.TREE,
	Kind.ROCK_OUTCROP,
	Kind.BERRY_BUSH,
]


static func name_of(kind: int) -> String:
	match kind:
		Kind.TREE:
			return "tree"
		Kind.ROCK_OUTCROP:
			return "rock_outcrop"
		Kind.BERRY_BUSH:
			return "berry_bush"
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


## Whether the player is blocked by this prop. Bushes are pushed through; trunks and
## outcrops are not.
static func is_solid(kind: int) -> bool:
	return kind != Kind.BERRY_BUSH
