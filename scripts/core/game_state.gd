## GameState —— 全局运行状态（Autoload 单例）
##
## 【负责什么】
##   保存"跨场景存活"的东西：局外解锁进度、当前一局的临时状态、玩家存档数据。
##   注意：局内构筑（词条）在 run 结束时清零，局外解锁不清零——这是本作的
##   核心设计边界，务必分清。
##
## 【职责边界：状态 vs 存档 IO】
##   本文件只做"**状态的持有与游戏语义变更**"（加金币 = 改数值 + 发信号）。
##   真正的磁盘读写（JSON 序列化、版本校验、文件路径）**委托给 `SaveManager`**。
##   切分依据见 SaveManager 文件头（对照官方"autoload 适合存全局变量 / 修改他人数据
##   的系统应为普通脚本"两条）：状态可以被独立断言，IO 可以被独立替换/测试。
##
## 【挂哪个节点】
##   project.godot 的 [autoload] 注册为 `GameState`。
##
## 【依赖谁】
##   EventBus（广播状态变化）、SaveManager（持久化）。不直接引用玩家节点。
##
## 【怎么扩展】
##   新增需要持久化的字段时，加进 _serialize/_deserialize，并升 SaveManager.SAVE_VERSION。
##   不要在这里直接操作玩家节点——那会破坏"跨系统不互相持有引用"的约定。
extends Node

# ============================================================================
# 常量（转发到 SaveManager，保持既有调用点如 GameState.SAVE_PATH 可用）
# ============================================================================

## 存档格式版本（真源在 SaveManager）。
const SAVE_VERSION: int = SaveManager.SAVE_VERSION
## 存档路径（真源在 SaveManager）。
const SAVE_PATH: String = SaveManager.SAVE_PATH

# ============================================================================
# 局外（永久）数据
# ============================================================================

## 已解锁的法术 id 列表。局外只做解锁，不做数值成长。
var unlocked_spells: Array[StringName] = []
## 已解锁的技能 id 列表。
var unlocked_abilities: Array[StringName] = []
## 已解锁的武器 id 列表。
var unlocked_weapons: Array[StringName] = []
## 累计金币（跨局保留）。
var gold: int = 0
## 已击败过的 Boss id，用于剧情推进与关卡解锁。
var defeated_bosses: Array[StringName] = []
## 最高到达的关卡 id。
var furthest_level: StringName = &""

# ============================================================================
# 局内（临时）数据——run 结束清零
# ============================================================================

## 本局已选择的词条：Array[{ id: StringName, stacks: int }]。
var run_modifiers: Array[Dictionary] = []
## 本局是否进行中。
var run_active: bool = false
## 本局内击杀数（结算展示用）。
var run_kills: int = 0
## 本局耗时（秒）。
var run_time: float = 0.0
## 复活点所在关卡 id（空表示未设置）。
var respawn_level: StringName = &""
## 复活点坐标。
var respawn_position: Vector2 = Vector2.ZERO
## 是否已看过新手教程（跨局保留，避免每次开新档都重看）。
var tutorial_completed: bool = false
## 背包：{ StringName(item_id): int(count) }。
var inventory: Dictionary = {}
## 已开启过的宝箱 id。宝箱只靠实例内的 _used 记状态，不落盘 →
## 死亡重进 / 换关回来就能无限重复领取金币与物品。
## 这里用"一次性奖励格子"做持久化，钥匙字符串由关卡名 + 宝箱 id 组成。
var opened_chests: Dictionary = {}

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	load_game()


func _process(delta: float) -> void:
	# 只在局内累计时间，避免主菜单停留时间被算进成绩。
	if run_active:
		run_time += delta


# ============================================================================
# 公开方法 —— 一局的生命周期
# ============================================================================

## 开始新的一局：清空局内数据。
func start_run() -> void:
	run_modifiers.clear()
	run_kills = 0
	run_time = 0.0
	run_active = true
	EventBus.run_started.emit()


## 结束当前一局：按设计"局内构筑清零，局外保留"。
func end_run(victory: bool) -> void:
	run_active = false
	run_modifiers.clear()
	EventBus.run_ended.emit(victory)
	save_game()


## 记录一次击杀。
func register_kill() -> void:
	run_kills += 1


## 记录一个 Boss 被击败（同时写入局外解锁）。
func register_boss_defeat(boss_id: StringName) -> void:
	if boss_id == &"" or defeated_bosses.has(boss_id):
		return
	defeated_bosses.append(boss_id)
	EventBus.boss_defeated.emit(boss_id)
	save_game()


## 添加物品到背包。
##
## 【为什么这里要写盘】`add_item` / `add_gold` 是"关键收益点"（宝箱、掉落、购买）。
##   旧实现全项目只有 end_run / register_boss_defeat / save_point / 教程 4 处 save_game()，
##   而 end_run 只在通关或死亡结算时调用（且不在"返回主菜单"路径上）。
##   于是玩家开了箱子、拿了装备之后直接关窗，进度全丢。
##   收益点即时落盘，代价是一点 IO，但对"关掉就没了"是唯一可靠的解法。
func add_item(item_id: StringName, count: int = 1) -> void:
	if item_id == &"" or count <= 0:
		return
	inventory[item_id] = int(inventory.get(item_id, 0)) + count
	EventBus.item_acquired.emit(item_id, count)
	save_game()


## 移除物品。数量不足返回 false。
func remove_item(item_id: StringName, count: int = 1) -> bool:
	var have: int = int(inventory.get(item_id, 0))
	if have < count:
		return false
	var left: int = have - count
	if left <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = left
	return true


## 是否持有某物品。
func has_item(item_id: StringName, count: int = 1) -> bool:
	return int(inventory.get(item_id, 0)) >= count


## 取某物品数量。
func get_item_count(item_id: StringName) -> int:
	return int(inventory.get(item_id, 0))


## 背包条目列表（UI 用）：Array[{ id, count, data }]。
func get_inventory_entries() -> Array:
	var out: Array = []
	for id: StringName in inventory.keys():
		out.append({
			"id": id,
			"count": int(inventory[id]),
			"data": DataRegistry.get_item(id),
		})
	return out


## 记录复活点（存档点交互时调用）。死亡后从这里重生。
func set_respawn_point(level_id: StringName, position: Vector2) -> void:
	respawn_level = level_id
	respawn_position = position


## 取复活点。未设置过则返回空关卡 id（表示回起点）。
func get_respawn_point() -> Dictionary:
	return { "level": respawn_level, "position": respawn_position }


# ============================================================================
# 公开方法 —— 解锁与货币
# ============================================================================

func unlock_spell(id: StringName) -> void:
	if not unlocked_spells.has(id):
		unlocked_spells.append(id)

func unlock_ability(id: StringName) -> void:
	if not unlocked_abilities.has(id):
		unlocked_abilities.append(id)

func unlock_weapon(id: StringName) -> void:
	if not unlocked_weapons.has(id):
		unlocked_weapons.append(id)

func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	save_game()


# --- 宝箱一次性状态 ---------------------------------------------------------

## 某个宝箱是否已开过。key 建议用 `"<关卡id>/<宝箱id>"` 保证跨关卡唯一。
func is_chest_opened(chest_key: StringName) -> bool:
	return chest_key != &"" and opened_chests.has(chest_key)


## 标记宝箱已开（并落盘，防重复领取）。
func mark_chest_opened(chest_key: StringName) -> void:
	if chest_key == &"" or opened_chests.has(chest_key):
		return
	opened_chests[chest_key] = true
	save_game()


func is_boss_defeated(boss_id: StringName) -> bool:
	return defeated_bosses.has(boss_id)


# ============================================================================
# 公开方法 —— 存档
# ============================================================================

## 把当前状态落盘。IO 委托给 SaveManager（版本头由它写入）。
func save_game() -> void:
	SaveManager.write(_serialize())


## 从磁盘读取并套用。文件缺失 / 损坏 / 版本不符时保持当前状态不变。
func load_game() -> void:
	var data: Dictionary = SaveManager.read()
	if data.is_empty():
		return
	_deserialize(data)


## 清空存档（调试/新档用）。
##
## 【为什么要把局内数据一起清】旧实现只清了局外字段，漏掉 run_modifiers /
##   run_kills / run_time / run_active —— 新档开局时上一局的击杀数与倒计时还在，
##   结算界面会显示一串不属于本局的数字。
##   另外 ModifierSystem 持有自己的一份 _owned 副本，不通知它就等于"新档带着旧词条"。
func reset_save() -> void:
	# --- 局外 ---
	unlocked_spells.clear()
	unlocked_abilities.clear()
	unlocked_weapons.clear()
	defeated_bosses.clear()
	opened_chests.clear()
	gold = 0
	furthest_level = &""
	respawn_level = &""
	respawn_position = Vector2.ZERO
	tutorial_completed = false
	inventory.clear()
	# --- 局内 ---
	run_modifiers.clear()
	run_kills = 0
	run_time = 0.0
	run_active = false
	# 词条系统自己缓存了一份持有列表，必须同步重置，否则新档一起步就带旧构筑。
	if ModifierSystem.has_method(&"clear"):
		ModifierSystem.call(&"clear")
	save_game()


# ============================================================================
# 私有方法
# ============================================================================

## 把永久数据打包成可 JSON 化的字典（JSON 不支持 StringName，统一转 String）。
func _serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"gold": gold,
		"furthest_level": String(furthest_level),
		"unlocked_spells": _to_string_array(unlocked_spells),
		"unlocked_abilities": _to_string_array(unlocked_abilities),
		"unlocked_weapons": _to_string_array(unlocked_weapons),
		"defeated_bosses": _to_string_array(defeated_bosses),
		"respawn_level": String(respawn_level),
		"respawn_position": [respawn_position.x, respawn_position.y],
		"tutorial_completed": tutorial_completed,
		"inventory": _serialize_inventory(),
		"opened_chests": opened_chests.keys().duplicate(),
	}


func _deserialize(data: Dictionary) -> void:
	# 版本不符直接丢弃，原型阶段不做迁移。
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("[GameState] 存档版本不匹配，已忽略")
		return
	gold = int(data.get("gold", 0))
	furthest_level = StringName(str(data.get("furthest_level", "")))
	unlocked_spells = _from_string_array(data.get("unlocked_spells", []))
	unlocked_abilities = _from_string_array(data.get("unlocked_abilities", []))
	unlocked_weapons = _from_string_array(data.get("unlocked_weapons", []))
	defeated_bosses = _from_string_array(data.get("defeated_bosses", []))
	respawn_level = StringName(str(data.get("respawn_level", "")))
	var rp: Variant = data.get("respawn_position", [0, 0])
	if typeof(rp) == TYPE_ARRAY and (rp as Array).size() == 2:
		respawn_position = Vector2(float(rp[0]), float(rp[1]))
	tutorial_completed = bool(data.get("tutorial_completed", false))
	inventory.clear()
	var inv: Variant = data.get("inventory", {})
	if typeof(inv) == TYPE_DICTIONARY:
		for key: Variant in (inv as Dictionary).keys():
			inventory[StringName(str(key))] = int((inv as Dictionary)[key])
	opened_chests.clear()
	var chests: Variant = data.get("opened_chests", [])
	if typeof(chests) == TYPE_ARRAY:
		for key: Variant in (chests as Array):
			opened_chests[StringName(str(key))] = true


## 把背包转成可 JSON 化的字典（StringName 键要转成 String）。
func _serialize_inventory() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in inventory.keys():
		out[String(id)] = int(inventory[id])
	return out


func _to_string_array(arr: Array[StringName]) -> Array:
	var out: Array = []
	for v: StringName in arr:
		out.append(String(v))
	return out


func _from_string_array(arr: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(arr) != TYPE_ARRAY:
		return out
	for v: Variant in arr:
		out.append(StringName(str(v)))
	return out
