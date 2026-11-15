extends RefCounted
## V41: read-only extraction from the owner's JX client PAK / loose files.
## Only new validated SPR are written under this Godot project's data/spr.
## No changes to original client, no network, no GM, no anti bypass.
const VFS = preload("res://scripts/JXVirtualFS.gd")
const BASE_VALIDATOR = preload("res://scripts/V27AT03Extractor.gd")
const MANIFEST = "res://data/renderer_audit/v41_spear_mace_source_composer.json"
const DEST = "res://data/spr/npcres/man/"
const REPORT = "res://data/renderer_audit/V41_SPR_IMPORT_RESULT.txt"

func extract(client_folder: String) -> Dictionary:
	var result: Dictionary = {"written": 0, "existing": 0, "missing": 0, "invalid": 0, "errors": [], "detail": [], "archives": 0}
	var clean_root: String = client_folder.strip_edges().replace("\\", "/").simplify_path()
	if clean_root.is_empty() or not DirAccess.dir_exists_absolute(clean_root):
		result["errors"].append("CLIENT_FOLDER_INVALID")
		return result
	if clean_root.get_file().to_lower() == "data":
		for name in DirAccess.get_files_at(clean_root):
			if name.get_extension().to_lower() == "pak":
				clean_root = clean_root.get_base_dir()
				break
	var obj: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not obj is Dictionary or str(obj.get("format", "")) != "jxnhalam.v41_spear_mace_native_composer":
		result["errors"].append("INVALID_V41_PROFILES")
		return result
	var filenames: Dictionary = obj.get("source_files", {})
	var virtual_fs = VFS.new()
	virtual_fs.configure(clean_root)
	result["archives"] = virtual_fs.archives.size()
	var validator = BASE_VALIDATOR.new()
	var output_folder: String = ProjectSettings.globalize_path(DEST)
	var created: Error = DirAccess.make_dir_recursive_absolute(output_folder)
	if created != OK:
		result["errors"].append("OUTPUT_FOLDER_ERROR_%d" % int(created))
		return result
	for filename_key in filenames.keys():
		var filename: String = str(filename_key)
		var expected: int = int(filenames[filename_key])
		if filename.get_file() != filename or not filename.begins_with("MA_") or not filename.ends_with(".spr") or expected <= 0 or expected % 8 != 0:
			result["invalid"] = int(result["invalid"]) + 1
			result["detail"].append("BAD_MANIFEST_ENTRY: " + filename)
			continue
		var to_path: String = DEST + filename
		if FileAccess.file_exists(to_path):
			var current: PackedByteArray = FileAccess.get_file_as_bytes(to_path)
			var check_existing: String = validator._validate_raw_spr(current, int(expected / 8))
			if check_existing == "OK":
				result["existing"] = int(result["existing"]) + 1
				continue
			result["invalid"] = int(result["invalid"]) + 1
			result["detail"].append("EXISTING_INVALID_NO_OVERWRITE: " + filename + " " + check_existing)
			continue
		var virtual_path: String = "\\spr\\npcres\\man\\" + filename
		var info: Dictionary = virtual_fs.locate(virtual_path)
		if not bool(info.get("found", false)):
			result["missing"] = int(result["missing"]) + 1
			result["detail"].append("NOT_FOUND: " + filename)
			continue
		var raw: PackedByteArray = virtual_fs.read_bytes(virtual_path)
		var status: String = validator._validate_raw_spr(raw, int(expected / 8))
		if status != "OK":
			result["invalid"] = int(result["invalid"]) + 1
			result["detail"].append("SOURCE_INVALID: " + filename + " " + status)
			continue
		var out: FileAccess = FileAccess.open(to_path, FileAccess.WRITE)
		if out == null:
			result["errors"].append("CANNOT_WRITE: " + filename)
			continue
		out.store_buffer(raw)
		out.close()
		result["written"] = int(result["written"]) + 1
		result["detail"].append("EXTRACTED: " + filename + " bytes=" + str(raw.size()))
	result["root"] = clean_root
	var lines: PackedStringArray = ["JXNHALAM V41 ORIGINAL SPR IMPORT", "Client=" + clean_root,
		"New=" + str(result["written"]) + " Existing=" + str(result["existing"]) + " Missing=" + str(result["missing"]) + " Invalid=" + str(result["invalid"]),
		"PAK indexes=" + str(result["archives"]), ""]
	for entry in result["detail"]:
		lines.append(str(entry))
	for err in result["errors"]:
		lines.append("ERROR " + str(err))
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()
	return result
