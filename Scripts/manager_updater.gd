class_name ManagerUpdater
extends Node

## Auto-Updater for the Compiled Manager (EXE).
## Checks GitHub Releases tags. If a new tag is found, downloads the ZIP asset and replaces the EXE.

signal update_status(msg: String)
signal update_error(msg: String)

# CONFIGURACIÓN DEL REPO DEL MANAGER
const MANAGER_REPO_OWNER: String = "newold3"
const MANAGER_REPO_NAME: String = "Godot-RPG-Creator-Launcher" # Pon aquí el nombre real del repo del Manager

# CONSTANTES INTERNAS
const TEMP_ZIP_PATH: String = "user://manager_update.zip"
const TEMP_EXTRACT_PATH: String = "user://manager_temp_extract/"

# REFERENCIA DE VERSIÓN ACTUAL (Hardcoded o desde ProjectSettings)
# Sugerencia: Usa ProjectSettings.get_setting("application/config/version")
var current_version: String = "0.85" 

var _http: HTTPRequest
var _thread: Thread
var _new_version_tag: String = ""

func _ready() -> void:
	# Intentar leer la versión desde la configuración del proyecto exportado
	var proj_ver = ProjectSettings.get_setting("application/config/version")
	if proj_ver: current_version = str(proj_ver)
	
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_release_info_received)

func check_updates() -> void:
	update_status.emit("Checking for Manager updates...")
	# Consultamos el endpoint de "Latest Release" de GitHub
	var url = "https://api.github.com/repos/%s/%s/releases/latest" % [MANAGER_REPO_OWNER, MANAGER_REPO_NAME]
	_http.request(url)

func _on_release_info_received(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		update_error.emit("Connection Error: " + str(code))
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json or not json.has("tag_name"):
		update_error.emit("Invalid GitHub response")
		return
		
	_new_version_tag = json["tag_name"] # Ej: "v0.85a" o "0.85a"
	
	# Limpieza de strings para comparar (quitar la 'v' si existe)
	var local_clean = current_version.replace("v", "")
	var remote_clean = _new_version_tag.replace("v", "")
	
	if local_clean == remote_clean:
		update_status.emit("Manager is up to date.")
		# Opcional: Emitir señal de finalizar
		return
	
	# --- LÓGICA DE ACTUALIZACIÓN ---
	update_status.emit("New version found: %s. Downloading..." % _new_version_tag)
	
	# Buscar el asset ZIP en la respuesta JSON
	var assets = json.get("assets", [])
	var download_url = ""
	
	for asset in assets:
		# Buscamos un zip. Puedes filtrar por nombre si subes varios archivos (ej: "Manager_Win.zip")
		if asset["name"].ends_with(".zip"):
			download_url = asset["browser_download_url"]
			break
	
	if download_url == "":
		update_error.emit("No ZIP asset found in release.")
		return
		
	_start_zip_download(download_url)

func _start_zip_download(url: String) -> void:
	# Desconectar señal anterior y reconectar a la de descarga
	for sig in _http.request_completed.get_connections():
		_http.request_completed.disconnect(sig.callable)
	
	_http.request_completed.connect(_on_zip_downloaded)
	_http.request(url)

func _on_zip_downloaded(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		update_error.emit("Failed to download update ZIP.")
		return
		
	var f = FileAccess.open(TEMP_ZIP_PATH, FileAccess.WRITE)
	if f:
		f.store_buffer(body)
		f.close()
		update_status.emit("Extracting update...")
		_thread = Thread.new()
		_thread.start(_threaded_extraction)
	else:
		update_error.emit("Write error (Permission denied?).")

func _threaded_extraction() -> void:
	if DirAccess.dir_exists_absolute(TEMP_EXTRACT_PATH):
		DirAccess.remove_absolute(TEMP_EXTRACT_PATH) # Limpieza previa
	DirAccess.make_dir_recursive_absolute(TEMP_EXTRACT_PATH)
	
	var zip = ZIPReader.new()
	if zip.open(TEMP_ZIP_PATH) != OK:
		call_deferred("emit_signal", "update_error", "Corrupt ZIP file.")
		return
		
	var files = zip.get_files()
	for path in files:
		if path.ends_with("/"): continue # Ignorar carpetas vacías
		
		# Leer y escribir en carpeta temporal
		var content = zip.read_file(path)
		var dest_path = TEMP_EXTRACT_PATH.path_join(path)
		
		# Asegurar que existan subcarpetas
		var base_dir = dest_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(base_dir):
			DirAccess.make_dir_recursive_absolute(base_dir)
			
		var f = FileAccess.open(dest_path, FileAccess.WRITE)
		if f: f.store_buffer(content)
	
	zip.close()
	call_deferred("_create_and_run_bat")

func _create_and_run_bat() -> void:
	update_status.emit("Restarting to apply updates...")
	
	# RUTAS GLOBALES PARA WINDOWS
	var bat_path = ProjectSettings.globalize_path("user://manager_updater.bat")
	var temp_folder_win = ProjectSettings.globalize_path(TEMP_EXTRACT_PATH).replace("/", "\\")
	# Aquí está la clave: La carpeta donde está el EXE actual
	var install_folder_win = OS.get_executable_path().get_base_dir().replace("/", "\\")
	var exe_name = OS.get_executable_path().get_file() # Ej: "Manager.exe"
	
	# SCRIPT DE ACTUALIZACIÓN (.BAT)
	# 1. Espera 3 segundos para que Godot se cierre.
	# 2. Mueve todo lo descomprimido a la carpeta de instalación (sobrescribe el EXE).
	# 3. Borra los temporales.
	# 4. Vuelve a arrancar el Manager.
	
	var script = "@echo off\r\n"
	script += "timeout /t 3 /nobreak > NUL\r\n"
	script += 'xcopy "%s\\*" "%s" /Y /S /E /I /R /H\r\n' % [temp_folder_win, install_folder_win]
	script += 'rmdir /s /q "%s"\r\n' % temp_folder_win
	script += 'del "%s"\r\n' % ProjectSettings.globalize_path(TEMP_ZIP_PATH).replace("/", "\\")
	script += 'start "" "%s\\%s"\r\n' % [install_folder_win, exe_name]
	script += '(goto) 2>nul & del "%~f0"' # Auto-borrado del bat
	
	FileAccess.open(bat_path, FileAccess.WRITE).store_string(script)
	
	# Ejecutar BAT y cerrar Manager
	OS.create_process("cmd.exe", ["/c", bat_path])
	get_tree().quit()
