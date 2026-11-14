extends Node
## Loads the game's content from the JSON files in res://data and reloads
## them automatically when they change on disk (live editing).

signal data_changed

const FILES: Array[String] = ["heroes", "monsters", "items"]
const POLL_SECONDS := 1.0

var heroes: Dictionary = {}
var monsters: Dictionary = {}
var items: Dictionary = {}

var _mtimes: Dictionary = {}
var _poll := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload()


func _process(delta: float) -> void:
	_poll += delta
	if _poll < POLL_SECONDS:
		return
	_poll = 0.0
	for f in FILES:
		var t := FileAccess.get_modified_time(_path(f))
		if int(_mtimes.get(f, t)) != t:
			reload()
			data_changed.emit()
			return


func reload() -> void:
	heroes = _index(_load("heroes"), "heroes")
	monsters = _index(_load("monsters"), "monsters")
	items = _index(_load("items"), "items")
	for f in FILES:
		_mtimes[f] = FileAccess.get_modified_time(_path(f))


func item(id: String) -> Dictionary:
	if id == "" or not items.has(id):
		return {}
	return items[id]


func _path(f: String) -> String:
	return "res://data/%s.json" % f


func _load(f: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(_path(f))
	if text == "":
		push_warning("DataDB: could not read %s" % _path(f))
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("DataDB: %s is not valid JSON (keeping old data)" % _path(f))
		return {}
	return parsed


func _index(root: Dictionary, key: String) -> Dictionary:
	var out := {}
	for entry in root.get(key, []):
		if typeof(entry) == TYPE_DICTIONARY and entry.has("id"):
			out[str(entry["id"])] = entry
	return out
