class_name ProjectItem
extends PanelContainer

## Signal emitted when this item is clicked (select).
signal selected(project_data: RPGProjectData)

## Signal emitted on double-click (open editor).
signal opened(project_data: RPGProjectData)

# ------------------------------------------------------------------------------
# VARIABLES & NODES
# ------------------------------------------------------------------------------

@export var hover_color: Color = Color("3b3b3bff")
@export var selected_color: Color = Color("353535ff")
@export var normal_color: Color = Color("292929")

var is_selected: bool = false
var _style_box: StyleBoxFlat
var data: RPGProjectData

@onready var label_name: Label = %ProjectName
@onready var label_path: Label = %ProjectPath
@onready var label_version: Label = %ProjectVersion
@onready var label_date: Label = %FileDate
@onready var texture_icon: TextureRect = %Icon


func _ready() -> void:
	var current = get_theme_stylebox("panel")
	if current is StyleBoxFlat:
		_style_box = current.duplicate()
	else:
		_style_box = StyleBoxFlat.new()
		_style_box.bg_color = normal_color
	
	add_theme_stylebox_override("panel", _style_box)


func setup(project_data: RPGProjectData) -> void:
	data = project_data
	
	label_name.text = data.project_name
	label_path.text = data.project_path
	label_version.text = data.version
	label_date.text = data.last_modified
	
	if FileAccess.file_exists(data.icon_path):
		var img = Image.load_from_file(data.icon_path)
		if img:
			var tex = ImageTexture.create_from_image(img)
			texture_icon.texture = tex


# ------------------------------------------------------------------------------
# INPUT HANDLING
# ------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(data)
		if event.double_click:
			opened.emit(data)


func _on_folder_button_pressed() -> void:
	if not data: return
	OS.shell_open(data.project_path)


# ------------------------------------------------------------------------------
# VISUAL STATES
# ------------------------------------------------------------------------------

func set_is_selected(value: bool) -> void:
	if is_selected != value:
		is_selected = value
		if is_selected:
			_set_bg_color(selected_color)
		else:
			_set_bg_color(normal_color)


func _set_bg_color(color: Color) -> void:
	if _style_box:
		_style_box.bg_color = color


func _on_focus_entered() -> void:
	if not is_selected:
		selected.emit(data)
	_set_bg_color(selected_color)


func _on_focus_exited() -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return

	if is_selected:
		_set_bg_color(selected_color)
	else:
		if get_global_rect().has_point(get_global_mouse_position()):
			_set_bg_color(hover_color)
		else:
			_set_bg_color(normal_color)


func _on_mouse_entered() -> void:
	if not is_selected:
		_set_bg_color(hover_color)


func _on_mouse_exited() -> void:
	if is_selected:
		_set_bg_color(selected_color)
	else:
		_set_bg_color(normal_color)
