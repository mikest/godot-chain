@tool
extends Node3D
@export var link_count: int = 5 :
	get:
		return link_count
	set(value):
		var new_value: int = max(value, 2)
		if new_value != link_count:
			link_count = new_value
			rebuild = true

@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var simulator: PhysicalBoneSimulator3D = $Skeleton3D/Simulator

var anchor: PhysicalBone3D = null
var link: PhysicalBone3D = null
var ball: PhysicalBone3D = null
var rebuild: bool = true

# creates a single virtual bone, as a child of the bone before it.
func _add_bone_to_chain(bone_name: String, length: float, twist: float) -> int:
	var bone_idx := skeleton.add_bone(bone_name)
	assert(bone_idx!=-1, "Failed to create new bone")
	
	# -1 is "no parent", or the root bone
	skeleton.set_bone_parent(bone_idx, bone_idx - 1)
	
	# our pose is the same as our rest
	# xform is offset relative to parent bone
	var xform := Transform3D.IDENTITY \
			.translated(Vector3(0,-length,0)) \
			.rotated(Vector3.UP, deg_to_rad(twist))
	skeleton.set_bone_rest(bone_idx, xform)
	skeleton.set_bone_pose(bone_idx, xform)
	
	return bone_idx

func _create_physical_bone(bone_name:String, template: PhysicalBone3D) -> PhysicalBone3D:
	# create the new PhysicalBone3D, set its bone_name and add it to the Simulator
	var phy_bone: PhysicalBone3D = template.duplicate()
	
	# two names...
	phy_bone.name = bone_name
	# the name of the Skeleton3D bone we point to is hidden for some reason
	phy_bone.set("bone_name", bone_name)
	
	return phy_bone

func _clear_bones():
	assert(link, "Link missing")
	assert(ball, "Ball missing")
	assert(anchor, "Anchor missing")
	
	# this only clear the logical bones in the skeleton
	skeleton.clear_bones()
	
	# now we need to clear _all_ the auto-generated children
	var children := simulator.get_children(true)
	for child in children:
		# This if statement is looking for the "shadow" bones for when we're in the editor
		# as well as the "real" bones when we're not.
		# This will skip Anchor, Link & Ball
		if child.name.begins_with("@PhysicalBone3D") or child.name.begins_with("Link_"):
			#print("Removing ", child.name)
			simulator.remove_child(child)
			child.queue_free()


func _setup_hinge(bone: PhysicalBone3D, lock: bool = false):
	bone.linear_velocity = Vector3.ZERO
	bone.angular_velocity = Vector3.ZERO
	
	bone.collision_layer = 0
	bone.collision_mask = 1
	
	bone.body_offset = Transform3D.IDENTITY
	bone.joint_offset = Transform3D.IDENTITY
	bone.joint_rotation = Vector3.ZERO #(0,0,deg_to_rad(15))
	bone.angular_damp = 1.0
	bone.linear_damp = 0.2
	bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	
	# BUG: the joint type gets reloaded on change, so we have to set it to none,
	# then set it to the type we want, and _then_ set the properties.
	# if we don't do this the ball, or last bone in the chain, will "detach"
	# because the init states for the PhysicalBoneSimulator don't appear to update correctly
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
	bone.set("joint_constraints/angular_limit_enabled", true);
	bone.set("joint_constraints/angular_limit_upper", 90); #90
	bone.set("joint_constraints/angular_limit_lower", -90); #-90
	bone.set("joint_constraints/angular_limit_bias", 0.3)
	bone.set("joint_constraints/angular_limit_softness", 0.9)
	bone.set("joint_constraints/angular_limit_relaxation", 1.0)
		
	
	# axis lock
	bone.axis_lock_linear_x = lock
	bone.axis_lock_linear_y = lock
	bone.axis_lock_linear_z = lock
	
	bone.axis_lock_angular_x = lock
	bone.axis_lock_angular_y = lock
	bone.axis_lock_angular_z = lock

# returns the height of the collision object attached to the ph_bone
func _link_spacing(node:PhysicalBone3D) -> float:
	var shape:Shape3D = node.shape_owner_get_shape(0, 0)
	assert(shape, "Unable to find shape")
	var spacing: float = 0
	
	var capsule := shape as CapsuleShape3D
	if capsule:
		spacing = capsule.height
	
	var sphere := shape as SphereShape3D
	if 	sphere:
		spacing = sphere.radius*2
	
	assert(spacing, "Unsupported shape type")
	return spacing * 1.0


# returns true if the bones where rebuilt
func _rebuild_bones() -> bool:
	# prevent null access on editor refresh
	if not rebuild or not is_node_ready() or not link or not ball:
		return false

	# Remove existing bones, and phy_bones
	simulator.physical_bones_stop_simulation()
	_clear_bones()

	# Anchor
	_add_bone_to_chain("Anchor",  0, 0)
	var anchor_spacing := _link_spacing(anchor)
	_setup_hinge(anchor, true)
	#simulator.add_child(anchor)
	
	# First Link
	_add_bone_to_chain("Link",  anchor_spacing/2, 0)
	_setup_hinge(link)
	#simulator.add_child(link)

	# Remaining Links
	var link_spacing := _link_spacing(link)
	for n in range(1, link_count):	# Head is bone 0, so start at 1
		var bone_name := "Link_" + str(n)
		
		# creat the physical bone next, and link it with the name
		var new_link := _create_physical_bone(bone_name, link)
		_add_bone_to_chain(bone_name, link_spacing, 90)
		simulator.add_child(new_link)

	# Ball
	# spacing is one link length, not ball length
	_add_bone_to_chain("Ball", link_spacing, 90)
	_setup_hinge(ball)
	
	# Manually update the ball position on resize.
	if Engine.is_editor_hint():
		skeleton.force_update_bone_child_transform(0)
		var xform := skeleton.get_bone_global_pose(skeleton.find_bone("Ball"))
		ball.transform = xform
		ball.force_update_transform()
	
	if not Engine.is_editor_hint():
		simulator.physical_bones_start_simulation()
	print(skeleton.get_concatenated_bone_names())
	return true

# Called when the node enters the scene tree for the first time.
func _ready():
	link = find_child("Link")
	ball = find_child("Ball")
	anchor = find_child("Anchor")
	rebuild = true

# scene update
func _process(_delta: float):
	if rebuild and _rebuild_bones():
		rebuild = false
	pass

# tooling
func _get_configuration_warnings():
	var warnings:Array[String] = []
	
	if is_node_ready():
		if not link:
			warnings.append("Link not found")
		else:
			if link.collision_mask & link.collision_layer != 0:
				warnings.append("Self Collision in LinkTemplate detected.")
			
		if not ball:
			warnings.append("Ball not found")
		else:
			if ball.collision_mask & ball.collision_layer != 0:
				warnings.append("Self Collision in BallTemplate detected.")

	return warnings
	
