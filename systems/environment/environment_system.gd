extends Node
## The gameplay-facing view of the world's terrain.
##
## Gameplay asks this system "how high is the ground here?" and "what is the
## ground made of here?". It never touches meshes, colliders or terrain nodes.
##
## Whatever builds the world registers itself as the provider. Today that is a
## procedural mesh; later it can be a sculpted heightmap, a streamed terrain
## plugin or a hand-built level, with no change to any gameplay system.
##
## A provider must implement:
##     func height_at(x: float, z: float) -> float
##     func substrate_at(pos: Vector3) -> Substrate
##     func world_extent() -> float

var _provider: Object = null

## Simple global weather scalar for now; the weather system replaces this later.
## 1.0 = dry and settled, lower = rain washing sign away.
var ground_condition := 1.0

func register_provider(p: Object) -> void:
	_provider = p

func has_provider() -> bool:
	return _provider != null

func height_at(x: float, z: float) -> float:
	if _provider != null and _provider.has_method("height_at"):
		return _provider.height_at(x, z)
	return 0.0

func ground_position(pos: Vector3) -> Vector3:
	return Vector3(pos.x, height_at(pos.x, pos.z), pos.z)

func substrate_at(pos: Vector3) -> Substrate:
	if _provider != null and _provider.has_method("substrate_at"):
		return _provider.substrate_at(pos)
	return Substrate.make(Substrate.Kind.LEAF_LITTER)

func world_extent() -> float:
	if _provider != null and _provider.has_method("world_extent"):
		return _provider.world_extent()
	return 100.0
