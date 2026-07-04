extends SceneTree


func _initialize() -> void:
	var assets_script := load("res://scripts/autoload/game_assets.gd")
	var audio_script := load("res://scripts/autoload/game_audio.gd")
	var assets: Node = assets_script.new()
	var audio: Node = audio_script.new()
	root.add_child(assets)
	root.add_child(audio)
	assets.name = "GameAssets"
	audio.name = "GameAudio"
	assets.load_manifest()

	var result: Dictionary = {
		"ok": true,
		"checks": [],
		"errors": [],
	}
	_check_asset_manifest(assets, result)
	_check_visual_assets(assets, result)
	_check_audio_assets(audio, result)
	_check_visual_scene(result)

	if result["ok"]:
		print("ASSET_AUDIO_VALIDATION_OK")
		for check in result["checks"]:
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		quit(0)
	else:
		push_error("ASSET_AUDIO_VALIDATION_FAILED")
		for error in result["errors"]:
			push_error(error)
		quit(1)


func _check_asset_manifest(assets: Node, result: Dictionary) -> void:
	_record_check(result, "asset_manifest_loaded", assets.manifest_asset_count() > 100, assets.manifest_asset_count())
	_record_check(result, "license_files_present", assets.missing_license_files().is_empty(), assets.missing_license_files())
	_record_check(result, "manifest_preserves_cc0_license", assets.manifest.get("license", "") == "Creative Commons CC0", assets.manifest.get("license", ""))


func _check_visual_assets(assets: Node, result: Dictionary) -> void:
	var required := [
		"sprites/towers/archer_idle.png",
		"sprites/towers/archer_idle_1.png",
		"sprites/towers/archer_idle_2.png",
		"sprites/enemies/normal.png",
		"sprites/enemies/normal_walk_1.png",
		"sprites/enemies/normal_walk_2.png",
		"sprites/projectiles/archer.png",
		"sprites/terrain/grass.png",
		"sprites/terrain/road.png",
		"sprites/effects/spark.png",
	]
	var missing: Array = []
	for relative_path in required:
		if assets.texture(relative_path) == null:
			missing.append(relative_path)
	_record_check(result, "required_visual_textures_load", missing.is_empty(), missing)
	var missing_status: Dictionary = assets.texture_status("sprites/towers/not_real.png")
	_record_check(result, "missing_texture_reports_fallback", missing_status["fallback"] == true, missing_status)


func _check_audio_assets(audio: Node, result: Dictionary) -> void:
	var build_status: Dictionary = audio.sound_status("sounds/ui/build.wav", 360.0)
	_record_check(result, "build_sound_loads", build_status["loaded"] == true and build_status["fallback"] == false, {"loaded": build_status["loaded"], "fallback": build_status["fallback"]})
	var archer_status: Dictionary = audio.sound_status("sounds/towers/archer.wav", 520.0)
	_record_check(result, "archer_sound_loads", archer_status["loaded"] == true and archer_status["fallback"] == false, {"loaded": archer_status["loaded"], "fallback": archer_status["fallback"]})
	var missing_status: Dictionary = audio.sound_status("sounds/ui/not_real.wav", 440.0)
	_record_check(result, "missing_sound_uses_tone_fallback", missing_status["loaded"] == false and missing_status["fallback"] == true and missing_status["stream"] is AudioStreamWAV, {"loaded": missing_status["loaded"], "fallback": missing_status["fallback"], "stream_type": missing_status["stream"].get_class()})


func _check_visual_scene(result: Dictionary) -> void:
	var scene: PackedScene = load("res://scenes/visuals/asset_sprite_visual.tscn")
	_record_check(result, "asset_visual_scene_loads", scene != null, scene)
	if scene == null:
		return
	var instance := scene.instantiate()
	root.add_child(instance)
	_record_check(result, "visual_scene_has_sprite", instance.get_node_or_null("Sprite2D") != null, instance.get_children().map(func(child): return child.name))
	_record_check(result, "visual_scene_has_animation_player", instance.get_node_or_null("AnimationPlayer") != null, instance.get_children().map(func(child): return child.name))
	var sprite: Sprite2D = instance.get_node_or_null("Sprite2D")
	_record_check(result, "visual_scene_uses_shader_material", sprite != null and sprite.material is ShaderMaterial, sprite.material if sprite != null else null)


func _record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	result["checks"].append({
		"label": label,
		"passed": passed,
		"detail": detail,
	})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(detail)])
