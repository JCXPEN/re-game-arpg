## AudioManager —— 音频服务（Autoload 单例）
##
## 【负责什么】
##   统一播放音效与音乐，自动管理音效播放器池（避免每次播放都 new 一个节点），
##   并提供音量总线控制。游戏逻辑只管喊"播这个音"，不关心播放器怎么来的。
##
## 【挂哪个节点】
##   project.godot 的 [autoload] 注册为 `AudioManager`。
##
## 【依赖谁】
##   EventBus（可选，用于统一提示音）。
##
## 【怎么扩展】
##   需要 3D/位置音效时加 play_sfx_at(position, stream)，给播放器设 panning。
##   不要为每种音效各写一个函数。
extends Node

# ============================================================================
# @export
# ============================================================================

## 音效播放器池大小。同时播放超过这个数量的音效会被丢弃（防止爆音）。
@export_range(1, 64, 1) var sfx_pool_size: int = 16
## 音效总音量（分贝）。
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var sfx_volume_db: float = -6.0
## 音乐总音量（分贝）。
@export_range(-60.0, 6.0, 0.5, "suffix:dB") var music_volume_db: float = -10.0
## 音效随机音调范围（±），让重复音效不呆板。
@export_range(0.0, 0.5, 0.01) var pitch_variation: float = 0.06

# ============================================================================
# 私有变量
# ============================================================================

## 空闲的音效播放器。
var _sfx_pool: Array[AudioStreamPlayer] = []
## 当前正在播放的音乐播放器（常驻，切歌时只换 stream）。
var _music_player: AudioStreamPlayer
## 当前音乐流，避免重复播放同一首。
var _current_music: AudioStream
## 当前音乐的语义归属（"menu" / "level:<id>" / ""）。
## 与 _current_music 配合，用来判断"这次请求算不算换歌"。
var _music_owner: StringName = &""

# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# 预创建播放器池，避免运行时分配造成卡顿。
	for i: int in sfx_pool_size:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = &"Master"
		player.volume_db = sfx_volume_db
		player.finished.connect(_on_sfx_finished.bind(player))
		add_child(player)
		_sfx_pool.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Master"
	_music_player.volume_db = music_volume_db
	add_child(_music_player)


# ============================================================================
# 公开方法
# ============================================================================

## 播放一次性音效。stream 为 null 时静默返回（允许数据里留空）。
##
## pitch：音高基准（1.0 = 原速）。仍会叠加本类自己的随机微调，
##   所以"逐字语音"既能有台词自身的音高（老人低、孩童高），
##   又不会变成整齐划一的机关枪。默认 1.0，既有调用方无需改动。
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _get_free_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = sfx_volume_db + volume_db
	# 随机音调：同一个音效连打时听起来不至于像机关枪。
	player.pitch_scale = pitch * (1.0 + randf_range(-pitch_variation, pitch_variation))
	player.play()


## 播放背景音乐。传入相同音乐时不重启，避免场景切换时音乐断掉。
##
## 【为什么委托给 play_music_for】旧实现只换 stream 不登记 owner，于是这里播出的
##   音乐 `_music_owner` 始终是空串。而"BGM 与场景是否匹配"的判定依据正是 owner：
##   主菜单用本方法放菜单曲，owner 留空 → 之后关卡切换按 owner 比对时被判成
##   "不是同一首/没有归属"，无论重启还是沿用都可能错位。统一委托后，凡是经由
##   AudioManager 播出的音乐都带明确归属。
func play_music(stream: AudioStream, restart: bool = false) -> void:
	play_music_for(&"music", stream, restart)


## 按"归属"切歌：owner 相同且正在播就不重启；owner 变了则强制换。
##
## 【为什么需要 owner 而不是只比 stream】两个不同场景可能恰好配了同一首曲子。
##   只比 stream 会认为"没变"而不重启，玩家却期望进新场景时音乐从头来
##   （尤其是清完房间重新进 BOSS 房）。owner 表达的是"这段音乐的语义归属"。
func play_music_for(owner: StringName, stream: AudioStream, restart: bool = false) -> void:
	if stream == null or _music_player == null:
		return
	if owner == _music_owner and stream == _current_music and _music_player.playing and not restart:
		return
	_music_owner = owner
	_current_music = stream
	_music_player.stream = stream
	_music_player.play()


func stop_music() -> void:
	if _music_player == null:
		return
	_music_player.stop()
	_music_player.stream = null
	_current_music = null
	_music_owner = &""


## 当前是否有音乐在播（主菜单据此判断要不要补一首）。
func is_playing_music() -> bool:
	return _music_player != null and _music_player.playing


## 当前音乐的归属（调试 / 测试用）。
func get_music_owner() -> StringName:
	return _music_owner


func set_sfx_volume(db: float) -> void:
	sfx_volume_db = db
	for player: AudioStreamPlayer in _sfx_pool:
		player.volume_db = db


func set_music_volume(db: float) -> void:
	music_volume_db = db
	_music_player.volume_db = db


# ============================================================================
# 私有方法
# ============================================================================

## 从池里找一个没在播放的播放器。全忙时返回 null。
func _get_free_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _sfx_pool:
		if not player.playing:
			return player
	return null


# ============================================================================
# 信号回调
# ============================================================================

func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	# 播完把音调复位，避免下次复用时残留。
	player.pitch_scale = 1.0
