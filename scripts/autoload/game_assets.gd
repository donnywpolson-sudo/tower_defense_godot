extends Node

const ASSET_ROOT := "res://assets/"
const MANIFEST_PATH := "res://assets/asset_manifest.json"
const LICENSE_PATHS := [
	"res://assets/licenses/kenney_assets.md",
	"res://assets/licenses/sfx_sources.md",
	"res://assets/licenses/sfx_replacement_map.json",
]

var manifest: Dictionary = {}
var texture_cache: Dictionary = {}


func _ready() -> void:
	load_manifest()


func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		manifest = {}
		return manifest
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		manifest = {}
		return manifest
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	manifest = parsed if parsed is Dictionary else {}
	return manifest


func manifest_asset_count() -> int:
	if manifest.is_empty():
		load_manifest()
	return int(manifest.get("assets", {}).size()) + int(manifest.get("skipped", []).size())


func missing_license_files() -> Array:
	var missing: Array = []
	for path in LICENSE_PATHS:
		if not FileAccess.file_exists(path):
			missing.append(path)
	return missing


func texture(relative_path: String) -> Texture2D:
	if texture_cache.has(relative_path):
		return texture_cache[relative_path]
	var path := ASSET_ROOT + relative_path
	if not ResourceLoader.exists(path):
		texture_cache[relative_path] = null
		return null
	var loaded: Resource = load(path)
	if loaded is Texture2D:
		texture_cache[relative_path] = loaded
		return loaded
	texture_cache[relative_path] = null
	return null


func texture_status(relative_path: String) -> Dictionary:
	var tex := texture(relative_path)
	return {
		"path": ASSET_ROOT + relative_path,
		"loaded": tex != null,
		"fallback": tex == null,
		"manifested": _manifest_mentions(relative_path),
	}


func sprite_frame(category: String, key: String, frame: String = "base") -> Texture2D:
	if category == "towers":
		if frame == "base":
			frame = "idle"
		return texture("sprites/towers/%s_%s.png" % [key, frame])
	if category == "enemies":
		var suffix := "" if frame == "base" else "_%s" % frame
		return texture("sprites/enemies/%s%s.png" % [key, suffix])
	if category == "projectiles":
		return texture("sprites/projectiles/%s.png" % key)
	if category == "effects":
		return texture("sprites/effects/%s.png" % key)
	if category == "terrain":
		return texture("sprites/terrain/%s.png" % key)
	return null


func animation_frame(category: String, key: String, frames: Array, speed_ms: int = 220) -> Texture2D:
	if frames.is_empty():
		return null
	var index: int = int(Time.get_ticks_msec() / max(1, speed_ms)) % frames.size()
	return sprite_frame(category, key, str(frames[index]))


func _manifest_mentions(relative_path: String) -> bool:
	if manifest.is_empty():
		load_manifest()
	var assets: Dictionary = manifest.get("assets", {})
	if assets.has(relative_path):
		return true
	for skipped in manifest.get("skipped", []):
		if skipped is Dictionary and str(skipped.get("local_path", "")).trim_prefix("assets/") == relative_path:
			return true
	return false
