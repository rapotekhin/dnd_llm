class_name ImageCard
extends ModalFrame
## The image of an event (v0.7.35): one window with the picture, closed by «✕» or Esc (the game screen's overlays);
## the file stays with the event.

const SCENE := "res://ui/components/image_card.tscn"

var picture: TextureRect


func required() -> Dictionary:
	var nodes := super()
	nodes["%ImagePicture"] = "TextureRect"
	return nodes


func _ready() -> void:
	super()
	close_requested.connect(func() -> void: visible = false)
	close_x.name = "CloseImageButton"
	picture = UiScenes.need(self, "%ImagePicture")


## Shows the file; false — it is gone (a cleared folder).
func open(path: String) -> bool:
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null:
		return false
	picture.texture = ImageTexture.create_from_image(img)
	visible = true
	return true


