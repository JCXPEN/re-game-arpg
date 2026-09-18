## DataRegistry —— 数据注册中心（Autoload 单例）
##
## 【负责什么】
##   启动时扫描 res://data/ 下的所有 .tres，按类型建索引，提供 O(1) 查询。
##   全项目**唯一**允许知道"数据文件在哪"的地方；其他系统只问它要数据。
##
## 【挂哪个节点】
##   project.godot 的 [autoload] 注册为 `DataRegistry`，在 EventBus 之后初始化。
##
## 【依赖谁】
##   仅依赖各种 *Data 的 class_name。不依赖任何玩法脚本。
##
## 【怎么扩展】
##   新增数据类型：在 SCAN_DIRS 里加目录，在 _index_resource() 里加一个 match 分支，
##   然后加一个 get_xxx() 查询方法。目录扫描用 ResourceLoader.list_directory，
##   它在导出后（.pck 内）同样可用，比 DirAccess 更适合。
##
## 【为什么用目录扫描而不是手写列表】
##   手写列表每加一个 .tres 都要改代码，违背"数据驱动"。扫描让美术/策划只丢文件。
extends Node

# ============================================================================
# 常量
# ============================================================================

## 要扫描的数据目录。新增数据类型时在这里登记。
const SCAN_DIRS: PackedStringArray = [
	"res://data/weapons",
	"res://data/spells",
	"res://data/abilities",
	"res://data/characters",
	"res://data/enemies",
	"res://data/modifiers",
	"res://data/items",
	"res://data/levels",
	"res://data/tutorial",
]
# ============================================================================
# 私有变量
# ============================================================================

## 各类型数据的索引：{ StringName(类型名): { StringName(id): Resource } }
var _index: Dictionary = {}
## 各类型数据的**有序**列表，用于"按 id 稳定遍历"（Dictionary 顺序不保证）。
var _ordered: Dictionary = {}
## 是否已完成扫描。防止其他系统在 _ready 之前查询到空表。
var _ready_flag: bool = false

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# autoload 的 _ready 在任何场景之前执行，所以玩家/敌人一定能查到数据。
	scan_all()
	_ready_flag = true


# ============================================================================
# 公开方法
# ============================================================================

## 重新扫描全部目录。热重载/编辑器调试时可手动调用。
func scan_all() -> void:
	_index.clear()
	_ordered.clear()
	for dir: String in SCAN_DIRS:
		_scan_dir(dir)
	# 扫描结果打印一次，方便确认 .tres 是否被正确识别（缺文件时一眼能看出来）。
	print("[DataRegistry] 已加载 %d 个数据文件，覆盖 %d 个类型" % [_count_all(), _index.size()])


## 按类型与 id 查数据。找不到返回 null，并打印警告（静默失败最难查）。
func get_data(type_name: StringName, id: StringName) -> Resource:
	var bucket: Dictionary = _index.get(type_name, {})
	var res: Resource = bucket.get(id, null)
	if res == null:
		push_warning("[DataRegistry] 找不到 %s:%s" % [type_name, id])
	return res


## 取某类型下所有数据（有序）。
func get_all(type_name: StringName) -> Array:
	return _ordered.get(type_name, [])


## 取某类型下所有 id（有序）。
func get_ids(type_name: StringName) -> Array:
	var out: Array = []
	for res: Resource in get_all(type_name):
		out.append(_resource_id(res))
	return out


## 是否已完成扫描。
func is_ready() -> bool:
	return _ready_flag


# --- 类型化便捷查询（避免调用方到处写字符串，写错了编译期发现不了）----------

func get_weapon(id: StringName) -> WeaponData:
	return get_data(&"WeaponData", id) as WeaponData

func get_spell(id: StringName) -> SpellData:
	return get_data(&"SpellData", id) as SpellData

func get_ability(id: StringName) -> AbilityData:
	return get_data(&"AbilityData", id) as AbilityData

func get_character(id: StringName) -> CharacterData:
	return get_data(&"CharacterData", id) as CharacterData

func get_enemy(id: StringName) -> EnemyData:
	return get_data(&"EnemyData", id) as EnemyData

func get_modifier(id: StringName) -> ModifierData:
	return get_data(&"ModifierData", id) as ModifierData

func get_item(id: StringName) -> ItemData:
	return get_data(&"ItemData", id) as ItemData

func get_level(id: StringName) -> LevelData:
	return get_data(&"LevelData", id) as LevelData


func get_all_weapons() -> Array:
	return get_all(&"WeaponData")

func get_all_spells() -> Array:
	return get_all(&"SpellData")

func get_all_abilities() -> Array:
	return get_all(&"AbilityData")

func get_all_modifiers() -> Array:
	return get_all(&"ModifierData")

func get_all_items() -> Array:
	return get_all(&"ItemData")

func get_all_levels() -> Array:
	return get_all(&"LevelData")


# ============================================================================
# 私有方法
# ============================================================================

## 递归扫描一个目录（含子目录），把每个 .tres 索引进 _index。
func _scan_dir(path: String) -> void:
	# 用 DirAccess 判断目录是否存在。注意不能用 ResourceLoader.exists()——
	# 那是给"资源文件"用的，对目录会返回 false，导致整个扫描被跳过。
	if not DirAccess.dir_exists_absolute(path):
		return
	# list_directory 返回的是"文件名或子目录名"；子目录带结尾 "/"。
	for entry: String in ResourceLoader.list_directory(path):
		var full_path: String = path.path_join(entry)
		if entry.ends_with("/"):
			_scan_dir(full_path)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			_index_resource(full_path)


## 加载单个资源并归类。
func _index_resource(path: String) -> void:
	var res: Resource = ResourceLoader.load(path)
	if res == null:
		push_warning("[DataRegistry] 加载失败：%s" % path)
		return
	var type_name: StringName = res.get_script().get_global_name()
	if type_name == &"":
		# 没写 class_name 的脚本无法归类，直接跳过并提示。
		push_warning("[DataRegistry] %s 的脚本缺少 class_name，已跳过" % path)
		return
	var id: StringName = _resource_id(res, path)
	if id == &"":
		push_warning("[DataRegistry] %s 无法确定 id，已跳过" % path)
		return
	if not _index.has(type_name):
		_index[type_name] = {}
		_ordered[type_name] = []
	if _index[type_name].has(id):
		push_warning("[DataRegistry] id 冲突：%s:%s（后者 %s 被忽略）" % [type_name, id, path])
		return
	_index[type_name][id] = res
	_ordered[type_name].append(res)


## 取一个资源的查询键。
## 优先级：显式 id 字段 > 文件名。
## 为什么用文件名而不是 display_name：display_name 是给玩家看的文本，随时可能
## 翻译/改名，拿它当键会让"改一个中文名就查不到数据"，且不同数据可能重名。
## 文件名（如 sword.tres / m_dragon_heart.tres）天然唯一且稳定。
func _resource_id(res: Resource, path: String = "") -> StringName:
	if res is LevelData:
		return res.id
	if res is ItemData:
		return res.id
	var explicit: StringName = &""
	if res is EnemyData:
		explicit = (res as EnemyData).id
	if explicit != &"":
		return explicit
	if path != "":
		return StringName(path.get_file().get_basename())
	return &""


## 统计已索引的资源总数（仅用于启动日志）。
func _count_all() -> int:
	var total: int = 0
	for bucket: Dictionary in _index.values():
		total += bucket.size()
	return total
