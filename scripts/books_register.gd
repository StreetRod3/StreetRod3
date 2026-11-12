class_name BooksRegister
extends RefCounted

## Catalog of car mechanics books that can sit on the garage bookshelf.
## Owned books boost parameters of the player's owned cars according to `assets/books/books.registry`.

const BOOKS := "books"

static var _cache: Dictionary = {}


static func load_path(path: String) -> Dictionary:
	if _cache.has(path):
		var cached: Variant = _cache[path]
		if typeof(cached) == TYPE_DICTIONARY:
			return cached
	var loaded := _read(path)
	_cache[path] = loaded
	return loaded


static func _read(path: String) -> Dictionary:
	var result := _empty()
	result.source = path
	if path.is_empty():
		result.errors.append("Books registry path is empty.")
		return result
	if not FileAccess.file_exists(path):
		result.errors.append("Books registry not found: %s" % path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("Could not open books registry: %s" % path)
		return result
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		result.errors.append("Invalid JSON in %s (line %d): %s" % [path, json.get_error_line(), json.get_error_message()])
		return result
	if typeof(json.data) != TYPE_DICTIONARY:
		result.errors.append("Books registry root must be a JSON object.")
		return result
	var root: Dictionary = json.data
	result.books = _rows(root.get(BOOKS, []), result)
	return result


static func _rows(value: Variant, result: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		result.errors.append("Books registry '%s' must be a list." % BOOKS)
		return rows
	var seen: Dictionary = {}
	for item: Variant in value as Array:
		if typeof(item) != TYPE_DICTIONARY:
			result.errors.append("A book entry must be an object.")
			continue
		var book: Dictionary = item
		var book_id := str(book.get("id", "")).strip_edges()
		if book_id.is_empty():
			result.errors.append("A book entry is missing an id.")
			continue
		if seen.has(book_id):
			result.errors.append("Duplicate book id '%s'." % book_id)
			continue
		seen[book_id] = true
		var copy: Dictionary = book.duplicate()
		copy["id"] = book_id
		var param := str(copy.get("parameter-name", copy.get("parameter_name", ""))).strip_edges()
		copy["parameter-name"] = param
		copy["bonus_value"] = str(copy.get("value", "0")).strip_edges().to_float()
		rows.append(copy)
	return rows


static func _empty() -> Dictionary:
	return {
		"source": "",
		"books": [],
		"errors": [],
	}
