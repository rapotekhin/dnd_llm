class_name UiScenes
extends RefCounted
## Screens and windows made in the editor (ADR-0013): opens a scene without its examples and finds the nodes a script
## needs. A scene's script says what it needs in `required()`: `{"%NodeName": "ClassName"}`, the test of every scene
## checks it.

const SAMPLE_GROUP := "editor_sample"  # rows that show the look in the editor and never reach the game


static func open(path: String) -> Node:
	var root: Node = (load(path) as PackedScene).instantiate()
	_drop_samples(root)
	return root


static func _drop_samples(node: Node) -> void:
	for ch: Node in node.get_children():
		if ch.is_in_group(SAMPLE_GROUP):
			node.remove_child(ch)
			ch.free()
		else:
			_drop_samples(ch)


## A node lost or retyped in the editor is a warning and a stand-in, never a crash (ADR-0013, §8).
static func need(root: Node, path: String) -> Node:
	var type: String = root.call("required").get(path, "Control")
	var node := root.get_node_or_null(path)
	if node != null and node.is_class(type):
		return node
	push_warning("%s: no %s %s" % [root.scene_file_path, type, path])
	var stand_in: Node = ClassDB.instantiate(type)
	stand_in.name = path.trim_prefix("%").get_file()
	root.add_child(stand_in)
	return stand_in
