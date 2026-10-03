extends RefCounted

# A model part is one mesh, regardless of how many colored blocks it contains.
static func make(blocks: Array) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for block in blocks:
		var center: Vector3 = block[0]
		var half: Vector3 = Vector3(block[1]) * 0.5
		var color: Color = block[2]
		var corners := [center + Vector3(-half.x, -half.y, -half.z),
			center + Vector3(half.x, -half.y, -half.z), center + Vector3(half.x, half.y, -half.z),
			center + Vector3(-half.x, half.y, -half.z), center + Vector3(-half.x, -half.y, half.z),
			center + Vector3(half.x, -half.y, half.z), center + Vector3(half.x, half.y, half.z),
			center + Vector3(-half.x, half.y, half.z)]
		for face in [[0, 3, 2, 1], [5, 6, 7, 4], [4, 7, 3, 0], [1, 2, 6, 5], [3, 7, 6, 2], [4, 0, 1, 5]]:
			var normal: Vector3 = (corners[face[1]] - corners[face[0]]).cross(corners[face[2]] - corners[face[0]]).normalized()
			for index in [0, 1, 2, 0, 2, 3]:
				surface.set_color(color)
				surface.set_normal(normal)
				surface.add_vertex(corners[face[index]])
	var node := MeshInstance3D.new()
	node.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	return node


static func block(center: Vector3, size: Vector3, color: Color) -> Array:
	return [center, size, color]
