extends Node
## 自动加载：Tts —— 发音管理。
## 策略：
##  1. 优先播放随游戏打包的真人级音频（assets/audio/<id>.mp3，神经语音合成）；
##  2. 无音频时回退系统 TTS 朗读假名（桌面端；安卓上部分国产 ROM 的 TTS 引擎
##     会让 Godot 崩溃，故安卓默认不调用系统 TTS，只用打包音频）。

var voice_id := ""
var available := false

var _player: AudioStreamPlayer
var _streams := {}


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	# 安卓上跳过系统 TTS 枚举（某些 ROM 会触发引擎层崩溃），发音一律用打包音频
	if OS.has_feature("android") or OS.has_feature("web_android") or OS.has_feature("ios"):
		available = false
		return
	_find_voice.call_deferred()


func _find_voice() -> void:
	for v: Dictionary in DisplayServer.tts_get_voices():
		var lang := String(v.get("language", "")).to_lower()
		var name := String(v.get("name", "")).to_lower()
		if lang.begins_with("ja") or lang.begins_with("jpn") or name.contains("japanese"):
			voice_id = String(v.get("id", ""))
			break
	available = voice_id != ""
	if available:
		print("[TTS] 日语语音: ", voice_id)
	else:
		print("[TTS] 未找到日语语音包，将使用打包音频")


func _vol_db() -> float:
	return -30.0 + float(Game.settings.get("volume", 0.8)) * 30.0


## 朗读一个词条：优先打包音频，回退系统 TTS
func speak_word(w: Dictionary) -> bool:
	var audio_path := String(w.get("audio", ""))
	if not audio_path.is_empty():
		return _play_audio(audio_path)
	var text := String(w.get("kana", ""))
	if text.is_empty():
		text = String(w.get("ja", ""))
	return speak(text)


func speak(text: String) -> bool:
	if not available or text.is_empty():
		return false
	_player.stop()
	DisplayServer.tts_stop()
	var pitch := float(Game.settings.get("pitch", 1.0))
	DisplayServer.tts_speak(text, voice_id, int(_vol_db()), pitch, true)
	return true


func _play_audio(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	if not _streams.has(path):
		_streams[path] = load(path)
	var stream: AudioStream = _streams[path]
	if stream == null:
		return false
	_player.stop()
	if available:
		DisplayServer.tts_stop()
	_player.stream = stream
	_player.volume_db = _vol_db() * 0.7
	_player.pitch_scale = float(Game.settings.get("pitch", 1.0))
	_player.play()
	return true


func stop() -> void:
	if _player != null:
		_player.stop()
	if available:
		DisplayServer.tts_stop()
