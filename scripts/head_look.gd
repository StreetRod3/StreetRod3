extends RefCounted

## Turns the driving view with the driver's head. Hold a look and the view eases that far,
## 80° on Q and E, or 165° on Z and C, then comes back when let go. Races
## and the city cruise both use it, on the chase cameras and from the cockpit and bumper.

const _Controller := preload("res://scripts/controller.gd")

## How quickly the head catches the way it is asked to face, in 1/seconds.
const RESPONSE := 10.0

## Positive looks to the right.
var yaw: float = 0.0


func update(delta: float) -> void:
	if delta <= 0.0:
		return
	var target := _Controller.head_yaw()
	# Stay on the short side of a half turn, so a swap from far left to far right passes
	# through straight ahead.
	yaw = lerpf(yaw, target, 1.0 - exp(-RESPONSE * delta))


## `rest` is the camera in the car's space. The head yaws around the car's up axis and stays put.
## A positive turn of this camera's basis looks left, so the stored yaw is applied the other way.
func apply(rest: Transform3D) -> Transform3D:
	if absf(yaw) < 0.0008:
		return rest
	return Transform3D(Basis(Vector3.UP, -yaw) * rest.basis, rest.origin)
