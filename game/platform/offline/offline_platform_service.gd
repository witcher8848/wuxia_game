extends Node
## Offline adapter: no Steam API, external service, or fake achievement success.

var _initialized: bool = false


func initialize() -> Dictionary:
	_initialized = true
	return {
		"platform": "offline", "achievements": false, "stats": false,
		"overlay": false, "cloud": false,
	}


func is_available() -> bool:
	return false


func get_platform_language() -> String:
	return OS.get_locale_language()


func unlock_achievement(_id: String) -> void:
	pass


func set_stat(_id: String, _value: float) -> void:
	pass


func store_stats() -> void:
	pass


func open_store_page() -> void:
	pass


func shutdown() -> void:
	_initialized = false
