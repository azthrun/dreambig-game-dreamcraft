extends Label
## Live debug readout.
##
## Boot information is fixed and set once; the sky and weather lines are re-read every
## frame, because the whole point is watching them change. Without a live readout there
## is no way to tell a stalled state machine from a slow one.

var _static_lines := PackedStringArray()
var _sources: Array[Node] = []


## `sources` are nodes exposing status_line(). Kept as a plain list so adding another
## live system later needs no change here.
func configure(static_lines: PackedStringArray, sources: Array[Node]) -> void:
	_static_lines = static_lines
	_sources = sources
	_refresh()


func _process(_delta: float) -> void:
	if not _sources.is_empty():
		_refresh()


func _refresh() -> void:
	var lines := PackedStringArray(_static_lines)
	for source in _sources:
		if is_instance_valid(source) and source.has_method(&"status_line"):
			lines.append(source.status_line())
	text = "\n".join(lines)
