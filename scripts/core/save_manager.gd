## SaveManager —— 存档读写服务（Autoload 单例）
##
## 【负责什么】
##   **只做一件事**：把一份"可 JSON 化的字典"写进磁盘 / 从磁盘读出来。它不认识
##   GameState 的字段，也不知道"金币"是什么——那些是**状态**的知识，留在状态持有者那边。
##
## 【为什么要把 IO 从 GameState 里拆出来 —— 对照官方文档】
##   Godot 官方《Scene organization》："Systems that modify other systems' data should be
##   regular scripts/scenes, not autoloads."，而《Singletons》又说 autoload 适合
##   "store global variables"。两者合起来的正确切分是：
##     · 状态持有者（GameState）—— 存字段、做游戏语义变更；
##     · 存档服务（本文件）—— 只负责持久化 IO。
##   混在一起时，任何"想测状态"的代码都会被文件系统拖累；拆开后状态可以脱离磁盘被断言。
##
## 【为什么不命名成 GlobalState / 不做成 game_state 的一部分】
##   名字直白表达职责：它是"保存/读取的管理者"，不是"游戏状态本身"。
##
## 【为什么不做成 class_name】注册为 autoload `SaveManager`，同名 class_name 会冲突。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 存档格式版本。字段结构变了就 +1，读取时用于迁移或丢弃旧档。
const SAVE_VERSION: int = 1
## 存档路径（默认存到用户目录，导出后也可写）。
const SAVE_PATH: String = "user://savegame.json"

# ============================================================================
# 公开方法
# ============================================================================

## 是否已经存在一份存档文件。
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 把字典写入存档文件。成功返回 true，失败打印告警并返回 false。
func write(data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("[SaveManager] 存档写入失败：%s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


## 读出存档字典。文件不存在 / 损坏 / 版本不符都返回空字典（调用方自行决定兜底）。
##
## 【为什么把版本校验也放在这里】存档头（version 字段）是"存档格式"的一部分，
##   属于 IO 层知识；状态持有者只关心"给我一份干净的字段"。旧版本直接丢弃（原型期不迁移）。
func read() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveManager] 存档损坏，已忽略")
		return {}
	var data: Dictionary = parsed as Dictionary
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("[SaveManager] 存档版本不匹配（%s≠%s），已忽略"
			% [data.get("version", 0), SAVE_VERSION])
		return {}
	return data


## 删除存档（调试 / 新档用）。
func delete_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_warning("[SaveManager] 删除存档失败：%d" % err)
