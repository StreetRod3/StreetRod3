extends RefCounted

## The tabs along the top of the Controls page. Each tab is a page of its own, and changing tab
## swaps one for the other in place, over the same settings menu, so to the player it is one page.

const KEYS_AND_PAD := 0
const WHEEL := 1
const MOUSE := 2
const _PAGES: Array[String] = ["res://scripts/controls_setup.gd", "res://scripts/controller_setup.gd", "res://scripts/mouse_setup.gd"]
const _NAMES: Array[String] = ["Keyboard and gamepad", "Wheel and shifter", "Mouse"]


static func build(current: int, from: CanvasLayer) -> TabBar:
	var tabs := TabBar.new()
	tabs.focus_mode = Control.FOCUS_ALL
	for tab_name: String in _NAMES:
		tabs.add_tab(tab_name)
	tabs.current_tab = current
	tabs.tab_changed.connect(func(index: int) -> void: _switch(from, index))
	return tabs


## Left and right, or A and D, change tab while the tabs have focus. Read before the menu's own
## focus moves would take the arrow keys.
static func handle_key(tabs: TabBar, event: InputEvent) -> bool:
	if not tabs.has_focus() or not event is InputEventKey or not event.pressed or event.echo:
		return false
	var code: Key = event.keycode
	if code == KEY_LEFT or code == KEY_A:
		tabs.current_tab = maxi(tabs.current_tab - 1, 0)
	elif code == KEY_RIGHT or code == KEY_D:
		tabs.current_tab = mini(tabs.current_tab + 1, tabs.tab_count - 1)
	else:
		return false
	return true


static func _switch(from: CanvasLayer, index: int) -> void:
	var to: CanvasLayer = load(_PAGES[index]).new()
	to.call(&"open", from.get_parent(), from.get(&"_page"), from.get(&"_return_focus"))
	to.call(&"focus_tabs")
	from.queue_free()
