class_name Sfx
extends Node
## 音效：art/sfx/*.wav（tools/make_sfx.py 合成；同名 wav 直接覆盖就能换成真录音，再导入一次）。
## bell = 警钟"当—当—当" · clear = 警报解除"叮—咚" · alert = 挨打报警的两声号角。M 键静音。
## 几个播放器轮流用：警钟没敲完又来报警，两个声音叠着放，不互相掐断

const VOLUME := {"bell": -3.0, "clear": -6.0, "alert": -4.0}
static var muted := false
static var _streams := {}
var last := ""             # 最近要播的（静音时也记，测试用）
var played := {}           # 每种播了几次（测试用）
var _players: Array = []
var _headless := DisplayServer.get_name() == "headless"

func _ready() -> void:
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

## 静态缓存要在退出前清掉，不然引擎退出时报"资源还在用"
func _exit_tree() -> void:
	_streams.clear()

static func stream(key: String) -> AudioStream:
	if not _streams.has(key):
		var path := "res://art/sfx/%s.wav" % key
		_streams[key] = load(path) if ResourceLoader.exists(path) else null
	return _streams[key]

func play(key: String) -> void:
	last = key
	played[key] = int(played.get(key, 0)) + 1
	if muted or _headless:
		return    # 无头跑（测试 / 机器人）：假声卡不回收播完的声音，退出时会报泄漏，干脆不放
	var s := stream(key)
	if s == null:
		return
	var p: AudioStreamPlayer = _players[0]
	for q in _players:
		if not q.playing:
			p = q
			break
	p.stream = s
	p.volume_db = float(VOLUME.get(key, -4.0))
	p.play()
