extends RefCounted
## The six terrain classifications every cell carries.
##
## Kept in its own file so nothing has to depend on the generator just to name a
## biome. Values are stored as bytes in the world grid, so the order here is part of
## the save format once persistence exists — append, never reorder.

enum Kind {
	OCEAN,
	BEACH,
	PLAINS,
	FOREST,
	MOUNTAINS,
	RIVER,
}

const ALL: Array[int] = [
	Kind.OCEAN,
	Kind.BEACH,
	Kind.PLAINS,
	Kind.FOREST,
	Kind.MOUNTAINS,
	Kind.RIVER,
]


static func name_of(kind: int) -> String:
	match kind:
		Kind.OCEAN:
			return "ocean"
		Kind.BEACH:
			return "beach"
		Kind.PLAINS:
			return "plains"
		Kind.FOREST:
			return "forest"
		Kind.MOUNTAINS:
			return "mountains"
		Kind.RIVER:
			return "river"
	return "unknown"


## True for classifications that sit above sea level and can be walked on.
static func is_land(kind: int) -> bool:
	return kind != Kind.OCEAN
