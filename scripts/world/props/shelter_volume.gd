extends Area3D
## Marks the sheltered interior of a cover prop.
##
## Reports entry and exit to whatever walks in, rather than the player polling the
## world. Checked by duck typing so this stays usable for creatures sheltering from
## weather later, without either side knowing about the other.

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method(&"enter_shelter"):
		body.enter_shelter()


func _on_body_exited(body: Node3D) -> void:
	if body.has_method(&"exit_shelter"):
		body.exit_shelter()
