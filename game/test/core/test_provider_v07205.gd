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
