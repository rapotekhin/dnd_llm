extends GdUnitTestSuite
## The provider pinned by hand (v0.7.20.5): the settings keep one per model, the master's requests carry the one of
## the chosen model; «Авто» sends none.

var _model: String
var _providers: Dictionary


func before_test() -> void:
	_model = SaveManager.master_model
	_providers = SaveManager.master_providers.duplicate()


func after_test() -> void:
	SaveManager.master_model = _model
	SaveManager.master_providers = _providers


func test_the_pinned_provider_of_the_chosen_model_goes_with_the_request() -> void:
	SaveManager.master_model = "deepseek/deepseek-v4.1-flash-1017"
	SaveManager.master_providers = {"deepseek/deepseek-v4.1-flash-1017": "relace", "qwen/qwen3.8-27b": "modal"}
	assert_dict(SaveManager.master_params({})).is_equal({"model": "deepseek/deepseek-v4.1-flash-1017", "provider": "relace"})
	SaveManager.master_providers["deepseek/deepseek-v4.1-flash-1017"] = ""
	assert_dict(SaveManager.master_params({})).is_equal({"model": "deepseek/deepseek-v4.1-flash-1017"})
	SaveManager.master_model = ""
	assert_dict(SaveManager.master_params({"kind": "x"})).is_equal({"kind": "x"})


## v0.7.34.1: every provider of the model in the list, with the cost of 1000 turns and our measured speed.
func test_a_provider_row_shows_its_cost_and_speed() -> void:
	var p := {"tag": "deepinfra/fp8/flex", "name": "DeepInfra", "usd_per_1000_turns": 0.698, "tokens_per_s": 41.6,
		"input_usd_per_mtok": 0.0784, "output_usd_per_mtok": 0.2352, "cache_usd_per_mtok": 0.0024, "bill_factor": 1.0,
		"uptime": 95.1, "quantization": "fp8", "picked": true}
	var text := SettingsScreen.provider_text(p)
	assert_str(text).contains("DeepInfra (deepinfra/fp8/flex)").contains("0.70").contains("42")
	assert_str(SettingsScreen.provider_tooltip(p)).contains("0.0784").contains("0.0024").contains("95.1").contains("fp8")
	p["cache_usd_per_mtok"] = null
	p["bill_factor"] = 3.8
	assert_str(SettingsScreen.provider_tooltip(p)).contains("3.8")
	# an old server sends names only
	assert_str(SettingsScreen.provider_text({"tag": "relace", "name": "Relace"})).is_equal("Relace")
	assert_str(SettingsScreen.provider_tooltip({"tag": "relace", "name": "Relace"})).is_empty()


## v0.7.34.1: the list sorted by our choice, the cost, the speed, the uptime or the name; unknown values last.
func test_the_provider_list_sorts_by_the_chosen_order() -> void:
	var list := [
		{"tag": "a", "name": "Zeta", "usd_per_1000_turns": 0.3, "tokens_per_s": 0.0, "uptime": 97.9, "picked": false},
		{"tag": "b", "name": "Alpha", "usd_per_1000_turns": 0.7, "tokens_per_s": 40.0, "uptime": 95.1, "picked": true},
		{"tag": "c", "name": "Mid", "usd_per_1000_turns": 0.9, "tokens_per_s": 60.0, "uptime": null, "picked": true},
	]
	var tags := func(key: String) -> Array: return SettingsScreen.sort_providers(list, key).map(func(p: Dictionary) -> String: return p["tag"])
	assert_array(tags.call("ours")).is_equal(["b", "c", "a"])
	assert_array(tags.call("cost")).is_equal(["a", "b", "c"])
	assert_array(tags.call("speed")).is_equal(["c", "b", "a"])
	assert_array(tags.call("uptime")).is_equal(["a", "b", "c"])
	assert_array(tags.call("name")).is_equal(["b", "c", "a"])
