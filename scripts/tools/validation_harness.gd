class_name ValidationHarness
extends RefCounted


static func new_result() -> Dictionary:
	return {"ok": true, "checks": [], "errors": []}


static func record_check(result: Dictionary, label: String, passed: bool, detail: Variant) -> void:
	var stored_detail: Variant = detail.duplicate(true) if detail is Dictionary or detail is Array else detail
	result["checks"].append({"label": label, "passed": passed, "detail": stored_detail})
	if not passed:
		result["ok"] = false
		result["errors"].append("%s failed: %s" % [label, str(stored_detail)])


static func root_node_or_new(tree: SceneTree, node_name: String, script: Script) -> Node:
	var existing := tree.root.get_node_or_null(node_name)
	if existing != null:
		return existing
	var node: Node = script.new()
	tree.root.add_child(node)
	node.name = node_name
	return node


static func teardown_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()


static func finish(tree: SceneTree, result: Dictionary, success_token: String, failure_token: String) -> void:
	if bool(result.get("ok", false)):
		print(success_token)
		for check in result.get("checks", []):
			print("  OK %s = %s" % [check["label"], str(check["detail"])])
		tree.quit(0)
		return
	push_error(failure_token)
	for error in result.get("errors", []):
		push_error(error)
	tree.quit(1)
