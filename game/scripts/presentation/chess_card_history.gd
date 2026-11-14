extends PanelContainer

const Battle = preload("res://scripts/domain/chess_battle.gd")
const UI = preload("res://scripts/presentation/card_ui.gd")

var home: Control
var recent: Label
var toggle: Button
var popover: PanelContainer
var scroll: ScrollContainer
var rows: VBoxContainer
var shown_count := 0
var build_face: Callable

func setup(view: Control, make_face: Callable) -> void:
	name = "CardPlayHistory"
	build_face = make_face
	custom_minimum_size.x = 235
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := UI.box(Color("292f28"), Color("79684c"), 8, 6)
	add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := UI.label(header, "出牌记录", 16, UI.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle = UI.button(header, "查看", _toggle_history)
	toggle.name = "ToggleCardHistory"
	toggle.accessibility_name = "查看双方出牌记录"
	toggle.custom_minimum_size = Vector2(47, 28)
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.disabled = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	home = Control.new()
	home.name = "LatestPlayedCard"
	home.custom_minimum_size = Vector2(73, 102)
	row.add_child(home)
	var backdrop := Panel.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_theme_stylebox_override("panel", UI.box(Color("21352e"), Color("4b5b4d"), 0, 5))
	home.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	recent = UI.label(row, "还没有出牌", 15, UI.MUTED, true)
	recent.name = "LatestPlayedCardSummary"
	recent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	recent.max_lines_visible = 4
	recent.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	popover = PanelContainer.new()
	popover.name = "CardHistoryPopover"
	popover.z_index = 45
	popover.add_theme_stylebox_override("panel", UI.box(Color("1c3129"), UI.GOLD, 11, 6))
	view.add_child(popover)
	var content := VBoxContainer.new()
	popover.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var log_title := UI.label(heading, "双方出牌记录", 18, UI.GOLD)
	log_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := UI.button(heading, "关闭", close_history)
	close.custom_minimum_size.y = 28
	close.add_theme_font_size_override("font_size", 14)
	scroll = UI.scroll(content)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	scroll.add_child(rows)
	popover.hide()
	view.resized.connect(func():
		custom_minimum_size.x = 174 if view.size.x < 1120 else 235
		_place_popover())
	resized.connect(_place_popover)

func show_through(plays: Array, count: int) -> void:
	if count <= shown_count:
		return
	for i in range(shown_count, count):
		_add_record(plays[i])
	shown_count = count
	var play: Dictionary = plays[count - 1]
	var card: Dictionary = play.card
	if home.has_node("CardFace"):
		var previous := home.get_node("CardFace")
		home.remove_child(previous)
		previous.queue_free()
	var frame := Panel.new()
	frame.name = "CardFace"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(frame)
	build_face.call(frame, card, side_color(play.side))
	recent.text = "%s · %s\n%s" % [side_name(play.side), card.name.get_slice(" · ", 0), summary(play, 2)]
	recent.add_theme_color_override("font_color", side_color(play.side))
	toggle.disabled = false
	_scroll_to_latest()

func _add_record(play: Dictionary) -> void:
	var card: Dictionary = play.card
	var content := UI.panel(rows, Color("293b32"), Color("48584a"))
	var header := HBoxContainer.new()
	content.add_child(header)
	UI.art(header, card, Vector2(40, 43))
	var captions := VBoxContainer.new()
	captions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(captions)
	UI.label(captions, "第 %d 回合 · %s · %d 费" % [play.round, side_name(play.side), card.cost], 13, side_color(play.side))
	UI.label(captions, card.name, 17, UI.INK, true)
	UI.label(content, summary(play), 14, UI.INK, true)
	UI.label(content, card.trait, 13, UI.MUTED, true)

func _toggle_history() -> void:
	if popover.visible:
		close_history()
		return
	popover.show()
	toggle.text = "收起"
	_place_popover()
	_scroll_to_latest()

func close_history() -> void:
	popover.hide()
	toggle.text = "查看"

func _place_popover() -> void:
	if not popover.visible:
		return
	var view := popover.get_parent() as Control
	var position_in_view := view.get_global_transform().affine_inverse() * global_position
	var height := clampf(position_in_view.y - 28.0, 100.0, 390.0)
	popover.size = Vector2(minf(420.0, view.size.x - position_in_view.x - 15.0), height)
	popover.position = position_in_view - Vector2(0, popover.size.y + 8.0)

func _scroll_to_latest() -> void:
	if popover.visible:
		_scroll_after_layout.call_deferred()

func _scroll_after_layout() -> void:
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

static func side_name(side: int) -> String:
	return "我方" if side == Battle.PLAYER else "敌方"

static func side_color(side: int) -> Color:
	return UI.GREEN if side == Battle.PLAYER else UI.ORANGE

static func summary(play: Dictionary, limit: int = 0) -> String:
	var lines: Array[String] = []
	for result in play.effects:
		if limit > 0 and lines.size() >= limit:
			lines.append("另有 %d 个目标" % (play.effects.size() - limit))
			break
		lines.append("%s · %s" % [result.name, result.summary])
	return "\n".join(lines)
