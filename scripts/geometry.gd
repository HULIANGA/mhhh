class_name FieldGeometry
extends RefCounted
## Small mesh helpers for the replaceable M1 placeholder art.

static func material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.88
	if emission > 0.0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = emission
	return result

static func box(parent: Node3D, dimensions: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return instance(parent, mesh, at, mat)

static func instance(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	parent.add_child(visual)
	visual.position = at
	return visual

static func ring(parent: Node3D, radius: float, width: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - width
	mesh.outer_radius = radius
	mesh.rings = 40
	mesh.ring_segments = 6
	return instance(parent, mesh, at, mat)

