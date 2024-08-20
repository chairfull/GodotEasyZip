@tool
extends Resource
class_name Zip

## Write multiple files to a zip.
## Autoconverts:
## 		- Dictionary -> json -> bytes
##		- String -> bytes
##		- Image -> (Uses file extension to determine) -> bytes
##		- Resource -> (.tres or .res) -> bytes
##		- Node -> (.tscn or .scn) -> bytes
## kwargs:
##		- lossy: (bool) Used for .webp
##		- quality: (float) Used for .jpg & .webp
##		- flags: (ResourceSave.FLAG_) Used for saving resources
## Usage:
##		write("user://data.zip", {
##			"version.txt": "123",
##			"state.json": {"score": 10, "position": [0.0, 0.0]},
##			"image.webp": Image,
##			"bytes.data": PackedByteArray()
##		})
static func write(zip_path: String, files: Dictionary, kwargs := {}, append_create := ZIPPacker.APPEND_CREATE) -> int:
	var zip := ZIPPacker.new()
	var err := zip.open(zip_path, append_create)
	if err != OK:
		push_error("Zip: Couldn't open %s: %s." % [zip_path, error_string(err)])
		return err
	
	for file_path: String in files:
		var bytes: PackedByteArray
		var file_data = files[file_path]
		
		match typeof(file_data):
			TYPE_PACKED_BYTE_ARRAY: bytes = file_data
			TYPE_STRING: bytes = (file_data as String).to_utf8_buffer()
			TYPE_DICTIONARY:
				match file_path.get_extension():
					"json": bytes = JSON.stringify(file_data, "", false).to_utf8_buffer()
					"var": bytes = var_to_str(file_data).to_utf8_buffer()
			TYPE_OBJECT:
				# Serialize image.
				if file_data is Image:
					var image: Image = file_data
					match file_path.get_extension():
						"png": bytes = image.save_png_to_buffer()
						"jpg", "jpeg": bytes = image.save_jpg_to_buffer(kwargs.get("quality", 0.75))
						"webp": bytes = image.save_webp_to_buffer(kwargs.get("lossy", false), kwargs.get("quality", 0.75))
						"svg": push_error(".svg writing not supported yet.")
						var unknown_ext:
							push_error("Zip: Couldn't write image %s: Unknown extension %s." % [file_path, unknown_ext])
							continue
				
				# Serialize resource.
				elif file_data is Resource:
					bytes = resource_to_bytes(file_data, file_path.get_extension(), kwargs)
				
				# Serialize node/scene.
				elif file_data is Node:
					var packed := PackedScene.new()
					packed.pack(file_data)
					bytes = resource_to_bytes(packed, file_path.get_extension(), kwargs)
				
				else:
					push_error("Zip: Couldn't write %s: Don't know how to serialize %s." % [file_path, file_data])
					continue
			
			var wrong_type:
				push_error("Zip: Couldn't add %s to %s: Can't convert type %s." % [file_path, zip_path, wrong_type])
				continue
		
		err = zip.start_file(file_path)
		if err != OK:
			push_error("Zip: Couldn't start %s: %s." % [file_path, error_string(err)])
			continue
		
		err = zip.write_file(bytes)
		if err != OK:
			push_error("Zip: Couldn't write %s: %s." % [file_path, error_string(err)])
			continue
		
		err = zip.close_file()
		if err != OK:
			push_error("Zip: Couldn't close %s: %s." % [file_path, error_string(err)])
			continue
	
	err = zip.close()
	if err != OK:
		push_error("Zip: Couldn't write %s: %s." % [zip_path, error_string(err)])
	
	return err

## Appends files, preserving what already existed.
static func append(zip_path: String, files: Dictionary, kwargs := {}):
	return write(zip_path, files, kwargs, ZIPPacker.APPEND_ADDINZIP)

## Appends a screenshot to the zip.
static func write_screenshot(zip_path: String, viewport: Viewport, name := "preview.jpg", shrink := true, kwargs := {}):
	await RenderingServer.frame_post_draw
	var screenshot := viewport.get_texture().get_image()
	if shrink:
		screenshot.shrink_x2()
	append(zip_path, {name: screenshot}, kwargs)

## Read a file in a zip.
static func read(zip_path: String, file: String, default: Variant = null) -> Variant:
	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		push_error("Zip: Can't read %s. (%s)" % [zip_path, error_string(err)])
		return null
	var bytes := zip.read_file(file)
	zip.close()
	
	match file.get_extension():
		"webp", "png", "jpg", "jpeg", "svg":
			var image := Image.new()
			match file.get_extension():
				"webp": image.load_webp_from_buffer(bytes)
				"png": image.load_png_from_buffer(bytes)
				"jpg", "jpeg": image.load_jpg_from_buffer(bytes) 
				"svg": image.load_svg_from_buffer(bytes)
			return image
		"txt": return bytes.get_string_from_utf8()
		"var": return str_to_var(bytes.get_string_from_utf8())
		"json": return JSON.parse_string(bytes.get_string_from_utf8())
		"tscn", "scn", "tres", "res": return resource_from_bytes(bytes, file.get_extension())
		var unknown_ext:
			push_error("Zip: Can't load ext %s in %s at %s." % [unknown_ext, file, zip_path])
	
	return default

## Remove files from a zip.
static func remove(zip_path: String, remove_files: Array):
	var reader := ZIPReader.new()
	var read_err := reader.open(zip_path)
	if read_err != OK:
		push_error("Zip: Can't open %s. (%s)" % [zip_path, error_string(read_err)])
		return
	
	var writer := ZIPPacker.new()
	var write_err := writer.open("user://temp_save.zip")
	if write_err != OK:
		push_error("Zip: Can't open %s. (%s)" % [zip_path, error_string(write_err)])
		return
	
	for file in reader.get_files():
		if file not in remove_files:
			writer.start_file(file)
			writer.write_file(reader.read_file(file))
			writer.close_file()
	
	DirAccess.remove_absolute(zip_path)
	DirAccess.rename_absolute("user://temp_save.zip", zip_path)

## Get all files that begin with head and end with tail.
static func get_files(zip_path: String, head := "", tail := "") -> PackedStringArray:
	var zip := ZIPReader.new()
	var err := zip.open(zip_path)
	if err != OK:
		push_error("Zip: Can't open %s. (%s)" % [zip_path, error_string(err)])
		return PackedStringArray()
	var files: PackedStringArray
	for file in zip.get_files():
		if file.begins_with(head) and file.ends_with(tail):
			files.append(file)
	return files

## Convert a resource to a byte array.
static func resource_to_bytes(resource: Resource, ext: String = "tres", kwargs := {}) -> PackedByteArray:
	var temp_path := "user://temp.%s" % ext
	ResourceSaver.save(resource, temp_path, kwargs.get("flags", ResourceSaver.FLAG_COMPRESS))
	var bytes := FileAccess.get_file_as_bytes(temp_path)
	DirAccess.remove_absolute(temp_path)
	return bytes

## Convert a scene to a byte array.
static func resource_from_bytes(bytes: PackedByteArray, ext: String = "tres") -> Resource:
	var temp_path := "user://temp.%s" % ext
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var resource := ResourceLoader.load(temp_path)
	DirAccess.remove_absolute(temp_path)
	return resource
