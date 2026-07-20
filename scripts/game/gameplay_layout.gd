class_name GameplayLayout
extends RefCounted


static func metrics(viewport_size: Vector2, map_size: Vector2, ui_width: float, bottom_min_height: float, dock_height: float, padding: float, gap: float) -> Dictionary:
	var mode := "sidebar"
	var map_scale := 1.0
	var map_rect := Rect2(Vector2.ZERO, map_size)
	var dock_rect := Rect2()
	var sidebar_rect := Rect2(Vector2(map_size.x, 0.0), Vector2(ui_width, map_size.y))
	var build_panel_rect := Rect2(sidebar_rect.position + Vector2(8.0, 96.0), Vector2(sidebar_rect.size.x - 16.0, 204.0))
	var wave_panel_rect := Rect2(sidebar_rect.position + Vector2(8.0, 210.0), Vector2(sidebar_rect.size.x - 16.0, 76.0))
	var detail_panel_rect := Rect2(sidebar_rect.position + Vector2(14.0, 304.0), Vector2(sidebar_rect.size.x - 28.0, 190.0))
	var upgrade_panel_rect := Rect2(sidebar_rect.position + Vector2(8.0, 286.0), Vector2(sidebar_rect.size.x - 16.0, 304.0))
	if viewport_size.y >= bottom_min_height:
		mode = "bottom_dock"
		dock_rect = Rect2(Vector2(0.0, viewport_size.y - dock_height), Vector2(viewport_size.x, dock_height))
		var map_area := Rect2(Vector2.ZERO, Vector2(viewport_size.x, max(1.0, dock_rect.position.y)))
		map_scale = max(0.001, min(map_area.size.x / map_size.x, map_area.size.y / map_size.y))
		var scaled_map_size := map_size * map_scale
		map_rect = Rect2(map_area.position + (map_area.size - scaled_map_size) * 0.5, scaled_map_size)
		var panel_height: float = dock_rect.size.y - padding * 2.0
		var build_width: float = min(430.0, max(390.0, viewport_size.x * 0.36))
		var wave_width: float = min(220.0, max(180.0, viewport_size.x * 0.16))
		build_panel_rect = Rect2(dock_rect.position + Vector2(padding, padding), Vector2(build_width, panel_height))
		wave_panel_rect = Rect2(Vector2(build_panel_rect.end.x + gap, dock_rect.position.y + padding), Vector2(wave_width, panel_height))
		detail_panel_rect = Rect2(Vector2(wave_panel_rect.end.x + gap, dock_rect.position.y + padding), Vector2(max(320.0, viewport_size.x - wave_panel_rect.end.x - gap - padding), panel_height))
		upgrade_panel_rect = detail_panel_rect
		sidebar_rect = Rect2()
	return {
		"mode": mode,
		"viewport_size": viewport_size,
		"map_rect": map_rect,
		"map_origin": map_rect.position,
		"map_scale": map_scale,
		"dock_rect": dock_rect,
		"sidebar_rect": sidebar_rect,
		"build_panel_rect": build_panel_rect,
		"shop_panel_rect": build_panel_rect,
		"wave_panel_rect": wave_panel_rect,
		"detail_panel_rect": detail_panel_rect,
		"run_status_panel_rect": detail_panel_rect,
		"upgrade_panel_rect": upgrade_panel_rect,
	}
