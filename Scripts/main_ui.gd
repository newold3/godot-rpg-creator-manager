class_name ProjectManager
extends Control

signal project_list_updated

# ------------------------------------------------------------------------------
# CONSTANTS & CONFIG
# ------------------------------------------------------------------------------

const CONFIG_FILENAME: String = "rpg_project.cfg"
const LAUNCHER_DATA_PATH: String = "user://launcher_data.json"
const CACHE_DIR: String = "user://cache/"
const CACHED_ZIP_PATH: String = "user://cache/template_master.zip"

const TEMPLATE_URL: String = "https://github.com/newold3/Godot-RPG-Creator/archive/refs/heads/master.zip"
const VERSION_CHECK_URL: String = "https://gist.githubusercontent.com/newold3/3ff01f9859cc46ae86b8eb5344cbb800/raw"

const PROJECT_ITEM_PATH: String = "res://Scenes/item.tscn"

enum OrderMode {LAST_EDITED, NAME, PATH}


# ------------------------------------------------------------------------------
# UI REFERENCES
# ------------------------------------------------------------------------------

@export_group("Containers")
@export var project_container: BoxContainer

@export_group("Top Menu Buttons")
@export var btn_create: Button
@export var btn_import: Button
@export var btn_scan: Button

@export_group("Side Bar Buttons")
@export var btn_edit: Button
@export var btn_run: Button
@export var btn_rename: Button
@export var btn_duplicate: Button
@export var btn_remove: Button
@export var btn_patreon: Button
@export var filter_control: LineEdit
@export var order_mode: OptionButton

@export_group("Dialogs & Tools")
@export var file_dialog: FileDialog
@export var http_downloader: HTTPRequest
@export var http_version_check: HTTPRequest
@export var version_label: Label


# ------------------------------------------------------------------------------
# INTERNAL VARIABLES
# ------------------------------------------------------------------------------

var projects: Array[RPGProjectData] = []
var selected_project: RPGProjectData = null
var item_scene_resource: PackedScene

var _thread: Thread
var _confirm_dialog: ConfirmationDialog
var _remove_dialog: ConfirmationDialog
var _remove_checkbox: CheckBox
var _rename_dialog: ConfirmationDialog
var _rename_input: LineEdit
var _pending_create_path: String = ""

# Standard Overlay Nodes (Processing only)
var _overlay_bg: ColorRect
var _overlay_title: Label
var _overlay_sub: Label

# State
var current_mode: OrderMode = OrderMode.LAST_EDITED
var current_filter: String = ""
var _search_timer: Timer

# Versioning
var cached_template_version: String = "0.0"
var online_template_version: String = ""


func _ready() -> void:
	DisplayServer.window_set_min_size(Vector2i(740, 580))
	
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)

	_setup_overlay_ui()
	_setup_dynamic_dialogs()
	
	_thread = Thread.new()
	
	# Search Debounce Timer
	_search_timer = Timer.new()
	_search_timer.wait_time = 0.25
	_search_timer.one_shot = true
	_search_timer.timeout.connect(_on_search_timer_timeout)
	add_child(_search_timer)

	if ResourceLoader.exists(PROJECT_ITEM_PATH):
		item_scene_resource = load(PROJECT_ITEM_PATH)
	else:
		printerr("CRITICAL: Scene not found: ", PROJECT_ITEM_PATH)

	# --- Native OS Drop Signal ---
	get_window().files_dropped.connect(_on_files_dropped)

	# Connections
	if btn_create: btn_create.pressed.connect(_on_create_pressed)
	if btn_import: btn_import.pressed.connect(_on_import_pressed)
	if btn_scan: btn_scan.pressed.connect(_on_scan_pressed)

	if btn_edit: btn_edit.pressed.connect(_on_edit_pressed)
	if btn_run: btn_run.pressed.connect(_on_run_pressed)
	if btn_rename: btn_rename.pressed.connect(_on_rename_pressed)
	if btn_duplicate: btn_duplicate.pressed.connect(_on_duplicate_pressed)
	if btn_remove: btn_remove.pressed.connect(_on_remove_pressed)
	if btn_patreon: btn_patreon.pressed.connect(_on_patreon_pressed)
	
	if order_mode: 
		order_mode.item_selected.connect(_on_mode_changed)
		if order_mode.item_count == 0:
			order_mode.add_item("Last Edited", OrderMode.LAST_EDITED)
			order_mode.add_item("Name", OrderMode.NAME)
			order_mode.add_item("Path", OrderMode.PATH)

	if filter_control: 
		filter_control.text_changed.connect(_on_filter_changed)
	
	if http_downloader:
		if http_downloader.request_completed.is_connected(_on_http_request_completed):
			http_downloader.request_completed.disconnect(_on_http_request_completed)
		http_downloader.request_completed.connect(_on_http_request_completed)

	if http_version_check:
		if http_version_check.request_completed.is_connected(_on_version_check_completed):
			http_version_check.request_completed.disconnect(_on_version_check_completed)
		http_version_check.request_completed.connect(_on_version_check_completed)

	if file_dialog:
		if file_dialog.dir_selected.is_connected(_on_file_dialog_dir_selected):
			file_dialog.dir_selected.disconnect(_on_file_dialog_dir_selected)
		file_dialog.dir_selected.connect(_on_file_dialog_dir_selected)
	
	_load_launcher_data()
	_update_sidebar_state()
	_check_online_version()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_launcher_data()
	if what == NOTIFICATION_DRAG_BEGIN:
		print("exito!")


func _exit_tree() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()


# ------------------------------------------------------------------------------
# DRAG AND DROP LOGIC
# ------------------------------------------------------------------------------

func _on_files_dropped(files: PackedStringArray) -> void:
	for path in files:
		if DirAccess.dir_exists_absolute(path):
			import_project(path)
			return 


# ------------------------------------------------------------------------------
# VERSION CHECK LOGIC
# ------------------------------------------------------------------------------

func _check_online_version() -> void:
	if not http_version_check: return
	_update_version_label(cached_template_version)
	http_version_check.request(VERSION_CHECK_URL)


func _on_version_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200: return
	
	var text = body.get_string_from_utf8().strip_edges()
	if "version:" in text:
		var split = text.split("version:")
		if split.size() > 1:
			online_template_version = split[1].strip_edges()
			_update_version_label(online_template_version)


func _update_version_label(ver: String) -> void:
	if version_label:
		version_label.text = "Last Version: " + ver


# ------------------------------------------------------------------------------
# UI CONSTRUCTION
# ------------------------------------------------------------------------------

func _setup_overlay_ui() -> void:
	_overlay_bg = ColorRect.new()
	_overlay_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_bg.color = Color(0, 0, 0, 0.85)
	_overlay_bg.visible = false
	_overlay_bg.z_index = 4096
	add_child(_overlay_bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE 
	_overlay_bg.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	_overlay_title = Label.new()
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(_overlay_title)
	
	_overlay_sub = Label.new()
	_overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_sub.add_theme_font_size_override("font_size", 18)
	_overlay_sub.add_theme_color_override("font_color", Color(1, 1, 1, 1)) 
	_overlay_sub.text = "Please wait..."
	vbox.add_child(_overlay_sub)


func _setup_dynamic_dialogs() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Warning"
	_confirm_dialog.dialog_text = "Folder not empty. Continue?"
	_confirm_dialog.confirmed.connect(_on_overwrite_confirmed)
	add_child(_confirm_dialog)

	_remove_dialog = ConfirmationDialog.new()
	_remove_dialog.title = "Remove Project"
	_remove_dialog.confirmed.connect(_on_remove_confirmed)
	var rm_vbox = VBoxContainer.new()
	var rm_lbl = Label.new()
	rm_lbl.text = "Remove project from list?"
	rm_vbox.add_child(rm_lbl)
	_remove_checkbox = CheckBox.new()
	_remove_checkbox.text = "Also delete files from Disk"
	rm_vbox.add_child(_remove_checkbox)
	_remove_dialog.add_child(rm_vbox)
	add_child(_remove_dialog)

	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename Project"
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	var rn_vbox = VBoxContainer.new()
	_rename_input = LineEdit.new()
	_rename_input.custom_minimum_size.x = 300
	rn_vbox.add_child(_rename_input)
	_rename_dialog.add_child(rn_vbox)
	_rename_dialog.visibility_changed.connect(func(): if _rename_dialog.visible: _rename_input.grab_focus())
	add_child(_rename_dialog)


# ------------------------------------------------------------------------------
# OVERLAY HELPERS
# ------------------------------------------------------------------------------

func _show_overlay(title: String, sub_text: String = "") -> void:
	_overlay_title.text = title
	_overlay_sub.text = sub_text if sub_text else "Please wait..."
	_overlay_bg.visible = true
	_overlay_bg.move_to_front()


func _update_overlay_progress(current: int, total: int) -> void:
	_overlay_title.text = "Extracting..."
	_overlay_sub.text = "%d / %d" % [current, total]


func _hide_overlay() -> void:
	_overlay_bg.visible = false


# ------------------------------------------------------------------------------
# UI LOGIC
# ------------------------------------------------------------------------------

func _refresh_ui_list() -> void:
	if not project_container: return
	
	for child in project_container.get_children():
		child.queue_free()
	
	if not item_scene_resource: return
	
	var filtered = []
	if current_filter.is_empty():
		filtered = projects.duplicate()
	else:
		for p in projects:
			if current_filter.to_lower() in p.project_name.to_lower() or current_filter.to_lower() in p.project_path.to_lower():
				filtered.append(p)
	
	_sort_projects_list(filtered)

	for proj in filtered:
		var item = item_scene_resource.instantiate() as ProjectItem
		project_container.add_child(item)
		item.setup(proj)
		item.selected.connect(_on_item_selected)
		item.opened.connect(_on_item_opened)
		
		# FIX: Compare object references, simpler and less error-prone than string paths
		if selected_project and proj == selected_project:
			item.set_is_selected(true)
			if filter_control and not filter_control.has_focus():
				item.call_deferred("grab_focus") 
	
	_update_sidebar_state()


func _sort_projects_list(list: Array) -> void:
	match current_mode:
		OrderMode.NAME: list.sort_custom(func(a, b): return a.project_name.naturalnocasecmp_to(b.project_name) < 0)
		OrderMode.PATH: list.sort_custom(func(a, b): return a.project_path.naturalnocasecmp_to(b.project_path) < 0)
		OrderMode.LAST_EDITED: list.sort_custom(func(a, b): return a.last_modified > b.last_modified)


func _on_item_selected(data: RPGProjectData) -> void:
	selected_project = data
	for child in project_container.get_children():
		# Update UI state for all items
		if child is ProjectItem: child.set_is_selected(child.data == selected_project)
	
	_save_launcher_data()
	_update_sidebar_state()


func _on_item_opened(data: RPGProjectData) -> void:
	selected_project = data
	_save_launcher_data()
	_on_edit_pressed()


func _update_sidebar_state() -> void:
	var has = (selected_project != null)
	if btn_edit: btn_edit.disabled = not has
	if btn_run: btn_run.disabled = not has
	if btn_rename: btn_rename.disabled = not has
	if btn_duplicate: btn_duplicate.disabled = not has
	if btn_remove: btn_remove.disabled = not has


# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

func _on_create_pressed() -> void:
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		file_dialog.title = "Select Folder"
		file_dialog.set_meta("action", "create")
		file_dialog.popup_centered()


func _on_import_pressed() -> void:
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		file_dialog.title = "Import Project"
		file_dialog.set_meta("action", "import")
		file_dialog.popup_centered()


func _on_scan_pressed() -> void:
	if file_dialog:
		file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		file_dialog.title = "Scan Folder"
		file_dialog.set_meta("action", "scan")
		file_dialog.popup_centered()


func _on_edit_pressed() -> void:
	if not selected_project: return
	var exe = OS.get_executable_path()
	OS.create_process(exe, ["--path", selected_project.project_path, "-e"])


func _on_run_pressed() -> void:
	if not selected_project: return
	var exe = OS.get_executable_path()
	OS.create_process(exe, ["--path", selected_project.project_path])


func _on_patreon_pressed() -> void:
	OS.shell_open("https://www.patreon.com/Newold13")


func _on_rename_pressed() -> void:
	if not selected_project: return
	_rename_input.text = selected_project.project_name
	_rename_dialog.popup_centered()


func _on_rename_confirmed() -> void:
	if not selected_project: return
	var new_name = _rename_input.text.strip_edges()
	if new_name.is_empty(): return
	var cfg = ConfigFile.new()
	var path = selected_project.project_path.path_join(CONFIG_FILENAME)
	if cfg.load(path) == OK:
		cfg.set_value("config", "name", new_name)
		cfg.save(path)
	var g_path = selected_project.project_path.path_join("project.godot")
	if cfg.load(g_path) == OK:
		cfg.set_value("application", "config/name", new_name)
		cfg.save(g_path)
	selected_project.project_name = new_name
	_save_launcher_data()
	_refresh_ui_list()


func _on_duplicate_pressed() -> void:
	if not selected_project: return
	var parent = selected_project.project_path.get_base_dir()
	var base = selected_project.project_path.get_file()
	var new_name = base + "_Copy"
	var i = 1
	while DirAccess.dir_exists_absolute(parent.path_join(new_name)):
		new_name = base + "_Copy" + str(i)
		i += 1
	var dest = parent.path_join(new_name)
	_show_overlay("Duplicating...")
	await get_tree().process_frame
	_copy_dir_recursive(selected_project.project_path, dest)
	_hide_overlay()
	import_project(dest)


func _on_remove_pressed() -> void:
	if not selected_project: return
	_remove_checkbox.button_pressed = false
	_remove_dialog.popup_centered()


func _on_remove_confirmed() -> void:
	if not selected_project: return
	remove_project(selected_project, _remove_checkbox.button_pressed)
	selected_project = null
	_update_sidebar_state()


func _on_filter_changed(txt: String) -> void:
	current_filter = txt
	_search_timer.start()


func _on_search_timer_timeout() -> void:
	_refresh_ui_list()


func _on_mode_changed(idx: int) -> void:
	current_mode = idx as OrderMode
	_refresh_ui_list()
	_save_launcher_data()


# ------------------------------------------------------------------------------
# CREATION FLOW
# ------------------------------------------------------------------------------

func _on_file_dialog_dir_selected(dir: String) -> void:
	var act = file_dialog.get_meta("action", "")
	match act:
		"import": import_project(dir)
		"scan": _scan_recursive(dir)
		"create": _initiate_project_check(dir)


func _initiate_project_check(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		var da = DirAccess.open(dir)
		if da:
			da.list_dir_begin()
			var f = da.get_next()
			da.list_dir_end()
			if f != "": 
				_pending_create_path = dir
				_confirm_dialog.popup_centered()
				return
	_start_creation_process(dir)


func _on_overwrite_confirmed() -> void:
	if _pending_create_path != "": _start_creation_process(_pending_create_path)


func _start_creation_process(target: String) -> void:
	var update = (online_template_version != "" and online_template_version != cached_template_version)
	if not FileAccess.file_exists(CACHED_ZIP_PATH) or update:
		_start_download(target)
	else:
		_start_extraction_process(CACHED_ZIP_PATH, target)


func _start_download(target: String) -> void:
	if not http_downloader: return
	http_downloader.set_meta("target_path", target)
	_show_overlay("Downloading...", "Version: " + (online_template_version if online_template_version else "Latest"))
	http_downloader.download_file = CACHED_ZIP_PATH 
	http_downloader.request(TEMPLATE_URL)


func _on_http_request_completed(res: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if res != 0 or code != 200:
		_show_overlay("Download Failed: " + str(code))
		if FileAccess.file_exists(CACHED_ZIP_PATH): DirAccess.remove_absolute(CACHED_ZIP_PATH)
		await get_tree().create_timer(2).timeout
		_hide_overlay()
		return
	if online_template_version != "":
		cached_template_version = online_template_version
		_save_launcher_data()
	_start_extraction_process(CACHED_ZIP_PATH, http_downloader.get_meta("target_path"))


func _start_extraction_process(zip: String, target: String) -> void:
	_show_overlay("Extracting...")
	if _thread.is_started(): _thread.wait_to_finish()
	_thread.start(_threaded_extract.bind([zip, target]))


func _threaded_extract(args: Array) -> void:
	var zip_path = args[0]
	var dest = args[1]
	var zip = ZIPReader.new()
	if zip.open(zip_path) != OK: return
	var files = zip.get_files()
	var root = ""
	if files.size() > 0 and "/" in files[0]: root = files[0].split("/")[0] + "/"
	if not DirAccess.dir_exists_absolute(dest): DirAccess.make_dir_recursive_absolute(dest)
	
	var i = 0
	call_deferred("_update_overlay_progress", 0, files.size())
	for f in files:
		i += 1
		if i % 5 == 0: call_deferred("_update_overlay_progress", i, files.size())
		if f.ends_with("/"): continue
		var clean = f.trim_prefix(root) if root != "" else f
		var final = dest.path_join(clean)
		var base = final.get_base_dir()
		if not DirAccess.dir_exists_absolute(base): DirAccess.make_dir_recursive_absolute(base)
		var content = zip.read_file(f)
		var w = FileAccess.open(final, FileAccess.WRITE)
		if w: w.store_buffer(content)
	zip.close()
	call_deferred("_finalize_creation", dest)


func _finalize_creation(dest: String) -> void:
	if _thread.is_started(): _thread.wait_to_finish()
	_hide_overlay()
	import_project(dest)
	_refresh_ui_list()


# ------------------------------------------------------------------------------
# DATA BACKEND
# ------------------------------------------------------------------------------

func _load_launcher_data() -> void:
	projects.clear()
	if not FileAccess.file_exists(LAUNCHER_DATA_PATH): return
	var f = FileAccess.open(LAUNCHER_DATA_PATH, FileAccess.READ)
	var j = JSON.new()
	if j.parse(f.get_as_text()) != OK: return
	var data = j.data
	var paths = []
	var last_sel = ""
	if data is Array: paths = data
	elif data is Dictionary:
		paths = data.get("projects", [])
		current_mode = data.get("order_mode", 0) as OrderMode
		if order_mode: order_mode.selected = current_mode
		if "window_size" in data:
			var s = data["window_size"]
			var p = data["window_pos"]
			var r = Rect2i(p[0], p[1], s[0], s[1])
			if DisplayServer.screen_get_usable_rect().intersects(r):
				DisplayServer.window_set_position(Vector2i(p[0], p[1]))
				DisplayServer.window_set_size(Vector2i(s[0], s[1]))
		cached_template_version = data.get("template_version", "0.0")
		last_sel = data.get("last_selected_path", "")
	for p in paths:
		var clean = p.replace("\\", "/")
		if _is_valid_project_folder(clean):
			var d = _parse_project_config(clean)
			if d: projects.append(d)
	if not projects.is_empty():
		for p in projects:
			if p.project_path == last_sel:
				selected_project = p
				break
		if not selected_project: selected_project = projects[0]
	_refresh_ui_list()


func _save_launcher_data() -> void:
	var paths = []
	for p in projects: paths.append(p.project_path)
	var s = DisplayServer.window_get_size()
	var p = DisplayServer.window_get_position()
	var d = {
		"projects": paths,
		"order_mode": current_mode,
		"window_size": [s.x, s.y],
		"window_pos": [p.x, p.y],
		"template_version": cached_template_version,
		"last_selected_path": selected_project.project_path if selected_project else ""
	}
	var f = FileAccess.open(LAUNCHER_DATA_PATH, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))


func save_known_projects() -> void: _save_launcher_data()


func import_project(path: String) -> void:
	# Normalize: Standardize separators and lowercase for comparison
	var clean_path = path.replace("\\", "/").rstrip("/")
	var clean_path_lower = clean_path.to_lower()
	
	if not _is_valid_project_folder(clean_path): return
	
	# Clear filter so the selected project is visible
	if current_filter != "":
		current_filter = ""
		if filter_control:
			filter_control.text = ""
	
	# Check for duplicates using lowercase comparison (Windows friendly)
	for proj in projects:
		var existing_clean = proj.project_path.replace("\\", "/").rstrip("/")
		if existing_clean.to_lower() == clean_path_lower:
			selected_project = proj
			_save_launcher_data()
			_refresh_ui_list()
			return # Duplicate found, selected, and refreshed. Stop here.
			
	# Load new
	var data = _parse_project_config(clean_path)
	if data:
		projects.append(data)
		selected_project = data
		_save_launcher_data()
		_refresh_ui_list()


func remove_project(data: RPGProjectData, delete: bool) -> void:
	projects.erase(data)
	if delete: OS.move_to_trash(data.project_path)
	_save_launcher_data()
	_refresh_ui_list()


func _is_valid_project_folder(path: String) -> bool:
	return FileAccess.file_exists(path.path_join(CONFIG_FILENAME))


func _parse_project_config(path: String) -> RPGProjectData:
	var c = ConfigFile.new()
	if c.load(path.path_join(CONFIG_FILENAME)) != OK: return null
	var d = RPGProjectData.new()
	d.project_path = path
	d.project_name = c.get_value("config", "name", "Untitled")
	d.icon_path = c.get_value("config", "icon", "res://icon.svg")
	d.version = c.get_value("config", "version", "0.0.1")
	var t = FileAccess.get_modified_time(path.path_join(CONFIG_FILENAME))
	d.last_modified = Time.get_datetime_string_from_unix_time(t, true)
	return d


func _scan_recursive(dir: String) -> void:
	var d = DirAccess.open(dir)
	if d:
		d.list_dir_begin()
		var f = d.get_next()
		while f != "":
			if d.current_is_dir() and not f.begins_with("."):
				var sub = dir.path_join(f)
				if _is_valid_project_folder(sub): import_project(sub)
				else: _scan_recursive(sub)
			f = d.get_next()


func _copy_dir_recursive(src: String, dst: String) -> void:
	if not DirAccess.dir_exists_absolute(dst): DirAccess.make_dir_recursive_absolute(dst)
	var d = DirAccess.open(src)
	if d:
		d.list_dir_begin()
		var f = d.get_next()
		while f != "":
			if not f.begins_with("."):
				var s_p = src.path_join(f)
				var d_p = dst.path_join(f)
				if d.current_is_dir(): _copy_dir_recursive(s_p, d_p)
				else: d.copy(s_p, d_p)
			f = d.get_next()
