extends "res://tools/playtest/playtest_base.gd"
## The brush playtest (python tools/godot_playtest.py --scenario images; --real draws with the real model), v0.7.35:
## the square right of the input draws the last event, the card closes, the event keeps its image — the brush and
## the link under the event open it again without a new request.


func run() -> void:
	var gs := node("GameState")
	var bus := node("EventBus")
	if not step("master connected", await wait_until(func() -> bool: return node("Backend").is_ready(), 30.0)):
		return
	step("the server offers image models", not node("Backend").image_models().is_empty(), str(node("Backend").image_models()))
	await tap("NewGameButton")
	await tap("NextButton")
	await tap("Preset_fighter_aira")
	await press(find(screen(), "StartButton"))
	if not step("game started", await wait_until(func() -> bool: return screen_is("GameScreen") and not gs.is_busy(), 90.0)):
		return
	var game := screen()
	var brush: Button = find(game, "BrushButton")
	if not step("the brush is right of the input", brush != null and brush.visible):
		return
	await wait_until(func() -> bool: return not brush.disabled, 10.0)
	step("the brush is on once the master has spoken", not brush.disabled)
	var requests := [0]
	bus.image_busy.connect(func(b: bool) -> void:
		if b:
			requests[0] += 1)
	await press(brush)
	await frames(2)
	await shot("drawing")
	var card: Control = find(game, "ImageView")
	if not step("the card opens with the image", await wait_until(func() -> bool: return card.visible, 160.0)):
		return
	var pic: TextureRect = find(game, "ImagePicture")
	step("the picture has a texture", pic.texture != null and pic.texture.get_width() > 0)
	await frames(3)
	await shot("card")
	var entry: Dictionary = gs.session.chat[ImageFrame.event_index(gs.session)]
	step("the event keeps its file", FileAccess.file_exists(ImageFrame.image_of(entry)), ImageFrame.image_of(entry))
	await press(find(game, "CloseImageButton"))
	await frames(3)
	step("«✕» closes the card", not card.visible)
	var link: Button = find(game, "ImageLink")
	step("the event has a link to its image", link != null)
	await shot("link")
	await press(brush)
	await frames(3)
	step("the brush on the same event opens it again, no new request", card.visible and requests[0] == 1, "requests %d" % requests[0])
	card.visible = false
	if link != null:
		await press(link)
		await frames(3)
		step("the link opens it too", card.visible)
		card.visible = false
