extends GdUnitTestSuite
## The player's additions to an image model's prompt (v0.7.37): absent — the server's own; saved — sent with the
## model the brush draws with, the server's default when the picked one is gone.

var _info: Dictionary
var _model: String
var _prompts: Dictionary

const MODELS := [
	{"id": "recraft", "name": "Recraft", "negative": false, "prompt_add": "", "negative_add": ""},
	{"id": "sd:amix", "name": "A-Mix", "negative": true, "prompt_add": "masterpiece, <lora:rimixO:0.65>", "negative_add": "lowres"},
]


func before_test() -> void:
	_info = Backend.client.server_info
	_model = SaveManager.image_model
	_prompts = SaveManager.image_prompts
	Backend.client.server_info = {"image_model": "recraft", "image_models": MODELS}
	SaveManager.image_prompts = {}


func after_test() -> void:
	Backend.client.server_info = _info
	SaveManager.image_model = _model
	SaveManager.image_prompts = _prompts


func test_nothing_saved_sends_nothing() -> void:
	SaveManager.image_model = "sd:amix"
	var p := SaveManager.image_params({})
	assert_str(str(p["image_model"])).is_equal("sd:amix")
	assert_bool(p.has("prompt_add") or p.has("negative_add") or p.has("negative_only")).is_false()


func test_the_saved_additions_go_with_their_model() -> void:
	SaveManager.image_model = "sd:amix"
	SaveManager.image_prompts = {"sd:amix": {"prompt": "<lora:rimixO:0.8>", "negative": "blurry", "only": true}}
	var p := SaveManager.image_params({})
	assert_str(str(p["prompt_add"])).is_equal("<lora:rimixO:0.8>")
	assert_str(str(p["negative_add"])).is_equal("blurry")
	assert_bool(bool(p["negative_only"])).is_true()


func test_a_model_gone_falls_back_to_the_default_and_its_additions() -> void:
	SaveManager.image_model = "sd:gone"
	SaveManager.image_prompts = {"sd:gone": {"prompt": "x"}, "recraft": {"prompt": "cinematic", "negative": "", "only": false}}
	assert_str(SaveManager.current_image_model()).is_equal("recraft")
	var p := SaveManager.image_params({})
	assert_bool(p.has("image_model")).is_false()
	assert_str(str(p["prompt_add"])).is_equal("cinematic")
