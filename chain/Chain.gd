@tool
extends Node3D
@export var link_count: int = 5 :
	get:
		return link_count
	set(value):
		link_count = value
		if is_node_ready():
			_queue_rebuild_bones()

@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var simulator: PhysicalBoneSimulator3D = $Skeleton3D/PhysicalBoneSimulator3D

var link: PhysicalBone3D = null
var ball: PhysicalBone3D = null

const IDENTITY := Transform3D.IDENTITY

#@onready var link: PhysicalBone3D = $LinkSkeleton/PhysicalBoneSimulator3D/Bone
#@onready var mesh: MeshInstance3D = $LinkSkeleton/PhysicalBoneSimulator3D/Bone/Link

var link_offset: Vector3

func _link_spacing(node:PhysicalBone3D) -> float:
	var shape:Shape3D = node.shape_owner_get_shape(0, 0)
	assert(shape, "Unable to find shape")
	
	var capsule := shape as CapsuleShape3D
	if capsule:
		return capsule.height
	
	var sphere := shape as SphereShape3D
	if 	sphere:
		return sphere.radius*2
	
	assert(false, "Unsupported shape type")
	return 0.0
		
	#return mesh.get_aabb().get_longest_axis_size() * 2/3.0

# creates a single virtual bone, as a child of the bone before it.
func _add_bone_to_chain(bone_name: String, rest := Transform3D.IDENTITY) -> int:
	# if the bone doesn't exist, create it.
	#var bone_idx = skeleton.find_bone(bone_name)
	var bone_idx := skeleton.add_bone(bone_name)
	assert(bone_idx!=-1, "Failed to create new bone")
		
	# -1 is "no parent", or the root bone
	skeleton.set_bone_parent(bone_idx, bone_idx - 1)
	
	# our pose is the same as our rest at this point
	skeleton.set_bone_rest(bone_idx, rest)
	skeleton.set_bone_pose(bone_idx, rest)
	
	return bone_idx

func _create_physical_bone(bone_idx: int, link_spacing:float, template: PhysicalBone3D) -> PhysicalBone3D:
	var bone_name := skeleton.get_bone_name(bone_idx)
	assert(bone_idx!=-1, "Unable to find bone")
	
	# create the new PhysicalBone3D, set its bone_name and add it to the Simulator
	var bone: PhysicalBone3D = template.duplicate()
	bone.position = Vector3(0,0,0)
	bone.visible = true
	bone.name = bone_name
	@warning_ignore("unsafe_property_access")
	bone.bone_name = bone_name
	
	return bone

func _queue_rebuild_bones():
	# Remove existing bones, and phy_bones
	_rebuild_bones()

func _clear_bones():
	skeleton.clear_bones()
	
	for child in simulator.get_children():
		if child != link and child != ball:
			simulator.remove_child(child)
			child.queue_free()

func _setup_hinge(bone: PhysicalBone3D, lock: bool = false):
	bone.collision_layer = 0
	bone.collision_mask = 1
	
	bone.joint_rotation = Vector3(0,90,0)
	bone.angular_damp = 1.0
	bone.linear_damp = 0.2
	bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
	bone.set("joint_constraints/angular_limit_enabled", true);
	bone.set("joint_constraints/angular_limit_upper", 45);
	bone.set("joint_constraints/angular_limit_lower", -45);
	bone.set("joint_constraints/angular_limit_bias", 0.3)
	bone.set("joint_constraints/angular_limit_softness", 0.9)
	bone.set("joint_constraints/angular_limit_relaxation", 1.0)
	
	# axis lock
	bone.axis_lock_linear_x = lock
	bone.axis_lock_linear_y = lock
	bone.axis_lock_linear_z = lock
	
	#bone.axis_lock_angular_x = lock
	bone.axis_lock_angular_y = lock
	#bone.axis_lock_angular_z = lock
	

func _rebuild_bones():
	# how tall is the chain link?
	assert(link, "Link not set")
	assert(ball, "Ball not set")
	
	# prevent null access on editor refresh
	if not is_node_ready() or not link or not ball:
		return

	# Remove existing bones, and phy_bones
	_clear_bones()

	# attach template
	var bone_idx := _add_bone_to_chain("Link",  IDENTITY)
	var link_spacing := _link_spacing(link)
	link.body_offset = IDENTITY.translated(Vector3(0,-link_spacing/2,0))
	#link.joint_offset = IDENTITY.translated(Vector3(0,-link_spacing/2,0))
	_setup_hinge(link, true)

	# Creat the rest of the links
	for n in range(1, link_count):	# Head is bone 0, so start at 1
		# create virtual bone first	
		# set transforms for new nodes, transforms are relative to previous bone
		var bone_xform := IDENTITY \
			.translated(Vector3(0,-link_spacing,0)) \
			.rotated(Vector3.UP, PI/2.0)
		bone_idx = _add_bone_to_chain("Link" + str(n), bone_xform)

		# creat the physical bone next, and link it with the name
		var new_link := _create_physical_bone(bone_idx, link_spacing, link)
		_setup_hinge(new_link)
		
		simulator.add_child(new_link)
		assert(new_link.get_bone_id()>=0, "Unassigned bone")

	# Attach the ball
	if ball:
		var ball_spacing = _link_spacing(ball)
		var ball_xform := IDENTITY.translated(Vector3(0, -link_spacing, 0))
		bone_idx = _add_bone_to_chain("Ball", ball_xform)
		
		ball.transform = IDENTITY
		ball.body_offset = IDENTITY.translated(Vector3(0,-ball_spacing/2,0))
		_setup_hinge(ball)
	
	skeleton.force_update_bone_child_transform(0)
	var bones := skeleton.get_concatenated_bone_names();
	print(bones)
	
	# rebuild transforms
	if Engine.is_editor_hint():
		simulator.update_gizmos()
		skeleton.update_gizmos()
	#skeleton.force_update_bone_child_transform(0)


# Called when the node enters the scene tree for the first time.
func _ready():
	link = find_child("LinkTemplate")
	ball = find_child("BallTemplate")
	
	_rebuild_bones()
	
	if not Engine.is_editor_hint():
		# Enable simulation
		skeleton.force_update_bone_child_transform(0)
		simulator.physical_bones_start_simulation()

# tooling
func _get_configuration_warnings():
	var warnings:Array[String] = []
	
	if is_node_ready():
		if not link:
			warnings.append("LinkTemplate not found")
		else:
			if link.collision_mask & link.collision_layer != 0:
				warnings.append("Self Collision in LinkTemplate detected.")
			
		if not ball:
			warnings.append("BallTemplate not found")
		else:
			if ball.collision_mask & ball.collision_layer != 0:
				warnings.append("Self Collision in BallTemplate detected.")

	return warnings
	
