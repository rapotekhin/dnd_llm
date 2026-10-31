class_name ImageCard
extends Control
## The image of an event (v0.7.35): one window with the picture, closed by «✕» or Esc (the game screen's overlays);
## the file stays with the event.

var frame: ModalFrame
var picture: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame = ModalFrame.make("IMAGE_TITLE", 1500.0)
	add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.close_requested.connect(func() -> void: visible = false)
	frame.close_x.name = "CloseImageButton"
	picture = TextureRect.new()
	picture.name = "ImagePicture"
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(1440, 810)
	frame.body.add_child(picture)


## Shows the file; false — it is gone (a cleared folder).
func open(path: String) -> bool:
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null:
		return false
	picture.texture = ImageTexture.create_from_image(img)
	visible = true
	return true


