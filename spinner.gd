extends Node3D

@export var speed: float = 1.0

func _physics_process(delta):
	self.rotate_y(delta * speed)
