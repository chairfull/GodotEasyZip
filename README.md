# Zip
`v1.0`

Write multiple files to a zip.

Ideal for save systems + level editors. 

Autoconverts:
- Dictionary -> (.json or .var) -> bytes
- String -> bytes
- Image -> (.png, .jpg/jpeg, .webp, .svg) -> bytes
- Resource -> (.tres or .res) -> bytes
- Node -> (.tscn or .scn) -> bytes

Saving files as `file.json` will use `JSON.stringify`, while `file.var` will use Godots `var_to_str` which supports built in formats.

# Usage
## Writing
```gd
Zip.write("user://data.zip", {
	"version.txt": "123",
	"state.json": {"score": 10, "position": [0.0, 0.0]},
	"state.var": {"score": 10, "position": Vector2(0.0, 0.0)},
	"image.webp": Image,
	"bytes.data": PackedByteArray(),
	"current_scene.tscn": get_tree().current_scene,
})
```
**kwargs**
- `lossy`: (bool) Used for .webp
- `quality`: (float) Used for .jpg & .webp
- `flags`: (ResourceSave.FLAG_) Used for saving resources

## Reading
```gd
var current_scene = Zip.read("user://data.zip", "current_scene.tscn")
```
## Other
```gd
# For kwargs look above.
# You don't have to call await before it, but it's ideal.
await Zip.write_screenshot("user://data.slot", get_viewport(), "name_and_ext.jpeg", shrink, kwargs)

# List of files you want removed from the zip.
Zip.remove("user://data.slot", ["file.json", "screenshot.jpg"])

# Exactly like write() but preserves the previous content if it exists.
Zip.append("user://data.slot", {"image.jpg", image})
```
