## SettingsService —— 玩家设置（音量 / 显示）的读写与应用（Autoload 单例）
##
## 【负责什么】
##   1. 从 `user://settings.cfg` 读 / 写设置（**只做 IO 与存储格式**）。
##   2. 把设置**应用到引擎**（AudioServer 总线音量、DisplayServer 显示模式）。
##   面板（SettingsPanel）只负责"把当前值画出来、把玩家改动交给本服务"。
##
## 【为什么要把设置逻辑从面板里拆出来 —— 单一职责】
##   旧实现的 `settings_panel.gd` 同时在做三件事：画 UI、读写配置文件、改音频/显示。
##   于是"想单独测设置持久化"就必须先造一个 UI。
##   拆开后：本服务可脱离界面被断言（见 settings_contract_test），面板只渲染。
##
## 【为什么音量用 0..1 线性值，而不是分贝】
##   分贝对玩家没有意义，且 dB 曲线的听感不是线性的（低半段几乎听不出差别）。
##   存线性值、用时转换，旁边还能直接显示百分比——这是通行做法。
##
## 【为什么不做成 class_name】注册为 autoload `SettingsService`，同名 class_name 会冲突。
extends Node

# ============================================================================
# 常量
# ============================================================================

const SETTINGS_PATH: String = "user://settings.cfg"

# ============================================================================
# 私有变量
# ============================================================================

## 当前设置（线性音量 0..1）。
var _master: float = 1.0
var _sfx: float = 1.0
var _music: float = 1.0
var _fullscreen: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_and_apply()

# ============================================================================
# 公开方法 —— 读写
# ============================================================================

## 从磁盘读取全部设置并应用。文件缺失时用默认值。
func load_and_apply() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var ok: bool = cfg.load(SETTINGS_PATH) == OK
	if ok:
		_master = _read_linear(cfg, "master", _master)
		_sfx = _read_linear(cfg, "sfx", _sfx)
		_music = _read_linear(cfg, "music", _music)
		_fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	apply_all()


## 写盘（不改变已应用的值；改值请用 set_* 系列）。
func save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("volume", "master", _master)
	cfg.set_value("volume", "sfx", _sfx)
	cfg.set_value("volume", "music", _music)
	cfg.set_value("display", "fullscreen", _fullscreen)
	var err: int = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("[SettingsService] 设置写入失败：%d" % err)


## 设置三个音量（线性 0..1），立即生效并落盘。
func set_volumes(master: float, sfx: float, music: float) -> void:
	_master = clampf(master, 0.0, 1.0)
	_sfx = clampf(sfx, 0.0, 1.0)
	_music = clampf(music, 0.0, 1.0)
	apply_all()
	save()


## 设置全屏并立即生效 + 落盘。
func set_fullscreen(on: bool) -> void:
	_fullscreen = on
	apply_display()
	save()

# ============================================================================
# 公开方法 —— 查询
# ============================================================================

func master_volume() -> float:
	return _master

func sfx_volume() -> float:
	return _sfx

func music_volume() -> float:
	return _music

func is_fullscreen() -> bool:
	return _fullscreen

# ============================================================================
# 公开方法 —— 应用
# ============================================================================

## 把当前设置全部应用到引擎。可在外部状态被改动后重新调用（幂等）。
func apply_all() -> void:
	apply_audio()
	apply_display()


func apply_audio() -> void:
	var master_idx: int = AudioServer.get_bus_index(&"Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db_safe(_master))
	AudioManager.set_sfx_volume(linear_to_db_safe(_sfx))
	AudioManager.set_music_volume(linear_to_db_safe(_music))


func apply_display() -> void:
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# ============================================================================
# 私有方法
# ============================================================================

## 读一个线性音量。兼容旧版按分贝存的键（audio/master_db 等）。
func _read_linear(cfg: ConfigFile, key: String, fallback: float) -> float:
	if cfg.has_section_key("volume", key):
		return clampf(float(cfg.get_value("volume", key, fallback)), 0.0, 1.0)
	var old_key: String = key + "_db"
	if cfg.has_section_key("audio", old_key):
		return clampf(db_to_linear(float(cfg.get_value("audio", old_key, 0.0))), 0.0, 1.0)
	return fallback


## 线性音量 → 分贝。0 会得到 -inf，用 -80dB 代替（等于静音但仍是合法数值）。
static func linear_to_db_safe(linear: float) -> float:
	if linear <= 0.0:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))
