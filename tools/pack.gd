extends SceneTree
## Packs the staged mod at res://mods/sit_anywhere/ into a standalone .pck.
##
## build.sh stages the runtime tree selected by .pckignore, runs --import, then copies this
## script into the staging project and calls it. The packer adds the staged tree as-is:
## mod.json, scripts and merge data, plus a generated mod.built.json marker.
##
##   godot --headless --path <stage> --script res://pack.gd -- --out FILE.pck

const ID_PATTERN := "^[a-z0-9_]{1,40}$"

var _count := 0
var _failed := false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out = args[i + 1]
	if out.is_empty():
		fail("missing --out <file.pck>")
		return

	var ids := DirAccess.get_directories_at("res://mods")
	if ids.size() != 1:
		fail("expected exactly one staged mod under res://mods/, found %d" % ids.size())
		return
	var id := ids[0]
	if RegEx.create_from_string(ID_PATTERN).search(id) == null:
		fail("invalid staged mod id: %s" % id)
		return

	var root := "res://mods/%s" % id
	var manifest_path := root.path_join("mod.json")
	var manifest: Variant = _json(manifest_path)
	if not manifest is Dictionary:
		fail("no readable %s" % manifest_path)
		return
	if str((manifest as Dictionary).get("id", "")) != id:
		fail("mod.json id does not match the staged folder %s" % id)
		return

	var out_path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())

	var packer := PCKPacker.new()
	if packer.pck_start(out_path) != OK:
		fail("cannot write %s" % out_path)
		return

	_add(packer, manifest_path, ProjectSettings.globalize_path(manifest_path))
	if _failed: return
	var absolute_root := ProjectSettings.globalize_path(root)
	for name: String in DirAccess.get_files_at(absolute_root):
		if name == "mod.json" or name.begins_with(".") or name.ends_with(".uid"):
			continue
		if name.ends_with(".import"):
			_add_import(packer, root.path_join(name), absolute_root.path_join(name))
		else:
			_add_file(packer, root.path_join(name), absolute_root.path_join(name))
		if _failed: return
	for name: String in DirAccess.get_directories_at(absolute_root):
		if name.begins_with("."):
			continue
		_add_tree(packer, root.path_join(name), absolute_root.path_join(name))
		if _failed: return

	var stamp := OS.get_temp_dir().path_join("mod_build_%s.json" % id)
	var marker := FileAccess.open(stamp, FileAccess.WRITE)
	if marker == null:
		fail("cannot write %s" % stamp)
		return
	marker.store_string(JSON.stringify({
		"id": id,
		"version": str((manifest as Dictionary).get("version", "")),
		"game_version": str((manifest as Dictionary).get("game_version", "")),
		"godot": Engine.get_version_info().string,
	}, "\t"))
	marker.close()
	_add(packer, root.path_join("mod.built.json"), stamp)
	if _failed: return

	if packer.flush() != OK:
		fail("cannot finish %s" % out_path)
		return
	DirAccess.remove_absolute(stamp)

	print("[%s] %d files" % [id, _count])
	print("MOD_BUILT ", out_path)
	quit(0)


func _add_file(packer: PCKPacker, logical: String, absolute: String, import_sidecar := true) -> void:
	if _failed: return
	if import_sidecar and FileAccess.file_exists(absolute + ".import"):
		return   # the .import sidecar carries the imported data
	_add(packer, logical, absolute)


func _add_import(packer: PCKPacker, logical: String, absolute: String) -> void:
	_add(packer, logical, absolute)
	if _failed: return
	var config := ConfigFile.new()
	if config.load(absolute) != OK:
		push_warning("cannot read %s" % absolute)
		return
	var dest: Variant = config.get_value("deps", "dest_files", [])
	if not dest is Array or (dest as Array).is_empty():
		if config.has_section_key("remap", "path"):
			dest = [config.get_value("remap", "path")]
		else:
			dest = []
	for item: Variant in dest:
		var logical_dest := str(item)
		var absolute_dest := ProjectSettings.globalize_path(logical_dest)
		if not FileAccess.file_exists(absolute_dest):
			fail("%s is not imported yet (run build.sh again)" % logical_dest)
			return
		_add(packer, logical_dest, absolute_dest)
		if _failed: return


func _add_tree(packer: PCKPacker, logical_dir: String, absolute_dir: String) -> void:
	if _failed: return
	for name: String in DirAccess.get_files_at(absolute_dir):
		if _failed: return
		if name.begins_with(".") or name.ends_with(".uid"):
			continue
		var logical := logical_dir.path_join(name)
		var absolute := absolute_dir.path_join(name)
		if name.ends_with(".import"):
			_add_import(packer, logical, absolute)
		else:
			_add_file(packer, logical, absolute)
	for name: String in DirAccess.get_directories_at(absolute_dir):
		if _failed: return
		if name.begins_with("."):
			continue
		_add_tree(packer, logical_dir.path_join(name), absolute_dir.path_join(name))


func _add(packer: PCKPacker, logical: String, absolute: String) -> void:
	if _failed: return
	if packer.add_file(logical, absolute) != OK:
		fail("cannot add %s" % logical)
		return
	_count += 1


func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null


func fail(why: String) -> void:
	_failed = true
	printerr("MOD_BUILD_FAILED ", why)
	quit(1)
