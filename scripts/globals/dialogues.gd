extends Node
## 自动加载：Dialogues —— NPC 对话目录（data/dialogues.json）。
##
## 结构（节点字典按 id 索引，start 指定入口节点）：
##   {"dialogues": {
##     "chef": {
##       "start": "hi",
##       "nodes": {
##         "hi": {
##           "lines": [{"ja": "いらっしゃい！", "zh": "欢迎光临！"}, ...],
##           "choices": [
##             {"text": "仕事ある？", "zh": "有委托吗？", "next": "hi", "action": "quests"},
##             ...
##           ]
##         }
##       }
##     }
##   }}
##
## lines 放完显示 choices；没有 choices 或 next=="END" 时对话结束。
## choice.action：""（无）/ "quests"（关闭对话并打开该 NPC 的任务面板）/ "close"。
## 对话缺失（文件不存在/该 NPC 没配）时由调用方回退旧行为（直接开任务面板）。

const DATA_PATH := "res://data/dialogues.json"

var _catalog := {}


func _ready() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return   # 没配对话是正常状态：NPC 直接进任务面板，不能报错刷屏
	var v: Variant = JSON.parse_string(f.get_as_text())
	if v is Dictionary:
		_catalog = v.get("dialogues", {})


func has(npc_id: String) -> bool:
	return _catalog.has(npc_id)


func get_dialogue(npc_id: String) -> Dictionary:
	return _catalog.get(npc_id, {})
