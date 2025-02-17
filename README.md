# Godot Chain Demo

## Skeleton3D does not clean up after object when adding and removing bones
- Reproduced in 4.3, 4.4b3
- Windows 11, Godot-4.4beta3

## Description
There is a bug which prevents dynamically adding and removing bones from a skeleton.

The use case for dynamically constructing skeletons is in creating generative creatures, mechanism, and so on.
For my example, I use a ball and chain simulation with dynamic number of links. The scene componentry builds a chain link up from a link template and a ball template

## Related Issues
Fix error spam at start with Skeleton3D modifiers #102030
https://github.com/godotengine/godot/pull/102030