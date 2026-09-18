## ModifierSystem —— Roguelite 词条系统（Autoload 单例）
##
## 【负责什么】
##   一局游戏内的词条收集与结算。它把玩家选到的所有词条累加成一个"属性乘区表"，
##   任何要读属性的地方（伤害、移速、冷却）都通过它取值。
##
## 【挂哪个节点】
##   project.godot 的 [autoload] 注册为 `ModifierSystem`。
##
## 【依赖谁】
##   ModifierData、GameState（记录本局已选词条）、EventBus。
##
## 【怎么扩展】
##   新词条机制 = 在 GameEnums.ModifierTarget 里加枚举 + 在 _matches_context 里加分支。
##   数值结算顺序固定为 FLAT → PERCENT → MULTIPLY，不能改，
##   否则同样的词条组合会算出不同结果（玩家会认为有 bug）。
##
## 【为什么单独做一层而不是直接改 CharacterData】
##   CharacterData 是 .tres 资源，运行时改它会污染资源文件（甚至被存盘）。
##   词条是"临时叠加层"，必须独立存放，run 结束直接丢弃。
##
## 【上下文过滤 —— 关键设计】
##   词条有作用域：`巨力` 只对双手武器生效、`烈焰精通` 只对火系法术生效。
##   所以取值时必须带上"当前在算什么"的上下文（武器类别 / 元素）。
##   乘区表按上下文分别缓存（`_cache`），否则一把铁剑也会吃到双手词条的加成。
extends Node

# ============================================================================
# 信号
# ============================================================================

## 词条被选中后发出，UI 刷新用。
signal modifier_added(modifier: ModifierData, stacks: int)

# ============================================================================
# 私有变量
# ============================================================================

## 本局已选词条：{ StringName(key): { data: ModifierData, stacks: int } }。
## key 用资源路径，而不是 display_name——同名不同源的词条（如两个"龙之心"）
## 用显示名做键会互相覆盖，第二个直接消失。
var _owned: Dictionary = {}
## 按上下文缓存的乘区表：{ String(context_key): { StatKind: {flat,percent,multiply} } }。
var _cache: Dictionary = {}
## 是否有新词条导致缓存失效。
var _dirty: bool = true

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)


# ============================================================================
# 公开方法
# ============================================================================

## 添加一个词条（三选一 UI 选中后调用）。
## id 为可选显式键；不传则用资源路径。
func add_modifier(modifier: ModifierData, id: StringName = &"") -> void:
	if modifier == null:
		return
	var key: StringName = id
	if key == &"":
		key = _key_for(modifier)
	var entry: Dictionary = _owned.get(key, { "data": modifier, "stacks": 0 })
	# 检查叠加上限。
	var max_stacks: int = modifier.max_stacks
	if max_stacks > 0 and int(entry["stacks"]) >= max_stacks:
		return
	entry["stacks"] = int(entry["stacks"]) + 1
	_owned[key] = entry
	_dirty = true
	_cache.clear()
	# 同步到 GameState（存档/结算展示用）。
	_sync_to_game_state()
	modifier_added.emit(modifier, int(entry["stacks"]))
	EventBus.modifier_chosen.emit(modifier)
	if modifier.pick_sfx != null:
		AudioManager.play_sfx(modifier.pick_sfx)


## 取某属性的最终乘区（按上下文过滤）。
## 用法：最终值 = (基础 + FLAT) * (1 + PERCENT) * MULTIPLY
func get_stat_multiplier(stat: GameEnums.StatKind, context: Dictionary = {}) -> Dictionary:
	_rebuild_if_dirty(context)
	# 缓存结构是 { 上下文键: { StatKind: { mods: {...} } } }，要分两层取。
	var table: Dictionary = _cache.get(_context_key(context), {})
	var bucket: Dictionary = table.get(stat, {})
	return bucket.get("mods", { "flat": 0.0, "percent": 0.0, "multiply": 1.0 })


## 直接算出一个属性的最终值。base 为角色基础属性，context 决定哪些词条生效。
func apply_stat(base: float, stat: GameEnums.StatKind, context: Dictionary = {}) -> float:
	var mods: Dictionary = get_stat_multiplier(stat, context)
	return (base + mods["flat"]) * (1.0 + mods["percent"]) * mods["multiply"]


## 本局已选词条列表（结算/UI 用）。
func get_owned_list() -> Array:
	return _owned.values()


## 已拥有的词条数量。
func get_owned_count() -> int:
	return _owned.size()


## 抽取 count 个候选词条（三选一 UI 用）。
## 按 weight 加权随机，已满层的词条不再出现。
func roll_candidates(count: int = 3) -> Array[ModifierData]:
	var pool: Array[ModifierData] = []
	var weights: PackedFloat32Array = PackedFloat32Array()
	for res: Resource in DataRegistry.get_all_modifiers():
		var mod: ModifierData = res as ModifierData
		if mod == null:
			continue
		# 满层的不再出现。
		if mod.max_stacks > 0 and _stacks_of(mod) >= mod.max_stacks:
			continue
		if mod.weight <= 0.0:
			continue
		pool.append(mod)
		weights.append(mod.weight)
	var picked: Array[ModifierData] = []
	# 不放回抽样，避免三选一出现重复词条。
	for i: int in count:
		if pool.is_empty():
			break
		var total: float = 0.0
		for w: float in weights:
			total += w
		var roll: float = randf() * total
		var idx: int = 0
		var acc: float = 0.0
		for j: int in weights.size():
			acc += weights[j]
			if roll <= acc:
				idx = j
				break
		picked.append(pool[idx])
		pool.remove_at(idx)
		weights.remove_at(idx)
	return picked


## 清空本局词条（run 结束时调用）。
func clear() -> void:
	_owned.clear()
	_cache.clear()
	_dirty = true


# ============================================================================
# 私有方法
# ============================================================================

## 词条的稳定键。优先资源路径（唯一且稳定），运行时临时资源退化为实例 id。
func _key_for(modifier: ModifierData) -> StringName:
	if modifier.resource_path != "":
		return StringName(modifier.resource_path)
	# 运行时用代码 new 出来的词条（测试探针）没有路径，用实例 id 兜底。
	return StringName("__runtime_%d" % modifier.get_instance_id())


## 取某词条当前叠层数。
func _stacks_of(modifier: ModifierData) -> int:
	var entry: Dictionary = _owned.get(_key_for(modifier), {})
	return int(entry.get("stacks", 0))


## 上下文 → 缓存键。
func _context_key(context: Dictionary) -> String:
	var weapon: int = int(context.get(&"weapon_kind", -1))
	var element: int = int(context.get(&"element", 0))
	var trigger: String = String(context.get(&"trigger", &""))
	return "%d|%d|%s" % [weapon, element, trigger]


## 按需重算乘区表（按上下文分别缓存）。
func _rebuild_if_dirty(context: Dictionary) -> void:
	# 有新词条时整个缓存作废；否则命中缓存直接返回。
	if _dirty:
		_cache.clear()
		_dirty = false
	var key: String = _context_key(context)
	if _cache.has(key):
		return
	var table: Dictionary = {}
	for entry: Dictionary in _owned.values():
		var mod: ModifierData = entry["data"]
		if not _matches_context(mod, context):
			continue
		var stacks: int = int(entry["stacks"])
		var amount: float = _stacked_value(mod, stacks)
		if not table.has(mod.stat):
			table[mod.stat] = { "mods": { "flat": 0.0, "percent": 0.0, "multiply": 1.0 } }
		var bucket: Dictionary = table[mod.stat]["mods"]
		match mod.op:
			GameEnums.ModifierOp.FLAT:
				bucket["flat"] += amount
			GameEnums.ModifierOp.PERCENT:
				bucket["percent"] += amount
			GameEnums.ModifierOp.MULTIPLY:
				# 乘法词条按 value^层数 叠乘（value 是倍率本身）。
				bucket["multiply"] *= pow(mod.value, float(stacks))
	_cache[key] = table


## 词条在当前上下文下是否生效。
func _matches_context(mod: ModifierData, context: Dictionary) -> bool:
	match mod.target:
		GameEnums.ModifierTarget.STAT:
			return true
		GameEnums.ModifierTarget.WEAPON:
			# 未限定武器类别 = 对所有武器生效。
			if mod.weapon_kinds.is_empty():
				return true
			var kind: int = int(context.get(&"weapon_kind", -1))
			return kind >= 0 and mod.weapon_kinds.has(kind)
		GameEnums.ModifierTarget.ABILITY:
			# 未限定元素 = 对所有法术生效。
			if mod.elements.is_empty():
				return true
			var element: int = int(context.get(&"element", 0))
			return element != 0 and mod.elements.has(element)
		GameEnums.ModifierTarget.GLOBAL:
			# 全局规则类（如"残血增伤"）只在对应触发标签下生效。
			if mod.trigger_tag == &"":
				return true
			return mod.trigger_tag == StringName(context.get(&"trigger", &""))
		_:
			return true


## 词条在 stacks 层时的数值。
## 正确公式：n*value + value_per_stack * n*(n-1)/2
## （第 k 层的增量是 value + value_per_stack*(k-1)，对 k=1..n 求和）。
## 旧写法 (value + vps*(n-1)) * n 把增量多乘了一遍。
func _stacked_value(mod: ModifierData, stacks: int) -> float:
	var n: float = float(stacks)
	return n * mod.value + mod.value_per_stack * n * (n - 1.0) * 0.5


## 把本局词条同步进 GameState（用于结算界面与存档）。
func _sync_to_game_state() -> void:
	GameState.run_modifiers.clear()
	for key: StringName in _owned.keys():
		var entry: Dictionary = _owned[key]
		GameState.run_modifiers.append({
			"id": String(key),
			"stacks": int(entry["stacks"]),
		})


# ============================================================================
# 信号回调
# ============================================================================

func _on_run_started() -> void:
	clear()
