extends RefCounted

## A street's speed limit is the `speed` field on its road, in mph. A road without one
## uses the ordinary city limit.

const DEFAULT_MPH := 30
const _MPH := 2.2369362920544
const DEFAULT_MPS := DEFAULT_MPH / _MPH


static func mph_of(road: Dictionary) -> int:
	var raw: Variant = road.get("speed", DEFAULT_MPH)
	if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
		return DEFAULT_MPH
	var mph := int(raw)
	if mph <= 0:
		return DEFAULT_MPH
	return mph


static func mps_of(road: Dictionary) -> float:
	return float(mph_of(road)) / _MPH
