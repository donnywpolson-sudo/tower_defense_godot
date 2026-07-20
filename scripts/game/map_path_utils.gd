extends RefCounted


static func points_from_path(raw_path: Array) -> Array:
	var result: Array = []
	for point in raw_path:
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


static func paths_from_map(raw_paths: Variant) -> Array:
	var result: Array = []
	if not raw_paths is Array:
		return result
	for raw_path in raw_paths:
		if not raw_path is Array:
			continue
		var points := points_from_path(raw_path)
		if points.size() >= 2:
			result.append(points)
	return result
