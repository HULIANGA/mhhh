class_name HunterInputFrame
extends RefCounted
## One physics tick of device-independent gameplay intent.

class ButtonState extends RefCounted:
	var pressed: bool = false
	var held: bool = false
	var released: bool = false

## Screen-space axes: +X right, +Y down. Keep analog magnitude, max length 1.
var movement := Vector2.ZERO
## World-space horizontal direction. Zero means keep the current facing.
var aim_direction := Vector3.ZERO
var attack := ButtonState.new()
var charge := ButtonState.new()
var dodge := ButtonState.new()
