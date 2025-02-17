# Godot Chain Demo

## Skeleton3D/PhysicalBoneSimulator does not clean up internal state when removing bones
- Reproduced in 4.3, 4.4b3
- Windows 11, Godot-4.4beta3

## Description
There is a bug which prevents dynamically removing and then adding bones to a skeleton.

The use case for dynamically constructing skeletons is in creating generative creatures, mechanism, and so on.
For my example, I use a ball and chain simulation with dynamic number of links. The scene componentry builds a chain link up from a link template and a ball template. This repo is a test case for demonstrating the behavior.

The Chain.gd file creates a ball-and-chain simulation with a dynamic number of links that can be changed directly within the editor. It is the only script file of interest for the project.



# Steps to reproduce crash
1. Open project.
2. Open Scene "Chain.tscn". You should see a monkey head on a chain.
3. Select the root node.
4. In the properties panel there is a counter for the number of chain links.
5. Increase the counter by one.

# Results:
Editor segfaults and exits.

# Investigation
Skeleton3D, PhysicalBoneSimulator3D, and PhysicalBone3D all maintain a set of internal caching structures that appear to be there as speed optimizations. These caching structures are not properly kept in sync when removing physical bones or when calling Skeleton3D.clear_bones(). In most cases, this results in numerous errors logged in the console, but on occasion, it can also result in crashes.

This PR is an attempt to reduce those errors and to reduce the conditions which trigger spurious console logging from cache size misses due to stale cache data.

To address this, I included more cache invalidation in `Skeleton3D::clear_bones()`.

I also fixed cache sync problems with the `bone_global_pose_dirty` and `nested_set_offset_to_bone_index` in `Skeleton3D::add_bone(const String &p_name)`.

Many of the logging errors that arrise after removing and adding a bone are due to caches being rebuilt before the `PhysicalBone3D` has been added to the tree. I have moved the cache rebuild to `NOTIFICATION_POST_ENTER_TREE`. This fixes the errors from `_reload_joints`.


## Related Issues
Fix error spam at start with Skeleton3D modifiers #102030
https://github.com/godotengine/godot/pull/102030

NOTE: I'm not terribly familiar with the godot internals and this is my first PR, so extra attention is probably warranted.
