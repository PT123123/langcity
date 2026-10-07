class_name Interactable
extends Area3D
## 街道上的可交互物体（3D）：全部由基础几何体 + 程序纹理拼装（无需美术资源）。
## 根节点是 Area3D：射线点击直接命中；实心物体额外挂 StaticBody3D 挡住玩家。

const S := 0.025  # 地图像素 -> 米（4000px 世界 = 100m）

# kind 元数据：
# click=点击体积(Area3D 盒) solid=碰撞体积(null=不挡路) range=交互距离(米,0=不限)
# stand=台面层厚度(米)。>0 时碰撞体只在物件顶部生成该厚度的薄层，脚下是通的 ——
#       猫可以跳上这玩意（Stray 的核心玩法：跳上箱子/长椅/矮墙）。
#       0 或不填 = 实心障碍（建筑、车辆等不可穿越的）。
#
# 【尺度基准】猫肩高 0.23m、碰撞体高 0.36m、跳高 0.66m（1.8 倍体高）。
# 所以能跳的物件台面必须在 0.66m 以下。建模时按这个标准定尺寸：
#   能跳：长椅座面 0.42 / 水泥管 0.38 / 花坛 0.5 / 塑料箱 0.4 / 矮墙 0.55
#   不能跳：窗台 0.9 / 车顶 1.5 / 公交站牌 2.9 —— 猫就是猫，别做超级英雄
# novis=不生成外形(隐藏标记) door_win=依附建筑正面（map 里用 host 指定建筑类型）
const META := {
	# ---- 可跳上去的：台面 ≤ 0.66m ----
	# 长椅：座面降到 0.42m（真人长椅座高约 0.42m，正好在猫的跳跃极限内）
	"bench":        {"click": Vector3(2.5, 1.1, 0.95), "solid": Vector3(2.3, 0.42, 0.8), "stand": 0.12, "range": 6.0},
	"mailbox":      {"click": Vector3(0.75, 0.62, 0.7), "solid": Vector3(0.62, 0.55, 0.55), "stand": 0.12, "range": 6.0},
	"trash":        {"click": Vector3(0.85, 0.58, 0.85), "solid": Vector3(0.72, 0.52, 0.72), "stand": 0.12, "range": 6.0},
	"bicycle":      {"click": Vector3(1.9, 1.05, 0.75), "solid": Vector3(1.75, 0.5, 0.55), "stand": 0.1, "range": 6.0},
	# ---- 不可穿越的实心体 ----
	"vending":      {"click": Vector3(1.0, 1.95, 0.9), "solid": Vector3(0.95, 1.85, 0.8), "range": 7.0},
	"pole":         {"click": Vector3(0.6, 7.2, 0.6), "solid": Vector3(0.3, 7.0, 0.3), "range": 6.0},
	"car":          {"click": Vector3(4.5, 1.7, 2.0), "solid": Vector3(4.3, 1.5, 1.85), "range": 8.0},
	"traffic":      {"click": Vector3(0.7, 5.6, 3.2), "solid": Vector3(0.35, 4.5, 0.35), "range": 7.0},
	"station":      {"click": Vector3(12.6, 5.4, 8.2), "solid": Vector3(12.5, 4.8, 4.5), "range": 14.0},
	"train":        {"click": Vector3(19.6, 3.4, 2.9), "solid": Vector3(19.0, 2.6, 2.6), "range": 14.0},
	"konbini":      {"click": Vector3(6.6, 3.6, 5.1), "solid": Vector3(6.5, 3.4, 5.0), "range": 11.0},
	"house":        {"click": Vector3(4.3, 4.3, 3.7), "solid": Vector3(4.2, 3.0, 3.6), "range": 9.0,
		# 【围墙碰撞】_b_house 里画了一圈院子围墙（后墙/左右墙/前两段/门柱），
		# 之前只有建筑本体这一个碰撞盒 —— 围墙是纯视觉，玩家直接穿墙进院。
		# 这里按 _b_house 的视觉尺寸逐段补碰撞（s=尺寸 p=局部坐标）。
		"extra_solids": [
			{"s": Vector3(7.4, 1.12, 0.2), "p": Vector3(0, 0.56, -3.0)},
			{"s": Vector3(0.2, 1.12, 4.2), "p": Vector3(-3.6, 0.56, -0.9)},
			{"s": Vector3(0.2, 1.12, 4.2), "p": Vector3(3.6, 0.56, -0.9)},
			{"s": Vector3(2.3, 1.0, 0.18), "p": Vector3(-2.5, 0.5, 1.35)},
			{"s": Vector3(2.3, 1.0, 0.18), "p": Vector3(2.5, 0.5, 1.35)},
			{"s": Vector3(0.26, 1.5, 0.26), "p": Vector3(-1.3, 0.75, 1.35)},
			{"s": Vector3(0.26, 1.5, 0.26), "p": Vector3(1.3, 0.75, 1.35)},
		]},
	"mansion":      {"click": Vector3(4.3, 9.7, 3.9), "solid": Vector3(4.2, 9.5, 3.8), "range": 10.0},
	"super":        {"click": Vector3(7.7, 4.6, 5.5), "solid": Vector3(7.6, 4.4, 5.4), "range": 12.0},
	"cafe":         {"click": Vector3(5.3, 3.8, 4.3), "solid": Vector3(5.2, 3.6, 4.2), "range": 10.0},
	"ramen":        {"click": Vector3(6.3, 4.2, 4.7), "solid": Vector3(6.2, 4.0, 4.6), "range": 11.0},
	"post_office":  {"click": Vector3(5.9, 4.6, 4.3), "solid": Vector3(5.8, 4.4, 4.2), "range": 10.0},
	"signboard":    {"click": Vector3(1.1, 2.8, 0.5), "solid": Vector3(0.9, 2.6, 0.35), "range": 6.0},
	"streetlight":  {"click": Vector3(1.9, 4.5, 0.45), "solid": Vector3(0.25, 4.2, 0.25), "range": 6.0},
	"tree":         {"click": Vector3(2.7, 4.7, 2.7), "solid": Vector3(0.55, 2.6, 0.55), "range": 7.0},
	"sakura":       {"click": Vector3(3.1, 5.3, 3.1), "solid": Vector3(0.55, 2.6, 0.55), "range": 7.0},
	"busstop":      {"click": Vector3(1.4, 3.1, 0.5), "solid": Vector3(1.15, 2.9, 0.3), "range": 6.0},
	"parksign":     {"click": Vector3(1.5, 2.4, 0.45), "solid": Vector3(1.25, 2.2, 0.25), "range": 6.0},
	# ---- 不可碰撞的装饰 ----
	"flower":       {"click": Vector3(1.2, 0.8, 1.2), "solid": null, "range": 5.0},
	"grass":        {"click": Vector3(1.5, 0.6, 1.5), "solid": null, "range": 5.0},
	"dog":          {"click": Vector3(1.2, 1.0, 0.9), "solid": null, "range": 5.0},
	"cat":          {"click": Vector3(0.9, 0.9, 0.85), "solid": null, "range": 5.0},
	"bird":         {"click": Vector3(0.6, 0.6, 0.6), "solid": null, "range": 4.0},
	# 美术包 NPC（任务发布者）：人形站立，点击盒按人形大小，不挡路
	"npc":          {"click": Vector3(0.9, 1.9, 0.9), "solid": null, "range": 6.0},
	# 美术包投递物（包裹/明信片/供品…）：小道具，不挡路，model 由 map.json extra 指定
	"delivery":     {"click": Vector3(0.6, 0.5, 0.6), "solid": null, "range": 5.0},
	"bowl":         {"click": Vector3(1.1, 0.85, 1.1), "solid": null, "range": 5.0},
	"cans":         {"click": Vector3(0.95, 0.6, 0.75), "solid": null, "range": 5.0},
	"onigiri":      {"click": Vector3(1.0, 0.7, 1.0), "solid": null, "range": 5.0},
	"bread":        {"click": Vector3(1.7, 1.0, 1.15), "solid": null, "range": 5.0},
	"door":         {"click": Vector3(1.4, 2.5, 0.7), "solid": null, "range": 6.0, "door_win": true},
	"window":       {"click": Vector3(1.4, 1.6, 0.7), "solid": null, "range": 6.0, "door_win": true},
	"marker_road":  {"click": Vector3(24.0, 0.5, 6.6), "solid": null, "range": 0.0, "novis": true},
	"marker_walk":  {"click": Vector3(18.0, 0.5, 4.6), "solid": null, "range": 0.0, "novis": true},
	"marker_cross": {"click": Vector3(16.2, 0.5, 16.2), "solid": null, "range": 0.0, "novis": true},
	"crosswalk":    {"click": Vector3(6.7, 0.4, 3.6), "solid": null, "range": 0.0},
	# ---- 批次 5 新增：专为「猫能跳上去」设计的矮物件 ----
	# 水泥管（街边排水管盖）：0.38m，猫跳上去是 Stray 里最经典的画面
	"pipe":         {"click": Vector3(0.7, 0.42, 0.7), "solid": Vector3(0.62, 0.38, 0.62), "stand": 0.1, "range": 5.0},
	# 塑料周转箱（店铺门口的箱子）：0.4m
	"crate":        {"click": Vector3(0.8, 0.46, 0.65), "solid": Vector3(0.72, 0.4, 0.58), "stand": 0.1, "range": 5.0},
	# 花坛矮沿（公园/店铺前）：0.5m
	"planter":      {"click": Vector3(1.6, 0.56, 1.0), "solid": Vector3(1.5, 0.5, 0.9), "stand": 0.14, "range": 5.0},
	# 矮墙（巷口/院落）：0.55m
	"lowwall":      {"click": Vector3(2.4, 0.62, 0.4), "solid": Vector3(2.3, 0.55, 0.32), "stand": 0.14, "range": 5.0},
	# ---- 批次 6 新增：家具（家具屋门前的展示品，矮件猫可跳） ----
	"furniture":    {"click": Vector3(7.7, 4.6, 5.5), "solid": Vector3(7.6, 4.4, 5.4), "range": 12.0},
	"table":        {"click": Vector3(1.6, 0.9, 1.1), "solid": Vector3(1.3, 0.45, 0.85), "stand": 0.12, "range": 5.0},
	"chair":        {"click": Vector3(0.7, 1.05, 0.7), "solid": Vector3(0.5, 0.44, 0.5), "stand": 0.12, "range": 5.0},
	"bed":          {"click": Vector3(2.5, 0.8, 1.6), "solid": Vector3(2.2, 0.35, 1.4), "stand": 0.12, "range": 5.0},
	"sofa":         {"click": Vector3(2.3, 1.0, 1.2), "solid": Vector3(2.0, 0.45, 0.95), "stand": 0.12, "range": 5.0},
	"tv":           {"click": Vector3(1.7, 1.8, 0.8), "solid": Vector3(1.45, 1.2, 0.6), "range": 5.0},
	"shelf":        {"click": Vector3(1.5, 2.0, 0.8), "solid": Vector3(1.3, 1.5, 0.6), "range": 5.0},
	"lamp":         {"click": Vector3(0.7, 1.7, 0.7), "solid": Vector3(0.45, 1.5, 0.45), "range": 5.0},
	"wash":         {"click": Vector3(0.9, 1.1, 0.9), "solid": Vector3(0.78, 0.92, 0.68), "range": 5.0},
	# ---- 批次 7：街景杂物（装饰为主，不参与学词；矮件猫可跳） ----
	# 路牌：map.json 里本来就有 roadsign（还是可学单词「標識」），但 META 漏了
	# 这个 kind —— 两个路牌一直是隐形的。补上建模。
	"roadsign":     {"click": Vector3(0.9, 2.7, 0.5), "solid": Vector3(0.12, 2.5, 0.12), "range": 6.0},
	# 消火栓（柱形）：0.62m，猫能跳上去
	"fireplug":     {"click": Vector3(0.5, 0.72, 0.5), "solid": Vector3(0.36, 0.62, 0.36), "stand": 0.1, "range": 5.0},
	# 鉢植え（盆栽）：店铺/家门口标配，0.4m 台面
	"potplant":     {"click": Vector3(0.85, 0.85, 0.85), "solid": Vector3(0.5, 0.4, 0.5), "stand": 0.08, "range": 5.0},
	# 物干し竿（晾衣杆）：两根 T 杆 + 下垂电线 + 挂着的毛巾，不挡路
	"laundry":      {"click": Vector3(2.6, 2.3, 1.0), "solid": null, "range": 6.0},
	# ゴミ袋（垃圾袋）：清晨收垃圾时段摆在路边，0.4m 可跳
	"trashbags":    {"click": Vector3(1.1, 0.55, 0.9), "solid": Vector3(0.95, 0.4, 0.75), "stand": 0.08, "range": 5.0},
	# タイヤ（旧轮胎堆）：店后巷，0.51m 可跳
	"tires":        {"click": Vector3(0.9, 0.62, 0.9), "solid": Vector3(0.76, 0.51, 0.76), "stand": 0.1, "range": 5.0},
	# 工事コーン（路锥）：路面施工/驻车禁止，不挡路
	"cones":        {"click": Vector3(1.2, 0.6, 0.8), "solid": null, "range": 5.0},
	# ガスボンベ（燃气罐）：拉面店/饮食店后面靠墙一排，实心
	"gasbottle":    {"click": Vector3(1.0, 1.1, 0.8), "solid": Vector3(0.85, 0.95, 0.6), "range": 5.0},
	# 水洼：路面半透明反光片（纯装饰，无碰撞）
	"puddle":       {"click": Vector3(1.6, 0.2, 1.6), "solid": null, "range": 0.0},
	# ---- 多地图传送点（车站/路口的指路牌）：不挡路，走近出现【前往 ▸ 目的地】按钮。
	# map 里的字段：to_map（目标 place id）、to_x/to_y（目标 px 坐标）、to_yaw、label（目的地名）
	"portal":       {"click": Vector3(2.6, 3.0, 0.8), "solid": null, "range": 6.0},
	# ---- 批次 8 新增：可进入室内的家具（house_basic / konbini_shop / station_hall 等模板用） ----
	# 矮件台面沿袭批次 5 铁律 ≤ 0.66m（猫跳得上）；墙挂/吊挂件 solid=null。
	# click_y：物件视觉中心不在默认 click.y*0.5 处时，显式指定点击盒中心高度（见 _ready）。
	# 冷蔵庫：白灰双门冰箱，实心不可跳
	"fridge":         {"click": Vector3(1.0, 1.9, 0.8), "solid": Vector3(0.95, 1.85, 0.75), "range": 5.0},
	# コンロ：厨房灶台（柜体 + 2 个燃气灶眼 + 锅），实心
	"stove":          {"click": Vector3(1.2, 0.92, 0.75), "solid": Vector3(1.15, 0.88, 0.72), "range": 5.0},
	# 浴槽：白瓷浴缸，缸沿 0.12m 圆边，猫可跳上
	"bathtub":        {"click": Vector3(1.7, 0.72, 0.85), "solid": Vector3(1.6, 0.66, 0.8), "stand": 0.12, "range": 5.0},
	# トイレ：便器 + 水箱，座面 0.1m 薄台可跳
	"toilet":         {"click": Vector3(0.72, 0.82, 0.78), "solid": Vector3(0.62, 0.78, 0.72), "stand": 0.1, "range": 5.0},
	# 戸棚：高身木柜（双门），实心不可跳
	"cupboard":       {"click": Vector3(1.15, 1.95, 0.68), "solid": Vector3(1.1, 1.9, 0.64), "range": 5.0},
	# 靴箱：玄关矮柜（百叶门 + 顶上一双鞋），台面 0.12m 可跳
	"shoe_cabinet":   {"click": Vector3(1.1, 0.95, 0.42), "solid": Vector3(1.05, 0.9, 0.38), "stand": 0.12, "range": 5.0},
	# エアコン：壁挂式室内机，装在高处（视觉中心 y≈2.0m），无碰撞；click_y 抬升点击盒
	"aircon":         {"click": Vector3(0.92, 0.34, 0.30), "solid": null, "click_y": 2.0, "range": 5.0},
	# カーペット：平铺地毯（纯装饰，无碰撞），贴地 y≈0.02
	"carpet":         {"click": Vector3(2.4, 0.04, 1.8), "solid": null, "range": 5.0},
	# 絵画：挂墙画框，视觉中心 y≈1.6m，无碰撞；click_y 抬升点击盒
	"painting":       {"click": Vector3(1.2, 0.8, 0.08), "solid": null, "click_y": 1.6, "range": 5.0},
	# カーテン：吊轨分幅布帘（暖簾式），无碰撞
	"curtain":        {"click": Vector3(2.0, 2.2, 0.14), "solid": null, "range": 5.0},
	# レジ：收银 POS（底座 + 屏 + 键位 + 小票机），实心
	"register":       {"click": Vector3(0.82, 1.15, 0.72), "solid": Vector3(0.78, 1.1, 0.68), "range": 5.0},
	# 陳列棚：超市/便利店的开口货架，实心不可跳
	"display_shelf":  {"click": Vector3(2.0, 1.65, 0.66), "solid": Vector3(1.95, 1.6, 0.62), "range": 5.0},
	# カウンター：吧台/收银台（出挑木台面），台面 0.12m 可跳
	"counter":        {"click": Vector3(2.4, 1.05, 0.72), "solid": Vector3(2.3, 1.0, 0.68), "stand": 0.12, "range": 5.0},
	# スツール：圆凳（金属脚 + 脚踏圈），座面 0.1m 可跳
	"stool":          {"click": Vector3(0.46, 0.62, 0.46), "solid": Vector3(0.4, 0.58, 0.4), "stand": 0.1, "range": 5.0},
	# 券売機：车站/拉面店的自动售票机，实心
	"ticket_machine": {"click": Vector3(0.95, 1.85, 0.95), "solid": Vector3(0.9, 1.8, 0.9), "range": 5.0},
	# 改札機：自动检票闸机（两端机箱 + 斜面顶 + 指示灯 + 挡板），实心
	"gate":           {"click": Vector3(1.85, 1.12, 0.62), "solid": Vector3(1.8, 1.08, 0.58), "range": 5.0},
	# 駅名標：吊挂站名板，视觉中心 y≈2.4m，无碰撞；click_y 抬升点击盒
	"station_sign":   {"click": Vector3(2.4, 0.62, 0.12), "solid": null, "click_y": 2.4, "range": 5.0},
	# ---- 批次 9：公共设施（学校/寺/病院…）+ 交通 + 单词牌，给 0% 分类补载体 ----
	# 全部实心、不可跳（楼就是楼），range 8~12m 与既有建筑一致
	"temple":     {"click": Vector3(5.2, 4.8, 4.6), "solid": Vector3(5.1, 4.4, 4.5), "range": 11.0},
	"school":     {"click": Vector3(9.0, 5.2, 4.8), "solid": Vector3(8.9, 4.8, 4.7), "range": 13.0},
	"hospital":   {"click": Vector3(7.0, 5.4, 5.0), "solid": Vector3(6.9, 5.0, 4.9), "range": 12.0},
	"bank":       {"click": Vector3(5.6, 4.6, 4.4), "solid": Vector3(5.5, 4.2, 4.3), "range": 10.0},
	"police":     {"click": Vector3(5.6, 4.6, 4.4), "solid": Vector3(5.5, 4.2, 4.3), "range": 10.0},
	"library":    {"click": Vector3(6.0, 5.0, 4.6), "solid": Vector3(5.9, 4.6, 4.5), "range": 11.0},
	# トラック：Kenney truck，实心不可跳（比小车高一截）
	"truck":      {"click": Vector3(6.0, 2.4, 2.4), "solid": Vector3(5.8, 2.2, 2.3), "range": 8.0},
	# 船：码头边的小舢板，不挡路（猫跳上船板 stand 0.1）
	"boat":       {"click": Vector3(2.6, 1.5, 1.3), "solid": null, "range": 6.0},
	# 切符（券売機旁的木牌）：薄牌无碰撞
	"ticket_sign": {"click": Vector3(0.9, 1.3, 0.4), "solid": Vector3(0.35, 1.2, 0.3), "range": 6.0},
	# 商店货架（屋台/店前Goods）：不挡路，台面 0.5m 可跳
	"goods":      {"click": Vector3(1.8, 1.1, 0.8), "solid": Vector3(1.7, 0.5, 0.7), "stand": 0.1, "range": 5.0},
	# 单词牌（立式看板，抽象词载体）：无碰撞，纯装饰
	"plate":      {"click": Vector3(1.1, 1.6, 0.3), "solid": null, "range": 6.0},
	# ---- 批次 9 动物：全部 solid: null（猫能走过去），归一化高度见各自 _b_xxx ----
	"deer":       {"click": Vector3(1.0, 0.8, 1.4), "solid": null, "range": 5.0},
	"fox":        {"click": Vector3(1.2, 0.6, 0.7), "solid": null, "range": 5.0},
	"wolf":       {"click": Vector3(1.0, 0.75, 1.4), "solid": null, "range": 5.0},
	"turtle":     {"click": Vector3(0.8, 0.4, 0.8), "solid": null, "range": 5.0},
}

var word_id := ""
var kind := ""
var no_draw := false
var interact_range := 7.0
var extra := {}

var highlighted := false
var quest_target := false   # 当前被追踪的收集类任务把它当作指路目标 → 显示光圈
var _pulse := 0.0
var _ring: MeshInstance3D
var _car_color := Color("e8e6e0")
var _door_dy := 0.0

static var _mats := {}

static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


## 存在哪些贴图套件（自动扫盘，新增贴图无需改代码）
static var _tex_kinds := {}
static var _tex_scanned := false

static func _scan_tex() -> void:
	if _tex_scanned:
		return
	_tex_scanned = true
	var d := DirAccess.open("res://assets/tex")
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with("_col.jpg"):
			continue
		var kind := f.substr(0, f.length() - 8)
		# 记下有哪些通道可用
		var chans := {"col": true}
		if FileAccess.file_exists("res://assets/tex/%s_nrm.jpg" % kind):
			chans["nrm"] = true
		if FileAccess.file_exists("res://assets/tex/%s_rgh.jpg" % kind):
			chans["rgh"] = true
		_tex_kinds[kind] = chans


static func has_tex(kind: String) -> bool:
	_scan_tex()
	return _tex_kinds.has(kind)


## 把 tint「软化」成接近白色的乘数。
## 【为什么需要】albedo_color 是直接乘贴图的，任何明显偏离 1.0 的 tint 都会
## 把贴图的明暗层次压平 —— 墙面会变成一块纯色。
## 做法：取 tint 的**平均亮度**作为「保持多少原色」，色相只保留一点点偏移。
##   strength=0 → 完全用 tint（老行为，会压平贴图）
##   strength=1 → 纯白（完全保留贴图原色）
##
## 【色相钳制范围：0.85~1.12 → 0.78~1.18（这轮放宽）】
## 原来 ±12% 的钳制太紧，实践中「给 12 栋民居配不同墙色」完全看不出来 ——
## 实测 tint 传 (0.90,0.84,0.68)（藤茶色）过一遍 _soft_tint 后
## 落到 (0.96,0.93,0.90)，色相基本被抹平，12 栋房子渲染出来全是同一个灰。
## 放宽到 ±22% 后同一输入落到 (0.94,0.88,0.79)，米黄/灰蓝/苔绿能分辨出来。
## 为什么可以放宽而不压平贴图：**明度只由 target 决定，与色相偏移解耦** ——
## target 仍锁在 [0.82,1.0]（不压暗），色相偏移是乘性微调，
## 不改变贴图的明暗对比结构。这是「颜色透出来」和「层次保得住」能同时成立的原因。
static func _soft_tint(tint: Color, strength: float) -> Color:
	var lum := (tint.r + tint.g + tint.b) / 3.0
	# 目标亮度也归一化：不管调用方传 (0.93,0.9,0.86) 还是 (0.8,0.85,0.95)，
	# 都只保留其相对明暗关系，映射到 [0.82, 1.0] 这个「几乎不压暗」的区间。
	var norm := inverse_lerp(0.55, 1.0, clampf(lum, 0.0, 1.0))  # 0..1
	var target := lerpf(0.82, 1.0, norm)
	# 色相偏移：把 tint 相对其亮度的偏离量，按 strength 打折后加回去
	var keep := clampf(strength, 0.0, 1.0)
	var ratio := 1.0 / maxf(lum, 0.001)
	# 注意 ratio 归一化后，饱和的 tint 也会被这个钳制限制。0.78/1.18 是
	# 「能看出色相差异」与「不把墙染成糖果色」之间的平衡点。
	return Color(
		clampf(target * lerpf(1.0, clampf(tint.r * ratio, 0.78, 1.18), keep), 0.0, 1.0),
		clampf(target * lerpf(1.0, clampf(tint.g * ratio, 0.78, 1.18), keep), 0.0, 1.0),
		clampf(target * lerpf(1.0, clampf(tint.b * ratio, 0.78, 1.18), keep), 0.0, 1.0),
		1.0)


## 照片级 PBR 表面材质（Poly Haven CC0 扫描贴图）。
## scale = 每米重复次数（0.5 = 一张贴图铺 2 米）。
##
## 【tint 的正确用法 —— 这条之前搞错过，导致所有墙面糊成一片紫灰】
## `albedo_color` 是**直接乘** albedo_texture 的，不是"调色叠加"。
## 所以：
##   tint = 0.93,0.9,0.86 → 贴图被压到 93% 亮度并染上米色，
##     贴图本身的明暗层次（灰缝、污渍、颗粒）全部被压平 → 看起来像纯色块。
## 正确做法：**tint 尽量接近白色（0.9~1.0），只做极轻微的明度/色温偏移**，
## 把"上色"这件事交给不同贴图本身去完成（每种墙用不同的贴图，而不是同一张贴图 × 不同 tint）。
##
## scale = 每米重复次数（0.5 = 一张贴图铺 2 米）。
## detail_scale/detail_amount：叠一层高频细节，打破 1k 贴图在大面上的重复感。
## 【Messenger 视觉】返回类型放宽为 Material：大面走真 toon ShaderMaterial，
## 退回旧观感时仍是 StandardMaterial3D。调用方不要再声明成 StandardMaterial3D。
static func mat_photo(kind: String, tint: Color, tint_amt: float, rough: float, scale: float,
		fallback_tex: ImageTexture = null, fallback_scale := 0.5,
		detail_scale := 0.0, detail_amount := 0.35) -> Material:
	_scan_tex()
	# 缓存 key 里带上 tint_amt（之前漏了，导致不同 tint_amt 命中同一缓存）
	var key := "ph_%s_%s_%f_%f_%f_%f_%f" % [kind, tint.to_html(), tint_amt, rough, scale, detail_scale, detail_amount]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# 三平面世界映射：贴图不会因物体 UV 缺失而拉伸
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = rough
	m.metallic = 0.0
	m.metallic_specular = 0.22
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX

	if _tex_kinds.has(kind):
		m.albedo_texture = _tex("res://assets/tex/%s_col.jpg" % kind)
		# tint 只做「轻微偏移」：把 tint 归一化到接近白色，保住贴图本身的层次。
		# tint_amt = 0 → 完全用 tint（原行为）；tint_amt = 1 → 保留贴图原色。
		# 实用区间是 tint_amt 0.7~1.0。
		m.albedo_color = _soft_tint(tint, tint_amt)
		if _tex_kinds[kind].get("nrm", false):
			m.normal_enabled = true
			m.normal_texture = _tex("res://assets/tex/%s_nrm.jpg" % kind)
			m.normal_scale = 0.75
		if _tex_kinds[kind].get("rgh", false):
			m.roughness_texture = _tex("res://assets/tex/%s_rgh.jpg" % kind)
		# 细节层：同贴图高频叠加，抑制大面积平铺的"壁纸感"
		# 注意：detail 相关的枚举在 Godot 4 里搬到了 StandardMaterial3D 上，
		# 不在 BaseMaterial3D（写 BaseMaterial3D.DETAIL_BLEND_* 会编译失败）。
		# 不要给 detail_mask 赋 roughness 图 —— roughness 的明暗区会当遮罩，
		# 在地面上表现成一块块水渍/油污斑。纯细节叠加才干净。
		if detail_scale > 0.0 and m.albedo_texture != null:
			m.detail_enabled = true
			m.detail_albedo = m.albedo_texture
			m.detail_uv_layer = StandardMaterial3D.DETAIL_UV_1
			m.detail_blend_mode = StandardMaterial3D.BLEND_MODE_MIX
			m.detail_albedoblend_sharpness = 0.35
			m.detail_uv_scale = detail_scale
			m.detail_amount = detail_amount
	else:
		# 回退：程序纹理（三平面）
		m.albedo_texture = fallback_tex
		m.uv1_scale = Vector3.ONE * fallback_scale
		m.roughness = rough
	# 【Messenger 视觉】大面（墙面/地面/屋顶）走真 toon shader：
	# Messenger 的 atlas/terrain shader 是逐像素算硬边阴影 + HSV 保色相压暗的，
	# StandardMaterial3D 的 PBR 过渡给不出那种「色带状」的明暗分层。
	# 这里返回 ShaderMaterial，所以形参类型必须放宽到 Material。
	if ToonKit.enabled:
		var dtex: Texture2D = m.detail_albedo if m.detail_enabled else null
		# 细节贴图沿用 albedo 贴图（原逻辑就是 detail_albedo = albedo_texture），
		# 但 scale 要更大 —— 它的作用是打散平铺感，必须高频。
		# normal 沿用 m.normal_texture：上面已按贴图集扫出 nrm 通道，
		# 这里只是把它透传给 shader。**这是零几何成本拿到凹凸细节的唯一路径**，
		# 也是「能用贴图解决就别加面数」这条预算铁律的落地点。
		var ntex: Texture2D = m.normal_texture if m.normal_enabled else null
		# normal_scale 从 0.75 提到 1.6：toon 的硬边阴影通道会削平原线起伏
		# （见 toon.gdshader 的 normal_detail_visibility 注释），需要更强的
		# 扰动幅度才能在最终画面里看见凹凸。
		# rtex 是 roughness 贴图 —— toon 管线无高光，它不送进 ROUGHNESS 输出，
		# 而是当「脏污/老化遮罩」调制 albedo（详见 toon.gdshader 注释）。
		# 这是 87 张 rgh 贴图在项目里第一次真正被用起来。
		var rtex: Texture2D = m.roughness_texture
		var sm: ShaderMaterial = ToonKit.toon_tex(
			m.albedo_texture, m.albedo_color, scale,
			dtex, detail_scale if detail_scale > 0.0 else scale * 8.0, detail_amount * 2.0,
			ntex, 1.6,
			rtex, 0.32)
		_mats[key] = sm
		return sm
	_mats[key] = m
	return m


## 依实例位置的微小颜色变化，打破整齐划一的"积木感"
func _var(base: Color, amount := 0.05) -> Color:
	var h := int(abs(position.x * 13.37 + position.z * 7.77)) % 100
	var f := 1.0 + (h / 100.0 - 0.5) * 2.0 * amount
	return Color(minf(base.r * f, 1.0), minf(base.g * f, 1.0), minf(base.b * f, 1.0))


## 落水管
func _downspout(pos: Vector3, h: float) -> void:
	box(Vector3(0.11, h, 0.11), pos + Vector3(0, h * 0.5, 0), Color("c9c4b8"))
	box(Vector3(0.11, 0.11, 0.55), pos + Vector3(0, 0.3, 0.28), Color("c9c4b8"))


# ---------------- 材质工具（程序纹理 + 三平面世界映射） ----------------

## 全局调色收口：把任何字面量颜色朝「暖灰」压缩，统一低饱和环境色。
## 【为什么在工厂入口收口】场景里有 300+ 处裸 Color 字面量，逐个改既易漏、
## 又会让数据的可读性变差。在这里统一做一次归一化，所有材质都经过同一条
## 色彩规则，世界的整体色温和饱和度自然收敛（视觉方向 §3 / §6）。
## 规则：
##   1. 朝暖灰压缩 18%（暖灰按原明度取，R>G>B 的轻微暖偏）
##   2. 钳最大饱和度：max(r,g,b)-min(r,g,b) ≤ 0.42，防止某个高饱和色跳出来
## 明度层次与 alpha 完整保留。
static func _unify(c: Color) -> Color:
	var lum := c.get_luminance()
	var warm := Color(lum * 1.04, lum, lum * 0.94)
	var r := lerpf(c.r, warm.r, 0.18)
	var g := lerpf(c.g, warm.g, 0.18)
	var b := lerpf(c.b, warm.b, 0.18)
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	if mx - mn > 0.42:
		var mid := (mx + mn) * 0.5
		var k := 0.21 / maxf(mx - mid, 0.0001)
		r = mid + (r - mid) * k
		g = mid + (g - mid) * k
		b = mid + (b - mid) * k
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0), c.a)


## 纯色表面材质 —— **按颜色自动配一张表面贴图**，不再返回无贴图的纯色块。
##
## 【为什么在这里收口】场景里 300+ 处几何体（电线杆、门窗框、招牌、垃圾桶、
## 便利店细节、空调外机…）全走 box()/cyl()/sph()/torus() 这几个壳，里面统一调
## mat(color)。逐个调用点贴图不可能不漏，**在唯一入口补图才是全覆盖**。
## 验收：--shot-action=probe_tex 会逐材质统计，裸面必须归零（out/tex_probe.txt）。
##
## 【为什么按颜色选图】这些盒子的语义在调用点才知道，但颜色本身就是语义
## （绿的=植物、棕的=木、冷蓝的=金属器物、暖白的=墙/招牌）。用颜色反查贴图种类，
## 复用现有 50+ 套 Poly Haven 贴图（**重复用同一张没关系，比没有强**），
## 观感上比统一灰泥可信得多。
##
## 【贴图强度】albedo_texture 是**乘**上去的，所以 tint 走 _soft_tint(c, 0.82) ——
## 保留颜色身份、只让贴图提供明暗颗粒。直接用 c 乘贴图会把颜色压死成贴图色。
## 玻璃/自发光/水面不走这里（各有专用材质），所以不会给透明件糊上不透明纹理。
## 开发用总开关：命令行加 `--no-surface-tex` 就关掉「按颜色/语义自动配贴图」，
## 退回改动前的纯色观感。存在的理由只有一个 —— **A/B 对照**：
## 全场景上贴图必然增加采样开销，「有没有掉帧」「画面变好还是变脏」都不能靠感觉，
## 要用同一个场景、同一个机位跑两遍（--shot-action=probe_perf 出 FPS/draw call）。
static var surface_tex := not _has_flag("--no-surface-tex")


static func _has_flag(flag: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == flag:
			return true
	return false


static func mat(color: Color, size_hint := 0.0) -> StandardMaterial3D:
	var c := _unify(color)
	var bucket := _size_bucket(size_hint)
	var key := "c_%s_%d" % [c.to_html(), bucket]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	var kind := _class_tex(c)
	if surface_tex and has_tex(kind):
		m.albedo_texture = _tex("res://assets/tex/%s_col.jpg" % kind)
		m.albedo_color = _soft_tint(c, 0.82)
		# 三平面世界映射：这些网格的 UV 基本不可用（BoxMesh 的 UV 被挤在
		# 每个面上 0~1），不用世界投影会出现「每个面一张图」的塑料感。
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * BUCKET_SCALE[bucket]
		m.roughness = 1.0
	ToonKit.apply(m)
	_mats[key] = m
	return m


## 物件尺寸分档 → 每米贴图重复次数。分档而不是连续取值，是为了让材质实例数可控
## （颜色数 × 6 档），draw call 才是本项目的瓶颈（见 street.gd 装饰层注释）。
const BUCKET_SCALE := [6.0, 3.6, 2.2, 1.4, 0.9, 0.5]
const BUCKET_EDGES := [0.15, 0.35, 0.8, 1.6, 3.0]   # 档位分界（米）


static func _size_bucket(size_hint: float) -> int:
	if size_hint <= 0.0:
		return 3          # 未知尺寸按中档走（1.4 次/米 ≈ 一张图铺 0.7m）
	for i in BUCKET_EDGES.size():
		if size_hint < BUCKET_EDGES[i]:
			return i
	return BUCKET_SCALE.size() - 1


## 颜色 → 贴图 kind。规则按「先判彩色相，再判明度」：
## 色相决定材质家族（植物/木/砖/涂装），明度只在无彩色时兜底。
static func _class_tex(c: Color) -> String:
	var lum := c.get_luminance()
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var sat := 0.0 if mx <= 0.001 else (mx - mn) / mx
	if c.g >= c.r and c.g >= c.b:
		return "grass"                      # 绿/青：植物、招牌底色
	if sat > 0.22 and c.r > c.b * 1.3:
		return "plaster_brick_01" if c.b < 0.5 else "plaster_paint"   # 暖色涂装
	if c.b > c.r * 1.04:
		return "concrete_wall_001"          # 冷蓝：金属/玻璃器物、阴面构件
	if c.r > c.b * 1.10:
		return "wood"                       # 棕木色：木构件、纸箱
	if lum < 0.22:
		return "concrete"                   # 深灰：井盖、排水管、底盘
	if lum > 0.70:
		return "wall_white_rough"           # 亮白：墙、招牌底、瓷砖
	return "grey_plaster"                   # 中灰：金属灰、混凝土件


## 带程序纹理的材质：tint 给灰度纹理上色；scale 为每米重复数
static func tex_mat(tex: ImageTexture, tint: Color, scale: float, rough := 0.95, spec_key := "", height := 0.0) -> StandardMaterial3D:
	var t := _unify(tint)
	var key := "t_%s_%s_%f_%s_%f" % [spec_key, t.to_html(), scale, str(rough), height]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = t
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	# 【Messenger】rough 形参在这里被忽略：Messenger 的表面没有高光层次，
	# 全部靠明度分层。之前 roughness 从 0.9~0.98 变化是 PBR 的遗产 ——
	# 在平涂观感下它只会带来不必要的高光。仍保留形参与缓存 key 以免改调用点。
	ToonKit.apply(m)
	if height > 0.0:
		m.heightmap_enabled = true
		m.heightmap_texture = tex
		m.heightmap_scale = height
	_mats[key] = m
	return m


## 玻璃材质：橱窗 / 窗户 / 车窗。
## 【关键】必须开 TRANSPARENCY_ALPHA，否则橱窗是一块不透明的紫灰板，
## 里面什么都看不见 —— 这是「便利店橱窗像积木」的根本原因。
## roughness 0.05 + metallic 0.55 制造「反射天空」的高光，
## 再给一点自发光让夜里窗户会亮（由 TimeOfDay 调制强度）。
static func glass_mat(tint: Color, glow := 0.0) -> StandardMaterial3D:
	var key := "g_%s_%.2f" % [tint.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	# 【Messenger 视觉】Messenger 的窗户是「反射天空的亮片」：低 roughness
	# 造高光，但**不开 metallic**（金属会拉出 PBR 式的锐利反射边）。
	# 半透明必须保留 —— 否则橱窗是一块不透明的紫灰板。
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(tint.r, tint.g, tint.b, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.6)                  # 暖色，夜里像室内灯
	m.emission_energy_multiplier = glow                   # 0 = 白天不亮
	m.cull_mode = BaseMaterial3D.CULL_DISABLED            # 双面，从内外都看得到
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[key] = m
	return m


# ---------------- 实例化 ----------------

static func make(obj: Dictionary) -> Interactable:
	var it := Interactable.new()
	it.word_id = String(obj.get("word", ""))
	it.kind = String(obj.get("kind", ""))
	var meta: Dictionary = META.get(it.kind, {})
	it.interact_range = float(meta.get("range", 7.0))
	it.no_draw = bool(meta.get("novis", false))
	it.extra = obj
	var px := Vector2(float(obj.get("x", 0)), float(obj.get("y", 0)))
	# y_lift：室内上屋台高度（米）。台面上的家具要整体抬上去，否则陷进地板里半截。
	# 只改 position.y —— 视觉 mesh 和碰撞体都是本节点的子节点，自动一起抬。
	it.position = Vector3(px.x * S, float(obj.get("y_lift", 0.0)), px.y * S)
	# rot：绕 Y 旋转（度）。晾衣杆/路锥这类有方向性的道具用（门/窗的吸附偏移在旋转前算，不受影响）
	it.rotation.y = deg_to_rad(float(obj.get("rot", 0.0)))
	if meta.has("door_win"):
		it._door_dy = 1.15 if it.kind == "door" else 1.95
		# no_snap：室内门（出口门/隔间门）不吸附到建筑正南面 —— 坐标由室内模板给定
		if not bool(obj.get("no_snap", false)):
			var host_meta: Dictionary = META.get(String(obj.get("host", "house")), {})
			var hs: Vector3 = host_meta.get("click", Vector3(4, 3, 3))
			var dx := float(obj.get("dx", 0.0))
			it.position += Vector3(dx, 0, hs.z * 0.5 + 0.12)
	if it.kind == "car":
		var palette := [Color("e8e6e0"), Color("7fa8e0"), Color("c6cbd4"), Color("8fbf9f"), Color("e6d3b3"), Color("d97f7f")]
		it._car_color = palette[int(abs(px.x * 0.37 + px.y * 0.11)) % palette.size()]
	return it


func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true

	var meta: Dictionary = META.get(kind, {})
	var click_size: Vector3 = meta.get("click", Vector3(1, 1, 1))
	var click_pos := Vector3(0, click_size.y * 0.5, 0)
	# 高挂件（空调/壁画/站名板）：视觉中心远高于默认的半高位置，
	# 用 META 的 click_y 把点击盒抬到该高度（与门/窗的 _door_dy 分开处理，避免动到老逻辑）。
	if meta.has("click_y"):
		click_pos = Vector3(0, float(meta.get("click_y", 0.0)), 0)
	elif kind == "door" or kind == "window":
		click_pos = Vector3(0, _door_dy, 0)
	var cs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = click_size
	cs.shape = cbox
	cs.position = click_pos
	add_child(cs)

	var solid: Variant = meta.get("solid", null)
	var extra_solids: Array = meta.get("extra_solids", [])
	if solid is Vector3 or not extra_solids.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var sv: Vector3 = solid if solid is Vector3 else Vector3.ZERO
		# 【关键】区分「可站上去的平台」与「实心障碍」。
		# 之前所有碰撞体都是从地面到顶的整块实心盒 —— 猫撞上只能绕过去，
		# 跳都跳不上去（垃圾桶 0.85m 高、邮筒 1.0m 高，全都撞墙）。
		# 现在：矮物件只保留"台面层"（顶面能站），高物件保持实心（建筑/车）。
		var top_only: bool = float(meta.get("stand", 0.0)) > 0.0
		var stand_h: float = float(meta.get("stand", 0.0))
		if solid is Vector3 and top_only:
			# 只在物件顶部生成一块薄碰撞体：脚下是通的，猫能从旁边跳上去
			var ss := CollisionShape3D.new()
			var sbox := BoxShape3D.new()
			sbox.size = Vector3(sv.x, stand_h, sv.z)
			# 顶面对齐原 solid 的顶部
			ss.position = Vector3(0, sv.y - stand_h * 0.5, 0)
			ss.shape = sbox
			body.add_child(ss)
		elif solid is Vector3:
			var ss2 := CollisionShape3D.new()
			var sbox2 := BoxShape3D.new()
			sbox2.size = sv
			ss2.shape = sbox2
			ss2.position = Vector3(0, sv.y * 0.5, 0)
			body.add_child(ss2)
		# 附属实心段（如 house 的院子围墙）：按 META 里的视觉尺寸逐段补碰撞
		for ex: Dictionary in extra_solids:
			var ss3 := CollisionShape3D.new()
			var sbox3 := BoxShape3D.new()
			sbox3.size = ex.get("s", Vector3.ONE)
			ss3.shape = sbox3
			ss3.position = ex.get("p", Vector3.ZERO)
			body.add_child(ss3)
		add_child(body)

	if not no_draw:
		_build_visual()
		_plinth()
		# 贴地假阴影：太阳落山后（夜里 sun_energy 0.45）实时阴影几乎消失，
		# 没有这层小物件会"浮"在地上 —— 这是视觉升级文档里挂账的遗留问题。
		if BLOB_KINDS.has(kind):
			var br := clampf(maxf(click_size.x, click_size.z) * 0.5 + 0.12, 0.4, 2.4)
			_blob_shadow(br)
	# 光圈统一创建（含 novis 隐形标记）：默认隐藏，靠近高亮或被任务追踪时点亮
	_make_ring(click_size)


## 地基 / 挡土墙：补住「大楼悬在坡上、底下能钻过去」的空隙。
## plinth（米）由地图整备工具（MapValidator.plan_fix）按「脚下地面比基座低多少」算好
## 写进 planet.json。这里在基座**下方**补一段混凝土块（含碰撞），既不留缝、也不埋楼 ——
## 就是山坡建筑常见的混凝土基座外观。比「下沉埋掉楼」和「搬迁搬空镇子」都稳。
func _plinth() -> void:
	var h := float(extra.get("plinth", 0.0))
	if h <= 0.02:
		return
	var meta: Dictionary = META.get(kind, {})
	var hx := 0.5
	var hz := 0.5
	var solid: Variant = meta.get("solid", null)
	if solid is Vector3:
		hx = maxf(hx, (solid as Vector3).x * 0.5)
		hz = maxf(hz, (solid as Vector3).z * 0.5)
	elif meta.has("click"):
		hx = maxf(hx, (meta["click"] as Vector3).x * 0.5)
		hz = maxf(hz, (meta["click"] as Vector3).z * 0.5)
	for ex: Dictionary in meta.get("extra_solids", []):
		var s: Vector3 = ex.get("s", Vector3.ONE)
		var p: Vector3 = ex.get("p", Vector3.ZERO)
		hx = maxf(hx, absf(p.x) + s.x * 0.5)
		hz = maxf(hz, absf(p.z) + s.z * 0.5)
	var w := hx * 2.12
	var d := hz * 2.12
	box(Vector3(w, h, d), Vector3(0, -h * 0.5, 0), Color("9a958c"), 0.0, 0.0, 0.0,
		mat_photo("concrete", Color(0.72, 0.70, 0.66), 0.0, 0.95, 0.7, ProceduralTex.pavers(83), 0.6, 2.4, 0.4))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, d)
	cs.shape = bs
	cs.position = Vector3(0, -h * 0.5, 0)
	body.add_child(cs)
	add_child(body)


func _process(delta: float) -> void:
	if (highlighted or quest_target) and _ring != null:
		_pulse += delta
		var p := 1.0 + 0.05 * sin(_pulse * 5.0)
		_ring.scale = Vector3(p, 0.22, p)


func set_highlight(v: bool) -> void:
	if highlighted == v:
		return
	highlighted = v
	_pulse = 0.0
	if _ring != null:
		_ring.visible = v or quest_target


## 被收集类任务追踪为目标时点亮光圈（隐形标记如「交差点」也靠它显形）
func set_quest_target(v: bool) -> void:
	if quest_target == v:
		return
	quest_target = v
	if _ring != null:
		_ring.visible = v or highlighted


## 玩家是否在交互范围内；range<=0 表示不限。
## 【星球】用完整 3D 距离 —— XZ 水平距离会把「正下方/正上方」（球面另一侧）
## 的物件误判成就在脚边；平地上 y 恒为 0，行为与旧的 XZ 距离一致。
func in_range_of(player_pos: Vector3) -> bool:
	if interact_range <= 0.0:
		return true
	return position.distance_to(player_pos) <= interact_range


func _make_ring(click_size: Vector3) -> void:
	var r := minf(maxf(click_size.x, click_size.z) * 0.5 + 0.2, 2.2)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = r - 0.08
	torus.outer_radius = r + 0.01
	torus.rings = 40
	_ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("f2cc5a")
	m.emission_enabled = true
	m.emission = Color("f2cc5a")
	m.emission_energy_multiplier = 0.9
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = m
	_ring.scale = Vector3(1, 0.22, 1)
	_ring.position = Vector3(0, 0.1, 0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


## 需要贴地假阴影的 kind。建筑/门/窗除外（有实时阴影，且贴墙）；
## 花/草丛排除（草地上一团黑斑像枯死）。
const BLOB_KINDS := ["pole", "streetlight", "signboard", "busstop", "vending",
	"mailbox", "trash", "bicycle", "traffic", "fireplug", "potplant", "laundry",
	"trashbags", "tires", "cones", "gasbottle", "crate", "pipe", "bench",
	"planter", "lowwall", "parksign", "wash", "lamp", "tv", "shelf", "table",
	"chair", "sofa", "bed", "tree", "sakura", "car", "roadsign",
	"dog", "cat", "bird", "bowl", "cans", "onigiri", "bread",
	# 批次 8 室内家具：实心落地件加贴地假阴影（平铺/墙挂/吊挂件不加，见 batch 注释）
	"fridge", "stove", "bathtub", "toilet", "cupboard", "shoe_cabinet",
	"register", "display_shelf", "counter", "stool", "ticket_machine", "gate"]

static var _blob_mat: StandardMaterial3D


## 程序生成径向渐变圆片：中心 alpha 0.34 → 边缘 0。
## 压在地面以上 9cm（路面顶 0.07 / 井盖顶 0.087 之上，且低于高亮环 0.1）。
## UNSHADED + 不投影：纯暗化贴地，任何时刻都稳定。
func _blob_shadow(radius: float) -> void:
	if _blob_mat == null:
		var tex := GradientTexture2D.new()
		tex.width = 128
		tex.height = 128
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)   # 半径 = 半张图，渐变铺满
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([
			Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.18), Color(0, 0, 0, 0.0)])
		tex.gradient = g
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.albedo_texture = tex
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = quad
	mi.material_override = _blob_mat
	mi.rotation = Vector3(-PI * 0.5, 0, 0)
	mi.position = Vector3(0, 0.09, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ================================================================
# 批次 3：材质语义工厂
#
# 病根：全场景所有物体都用同一个默认 StandardMaterial3D，
#       结果满屏同一种塑料反光 —— 这是「demo 感」的第3 大来源。
# 修法：按「材质语义」分工厂，每个语义有明确的 roughness/metallic/emission 参数。
#       关键点是 roughness 与 metallic 要拉开档：
#         塑料 0.35 / 金属 0.4+metallic0.85 / 混凝土 0.85 / 玻璃 0.05 / 和纸 0.95
#       档位拉开后，即使光照相同也能靠「反光形状不同」区分物体。
# ================================================================

## 顶点色微差：按世界坐标伪随机，让同一材质的每块砖/每扇窗颜色都不同。
## 这是 low-poly 不廉价的关键 —— 消除「同一个紫出现 200 次」的塑料感。
static func _jitter_color(base: Color, pos: Vector3, amount := 0.055) -> Color:
	var h := int(abs(pos.x * 12.9898 + pos.z * 78.233 + pos.y * 37.719)) % 1000
	var f := 1.0 + (float(h) / 1000.0 - 0.5) * 2.0 * amount
	# 轻微的色相偏移，不只是明度 —— 纯明度变化在大片墙面上仍显假
	var warm := (float(h % 97) / 97.0 - 0.5) * amount * 0.6
	return Color(
		clampf(base.r * f + warm, 0, 1),
		clampf(base.g * f, 0, 1),
		clampf(base.b * f - warm * 0.5, 0, 1),
		base.a)


## 带微差的工厂包装：缓存 key 含位置哈希，所以每块砖是独立材质实例。
## 面数代价换「无塑料感」，比加面数划算。
##
## 【Messenger 视觉】rough / metal 两个参数被忽略：Messenger 的表面没有高光层次，
## 金属与非金属的区分完全靠明度分层，不靠反光形状。这是本次改造里
## 「材质语义工厂」与 Messenger 观感的唯一冲突点 —— 12 个语义（塑料/金属/混凝土/
## 瓦/木/玻璃/橡胶/植被/纸/铺装/沥青/朱红）的**配色**全部保留，只抹平反射参数。
## 保留形参与缓存 key 是为了不改调用点，也不影响不同语义的区分。
static func _mat_j(key: String, base: Color, pos: Vector3,
		rough: float, metal: float, jitter := 0.055) -> StandardMaterial3D:
	var ck := "%s_%d" % [key, int(abs(pos.x * 12.9898 + pos.z * 78.233)) % 997]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = _jitter_color(_unify(base), pos, jitter)
	ToonKit.apply(m)
	# 【贴图覆盖】这 12 个语义材质过去全是纯色 —— 贩卖机/电柱/浴缸/马桶/冰箱
	# 全是「一块塑料」。按 key 的语义选贴图（金属件给铁皮、瓷器给瓷砖、
	# 木箱给木板、布料给织物），选不到就按颜色兜底（见 _class_tex）。
	# 【注意】GDScript 的注释是 #，行首写 // 会被当成除号报
	# "Expected statement, found /"。
	_attach_surface_tex(m, _semantic_tex(key, base))
	_mats[ck] = m
	return m


## 材质语义 key → 贴图 kind。**没列到的 key 不会裸模** —— 落到 _class_tex 按颜色兜底。
## 【为什么用 key 而不是材质名】这些工厂的 key 本来就是语义（mt_galva/pl_white/
## verm/tub/rug…），是最可靠的信息源；材质名是空字符串。
const SEMANTIC_TEX := {
	"mt_dark": "metal_rust", "mt_cool": "metal", "mt_galva": "metal_corrugated",
	"disp": "metal_shutter", "reg": "metal", "gate": "metal", "panel": "metal",
	"asphalt": "road", "concrete": "concrete", "tile": "tiles",
	"tub": "tiles", "wc": "tiles", "wc_seat": "tiles", "stove": "tiles",
	"fridge": "wall_white_rough", "tkm": "metal_shutter",
	"pl_white": "wall_white_rough", "pl_red": "plaster_paint", "pl_blue": "plaster_paint",
	"verm": "plaster_paint", "verm_d": "plaster_paint", "sign_band": "plaster_paint",
	"plate_face": "plaster_paint",
	"wood": "wood", "cup": "wood", "shoec": "wood", "seat": "wood", "stool": "wood",
	"crate": "wooden_panels", "cnt": "wooden_panels", "boat_hull": "wall_white_plank",
	"rug": "fabric", "rug_a": "fabric", "rug_b": "fabric",
	"curtain": "fabric_alt", "curtain_b": "fabric_alt", "towel": "fabric",
	"canvas": "fabric", "rubber": "concrete",
}


static func _semantic_tex(key: String, base: Color) -> String:
	# key 常带位置后缀（"drink3" / "good12"），按前缀匹配
	for k: String in SEMANTIC_TEX:
		if key == k or key.begins_with(k):
			return SEMANTIC_TEX[k]
	if key.begins_with("drink") or key.begins_with("can") or key.begins_with("good"):
		return "plaster_paint"          # 饮料罐/货品：彩色包装
	if key.begins_with("fib") or key.begins_with("tpot"):
		return "wood"
	return _class_tex(_unify(base))


## 给已有材质就地补一张表面贴图（三平面世界映射）。
## 供各语义工厂复用；贴图不存在时保持原样（纯色兜底，不会崩）。
static func _attach_surface_tex(m: StandardMaterial3D, kind: String, scale := 2.2) -> void:
	if not surface_tex or m == null or kind.is_empty() or not has_tex(kind):
		return
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return          # 透明件（玻璃/塑料袋）不加贴图：会立刻变浑
	if m.albedo_texture != null:
		return
	m.albedo_texture = _tex("res://assets/tex/%s_col.jpg" % kind)
	m.albedo_color = _soft_tint(m.albedo_color, 0.82)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale


## ---- 12 个材质语义 ----

## 自动贩卖机机身：朱红塑料。视觉方向 §6：点缀色降到中饱和，不抢世界
static func m_plastic_red(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var m := _mat_j("pl_red", Color(0.68, 0.26, 0.24), pos, 0.35, 0.1, 0.04)
	return m


## 贩卖机/招牌面板：白塑料
static func m_plastic_white(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("pl_white", Color(0.93, 0.93, 0.9), pos, 0.4, 0.0, 0.03)


## 电柱/护栏/管道：金属。metallic 0.85 是金属感的铁律（0.3 以下看起来还是塑料）
static func m_metal_dark(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("mt_dark", Color(0.3, 0.31, 0.34), pos, 0.42, 0.85, 0.05)


## 镀锌铁皮：空调外机/铁皮屋/水槽。metallic 高但 roughness 高一些 = 旧铁皮
static func m_metal_galva(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("mt_galva", Color(0.66, 0.68, 0.7), pos, 0.55, 0.75, 0.07)


## 混凝土：建筑外墙/台阶/电线杆。roughness 0.85 吃光不反光
static func m_concrete(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("concrete", Color(0.74, 0.72, 0.68), pos, 0.88, 0.0, 0.06)


## 瓦：青灰。用 roughness 0.7，比混凝土略反光一点才像瓦
static func m_tile_roof(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("tile", Color(0.33, 0.37, 0.42), pos, 0.68, 0.05, 0.08)


## 木材：招牌框/长椅/电线杆箱
static func m_wood(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("wood", Color(0.52, 0.38, 0.26), pos, 0.76, 0.0, 0.07)


## 玻璃：窗户/便利店橱窗。
## 【Messenger 视觉】metallic 0.4 → 0，specular 关掉：Messenger 的窗是平涂亮片，
## 不是物理玻璃。半透明 + 暖自发光保留（夜里窗户会亮由 TimeOfDay 统一调制）。
static func m_glass(pos: Vector3 = Vector3.ZERO, warm := true) -> StandardMaterial3D:
	var ck := "glass%s_%d" % ["w" if warm else "c", int(abs(pos.x * 7.7 + pos.z * 3.3)) % 499]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = _unify(Color(0.66, 0.72, 0.78, 0.50))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.82, 0.5) if warm else Color(0.8, 0.9, 1.0)
	m.emission_energy_multiplier = 0.0   # 由 TimeOfDay 按时刻点亮
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats[ck] = m
	return m


## 橡胶：轮胎/盲道垫/井盖
static func m_rubber(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("rubber", Color(0.2, 0.2, 0.21), pos, 0.92, 0.0, 0.05)


## 植被：樱/树冠。改用 ToonKit.foliage —— Messenger 的 treeLeaves shader
## （风摆 + 叶片透光）。sway_phase 按位置哈希给，整排树不会整齐划一地摆。
static func m_leaf(pos: Vector3 = Vector3.ZERO) -> Material:
	var ck := "leaf_%d" % (int(abs(pos.x * 9.1 + pos.z * 4.7)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var base := _jitter_color(Color(0.47, 0.58, 0.40), pos, 0.09)
	# 相位必须用静态哈希：_var_seed 是实例方法，在 static 函数里调不到。
	var ph := float(int(abs(pos.x * 12.9898 + pos.z * 78.233)) % 628) / 100.0
	var m := ToonKit.foliage(base, ph)
	_mats[ck] = m
	return m


## 樱花瓣：浅粉 + 自发光。emission 让 Bloom 捕获（规格铁律：>1 才被捕获）
static func m_petal() -> StandardMaterial3D:
	if _mats.has("petal"):
		return _mats["petal"]
	var m := StandardMaterial3D.new()
	m.albedo_color = _unify(Color(0.96, 0.78, 0.85))
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.9
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.9)
	m.emission_energy_multiplier = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats["petal"] = m
	return m


## 和纸灯笼：粗糙 0.95 + 自发光（和纸透光）。夜晚是画面亮点
static func m_paper(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var ck := "paper_%d" % (int(abs(pos.x * 5.3 + pos.z * 8.1)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = _unify(Color(0.96, 0.9, 0.76))
	m.roughness = 0.95
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = Color(1.0, 0.72, 0.36)
	m.emission_energy_multiplier = 0.0   # TimeOfDay 点亮
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	ToonKit.apply(m)
	_attach_surface_tex(m, "tatami", 3.0)   # 和纸的纤维感 ≈ 榻榻米编织纹
	_mats[ck] = m
	return m


## 铺装：人行道砖。顶点色做砖缝明暗交替
static func m_paving(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	var ck := "pave_%d" % (int(abs(pos.x * 2.1 + pos.z * 3.7)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = _jitter_color(_unify(Color(0.66, 0.64, 0.6)), pos, 0.07)
	m.roughness = 0.8
	m.metallic = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	ToonKit.apply(m)
	_attach_surface_tex(m, "pavers", 0.9)   # 地面是玩家天天踩的面，不能是纯色
	_mats[ck] = m
	return m


## 霓虹/招牌发光字：UNSHADED + emission 强度（视觉方向 §15：Bloom 克制，默认降到 1.8）
## 【铁律】emission_energy_multiplier 必须 > 1，否则 Bloom 不捕获，看起来就是块白板
static func m_neon(tint := Color(0.86, 0.58, 0.66), energy := 1.8) -> StandardMaterial3D:
	var ck := "neon_%s_%.1f" % [tint.to_html(), energy]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	_mats[ck] = m
	return m


## 亮着的窗户/灯箱：UNSHADED 自发光，TimeOfDay 调制（默认强度按 §15 降到 1.5）
static func m_glow(tint := Color(1.0, 0.78, 0.4), energy := 1.5) -> StandardMaterial3D:
	var ck := "glow_%s_%.1f" % [tint.to_html(), energy]
	if _mats.has(ck):
		return _mats[ck]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = tint
	m.emission_energy_multiplier = energy
	_mats[ck] = m
	return m


## 沥青：路面。roughness 高 = 不反光（湿路面才反光，那是另一个材质）
static func m_asphalt(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("asphalt", Color(0.3, 0.3, 0.32), pos, 0.95, 0.0, 0.05)


## 斑马线白漆：粗糙但亮，纯白反光
static func m_paint_white() -> StandardMaterial3D:
	if _mats.has("paint_w"):
		return _mats["paint_w"]
	var m := StandardMaterial3D.new()
	m.albedo_color = _unify(Color(0.85, 0.85, 0.82))
	m.roughness = 0.75
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	ToonKit.apply(m)
	_attach_surface_tex(m, "wall_white_rough", 1.8)   # 白漆面：粗糙白墙漆的颗粒
	_mats["paint_w"] = m
	return m


## 饱和朱红（点缀色，占比 < 5%）：朱红邮筒/消火栓/鸟居。已按视觉方向 §6 降档
static func m_vermilion(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("verm", Color(0.72, 0.32, 0.28), pos, 0.45, 0.05, 0.05)


## 暖黄（灯笼/灯箱的纸）
static func m_warm_paper(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return m_paper(pos)


## 冷色金属（信号灯杆/护栏）
static func m_metal_cool(pos: Vector3 = Vector3.ZERO) -> StandardMaterial3D:
	return _mat_j("mt_cool", Color(0.42, 0.45, 0.5), pos, 0.5, 0.6, 0.06)


## 树叶/灌木：比 m_leaf 更深更哑。用同一个 foliage shader，靠 tint 区分深浅。
static func m_foliage(pos: Vector3 = Vector3.ZERO) -> Material:
	var ck := "foliage_%d" % (int(abs(pos.x * 7.7 + pos.z * 3.3)) % 499)
	if _mats.has(ck):
		return _mats[ck]
	var base := _jitter_color(Color(0.32, 0.42, 0.30), pos, 0.1)
	var ph := float(int(abs(pos.x * 7.7 + pos.z * 3.3)) % 628) / 100.0
	var m := ToonKit.foliage(base, ph, 2.0)
	_mats[ck] = m
	return m


# ---------------- 几何体工具 ----------------
# 【Messenger 视觉】material 形参放宽为 Material：mat_photo() 现在会返回
# ShaderMaterial（大面走真 toon shader），这些形参若还写死 StandardMaterial3D
# 会直接类型报错。

func box(size: Vector3, pos: Vector3, color: Color, ry := 0.0, rx := 0.0, rz := 0.0, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	# 传最大边长：贴图密度按物件尺度分档（见 mat() 的 BUCKET_SCALE）
	mi.material_override = material if material != null else mat(color, maxf(size.x, maxf(size.y, size.z)))
	mi.position = pos
	mi.rotation = Vector3(rx, ry, rz)
	add_child(mi)
	return mi


## 室外踏步（真实几何 + 真实贴图，不用纯色盒子凑）。
##
## 【为什么要专门写一个】原来门口的"台阶"只是一个 0.16m 高的纯色长盒
## （_shop_front 末尾）或 0.9m 的混凝土基座（车站）。它们**没有踏步分隔**，
## 远看是一块水泥台，近看是塑料；而台阶是玩家每天进进出出踩的面，
## 也是日式街景辨识度最高的元素之一（缘石台阶 + 防滑条 + 排水沟）。
##
## 做法：每一级 = 一块独立 box（踏面+ 立面补齐到地面，侧面看是实心锯齿），
## 材质统一走 mat_photo 的**现成 CC0 贴图**
## （step_concrete / step_grey / step_granite / step_wood / step_antiskid），
## 不再自己画灰度图案。
##
## 【碰撞】每级自带一个 StaticBody3D。这里不挂到 _ready() 建的 body 上：
## _build_visual() 在 _ready() 之前跑，body 那时还不存在；而且台阶在建筑
## 碰撞盒**外面**（+z 侧），独立 body 最省事也最不容易漏。
##
## 参数：
##   width 台阶宽（x）、n 级数、rise 每级高、run 每级进深（+z 方向为下行）
##   pos   台阶**最上一级踏面**的中点（x, z 用；y 被 base_y + rise*n 覆盖）
##   mat   贴图 kind
##   rail  是否加两侧挡墙（车站/公共建筑用 true，民居用 false）
##   base_y 台阶底面所在高度（默认 0；建在基座/站台上时传基座顶面高度）
func stairs_front(width: float, n: int, rise: float, run: float, pos: Vector3,
		mat: String, rail := false, base_y := 0.0,
		side_mat := "step_granite") -> void:
	n = maxi(1, n)
	var tread := mat_photo(mat, Color(0.94, 0.93, 0.90), 0.86, 0.82, 1.4,
		ProceduralTex.pavers(61), 0.8, 3.0, 0.4)
	# 每级从 base_y 一路补齐到该级顶面 —— 侧面看是实心的锯齿，不是悬空薄片
	for i in n:
		var h := rise * float(i + 1)
		var z := pos.z + run * (float(n - 1 - i) + 0.5)
		var mi := box(Vector3(width, h, run), Vector3(pos.x, base_y + h * 0.5, z),
			Color.WHITE, 0.0, 0.0, 0.0, tread)
		mi.name = "StairStep%d" % i
		_step_collider(Vector3(width, h, run), Vector3(pos.x, base_y + h * 0.5, z))
	# 两侧挡墙/扶手：把台阶收进两侧，读起来像「有边界的楼梯」而不是一块斜坡
	if rail:
		var sm := mat_photo(side_mat, Color(0.90, 0.89, 0.86), 0.88, 0.86, 1.2,
			ProceduralTex.pavers(63), 0.7, 2.6, 0.4)
		var total_h := rise * float(n)
		var total_d := run * float(n)
		for sx in [-1.0, 1.0]:
			var p := Vector3(pos.x + sx * (width * 0.5 + 0.08),
				base_y + (total_h + 0.08) * 0.5,
				pos.z + run * (float(n) - 1) * 0.5 + run * 0.5 - 0.1)
			var sz := Vector3(0.16, total_h + 0.08, total_d + 0.2)
			box(sz, p, Color.WHITE, 0.0, 0.0, 0.0, sm)
			_step_collider(sz, p)


## 单级台阶（一级踏步 + 补齐到地面的立面）。
## top_y = 踏面顶面高度；front_z = 踏步最外沿（朝玩家那一侧）的 z。
func step_single(width: float, rise: float, run: float, top_y: float, front_z: float,
		mat := "step_concrete") -> void:
	var tread := mat_photo(mat, Color(0.94, 0.93, 0.90), 0.86, 0.82, 1.6,
		ProceduralTex.pavers(65), 0.8, 3.0, 0.4)
	var p := Vector3(0, top_y * 0.5, front_z + run * 0.5)
	box(Vector3(width, top_y, run), p, Color.WHITE, 0.0, 0.0, 0.0, tread)
	_step_collider(Vector3(width, top_y, run), p)


## 台阶专用碰撞体（layer 1 = 玩家会撞的实心层，与建筑 body 同层）。
func _step_collider(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	body.position = pos
	add_child(body)


func cyl(top_r: float, bottom_r: float, h: float, pos: Vector3, color: Color, axis_z := false, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = h
	mesh.radial_segments = 14
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color, maxf(h, maxf(top_r, bottom_r) * 2.0))
	mi.position = pos
	if axis_z:
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	add_child(mi)
	return mi


func sph(r: float, pos: Vector3, color: Color, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 16
	mesh.rings = 10
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color, r * 2.0)
	mi.position = pos
	add_child(mi)
	return mi


func torus(inner: float, outer: float, pos: Vector3, color: Color, upright := false, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mi.mesh = mesh
	mi.material_override = material if material != null else mat(color, (outer - inner) * 2.0 + outer)
	mi.position = pos
	if upright:
		mi.rotation = Vector3(PI * 0.5, 0, 0)
	add_child(mi)
	return mi


func prism(size: Vector3, pos: Vector3, material: Material, ry := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = Vector3(0, ry, 0)
	add_child(mi)
	return mi


# ================================================================
# 外部模型（GLB / glTF）
# ================================================================
# 【为什么换成外部模型】手搭的低多边形只能到「能看」这一档，剪影和比例怎么调都有
# 股「零件拼装」味。树、猫狗、家具、车这类交给现成资产库（Kenney / Quaternius，CC0），
# 画质和手写代码不在一个量级。归一化/染色/动画查找的公共逻辑在 ModelUtil 里。
#
# 选型标准：CC0 或 CC-BY、单文件自带 buffer、纯色材质无贴图（移动端友好）。

const MODEL_ROOT := "res://assets/models/"

## Kenney 家具的原色偏「浅桦木」（0.9/0.6/0.39），在本场景的暖色夕照下会整体发粉。
## 乘一层略深的暖木色压住它，家具才和街道的色调是一家人。
const TINT_WOOD := {"wood": Color("b07440"), "woodDark": Color("8a5527")}
const TINT_WOOD_WARM := {"wood": Color("c08a52"), "woodDark": Color("9a6634")}
## 布艺：灰绿沙发 + 米色坐垫，和旧手搭版一致
const TINT_FABRIC := {"carpet": Color("93a89b"), "carpetWhite": Color("e6e0d2")}


## 摆一个外部模型。tints = {"leafs": 颜色}，按材质名子串染色。
func _glb(rel: String, pos: Vector3, scl := 1.0, ry := 0.0, tints := {}) -> Node3D:
	var n := ModelUtil.spawn(self, rel, pos, 0.0, ry, tints)
	if n != null and scl != 1.0:
		n.scale = Vector3.ONE * scl
	return n


## 摆一个外部模型并归一化到指定高度（米）。家具/树用这个：
## 高度直接对齐 META 里为「猫能跳上去」调好的数值，碰撞体不用动。
func _glb_h(rel: String, height: float, pos := Vector3.ZERO, ry := 0.0, tints := {}) -> Node3D:
	return ModelUtil.spawn(self, rel, pos, height, ry, tints)


func text3d(s: String, px: int, pos: Vector3, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font = UiKit.font()
	l.font_size = px
	l.modulate = color
	l.outline_size = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.position = pos
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


## 玻璃窗：白框 + 玻璃 + 窗台。
## 批次 3：玻璃用暖色自发光材质，夜晚由 TimeOfDay 点亮 —— 亮着的窗是「街道感」的核心。
## vary: 同一栋楼的窗给不同亮度，避免整排窗一个样（顶点色微差思路）
func _window_unit(w: float, h: float, pos: Vector3, frame_col := Color("f2efe6"),
		lit := true, vary := 0.0) -> void:
	var frame := m_plastic_white(position)
	box(Vector3(w + 0.14, h + 0.14, 0.09), pos + Vector3(0, 0, -0.02), Color.WHITE, 0,0,0, frame)
	# 窗玻璃：暖色自发光，emission 基准值带随机（模拟不同房间的灯亮度）
	var bright := 1.0 + _var_seed(pos, vary)
	var glass := m_glass(pos, true) if lit else m_glass(pos, false)
	if lit:
		# 每扇窗独立材质实例，才能有不同亮度
		var ck := "win_%.0f_%.2f" % [int(abs(pos.x * 31.7 + pos.y * 17.3)), bright]
		if not _mats.has(ck):
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.72, 0.66, 0.54, 0.6)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.roughness = 0.08
			gm.metallic = 0.3
			gm.emission_enabled = true
			gm.emission = Color(1.0, 0.84, 0.56)
			gm.emission_energy_multiplier = 0.0   # TimeOfDay 点亮
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			_mats[ck] = gm
		glass = _mats[ck]
		glass.emission_energy_multiplier = 0.0
		# 记下基准值供 TimeOfDay 调制时读取
		if not _win_base.has(glass.get_instance_id()):
			_win_base[glass.get_instance_id()] = bright * 1.8
	box(Vector3(w, h, 0.07), pos + Vector3(0, 0, 0.01), Color.WHITE, 0,0,0, glass)
	box(Vector3(w, 0.05, 0.08), pos, Color.WHITE, 0,0,0, frame)
	box(Vector3(0.05, h, 0.08), pos, Color.WHITE, 0,0,0, frame)
	# 窗台：混凝土质感
	box(Vector3(w + 0.24, 0.09, 0.2), pos + Vector3(0, -h * 0.5 - 0.07, 0.03), Color.WHITE, 0,0,0, m_concrete(pos))


## 窗户基准亮度表（供 TimeOfDay 查询）
static var _win_base := {}

## 位置哈希种子：给同类物件做细微差异
func _var_seed(pos: Vector3, salt := 0.0) -> float:
	var h := int(abs(pos.x * 12.9898 + pos.z * 78.233 + salt * 37.719)) % 1000
	return (float(h) / 1000.0 - 0.5) * 0.9


## 墙挂空调外机
func _ac_unit(pos: Vector3) -> void:
	box(Vector3(0.75, 0.55, 0.32), pos, Color("d8d8d4"))
	box(Vector3(0.6, 0.4, 0.05), pos + Vector3(0, 0, 0.16), Color("a8a8a4"))
	cyl(0.04, 0.04, 1.2, pos + Vector3(0.3, -0.5, 0.1), Color("b8b0a4"))


## 悬挂两点间的电线（中部下垂）
static func _wire(parent: Node3D, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var mid := (a + b) * 0.5 - Vector3(0, 0.45, 0)
	for seg in [[a, mid], [mid, b]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = r
		mesh.bottom_radius = r
		mesh.height = p0.distance_to(p1)
		mesh.radial_segments = 5
		mi.mesh = mesh
		mi.material_override = mat(col, r * 2.0)
		parent.add_child(mi)
		mi.position = (p0 + p1) * 0.5
		var dir := p1 - p0
		if dir.length() > 0.01:
			mi.look_at_from_position(mi.position, p1)
			mi.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)


## 在一组电线杆之间拉电线（按行/列自动连接）
static func build_wires(parent: Node3D, poles: Array[Vector3]) -> void:
	var rows := {}
	var cols := {}
	for p in poles:
		rows.get_or_add(roundi(p.z), []).append(p)
		cols.get_or_add(roundi(p.x), []).append(p)
	for key in rows:
		var arr: Array = rows[key]
		if arr.size() < 2:
			continue
		arr.sort_custom(func(a, b): return a.x < b.x)
		for i in arr.size() - 1:
			var a: Vector3 = arr[i]
			var b: Vector3 = arr[i + 1]
			if b.x - a.x > 16.0:
				continue
			for off in [-0.55, 0.0, 0.55]:
				_wire(parent, a + Vector3(0, 5.55, off), b + Vector3(0, 5.55, off), 0.022, Color("34363d"))
			_wire(parent, a + Vector3(0.2, 6.1, 0), b + Vector3(0.2, 6.1, 0), 0.018, Color("3d4048"))
	for key in cols:
		var arr: Array = cols[key]
		if arr.size() < 2:
			continue
		arr.sort_custom(func(a, b): return a.z < b.z)
		for i in arr.size() - 1:
			var a: Vector3 = arr[i]
			var b: Vector3 = arr[i + 1]
			if b.z - a.z > 16.0:
				continue
			for off in [-0.55, 0.0, 0.55]:
				_wire(parent, a + Vector3(off, 5.55, 0), b + Vector3(off, 5.55, 0), 0.022, Color("34363d"))


# ---------------- 外形构建 ----------------

func _build_visual() -> void:
	match kind:
		"vending": _b_vending()
		"pole": _b_pole()
		"mailbox": _b_mailbox()
		"trash": _b_trash()
		"bicycle": _b_bicycle()
		"car": _b_car()
		"traffic": _b_traffic()
		"station": _b_station()
		"train": _b_train()
		"konbini": _b_konbini()
		"house": _b_house()
		"mansion": _b_mansion()
		"super": _b_super()
		"cafe": _b_cafe()
		"ramen": _b_ramen()
		"post_office": _b_post()
		"signboard": _b_signboard()
		"streetlight": _b_streetlight()
		"bench": _b_bench()
		"busstop": _b_busstop()
		"tree": _b_tree()
		"sakura": _b_sakura()
		"flower": _b_flower()
		"grass": _b_grass()
		"parksign": _b_parksign()
		"dog": _b_dog()
		"cat": _b_cat()
		"bird": _b_bird()
		"delivery": _b_delivery()
		"npc": _b_npc()
		"bowl": _b_bowl()
		"cans": _b_cans()
		"onigiri": _b_onigiri()
		"bread": _b_bread()
		"door": _b_door()
		"window": _b_window()
		"crosswalk": _b_crosswalk()
		"pipe": _b_pipe()
		"crate": _b_crate()
		"planter": _b_planter()
		"lowwall": _b_lowwall()
		"furniture": _b_furniture()
		"table": _b_table()
		"chair": _b_chair()
		"bed": _b_bed()
		"sofa": _b_sofa()
		"tv": _b_tv()
		"shelf": _b_shelf()
		"lamp": _b_lamp()
		"wash": _b_wash()
		"roadsign": _b_roadsign()
		"fireplug": _b_fireplug()
		"potplant": _b_potplant()
		"laundry": _b_laundry()
		"trashbags": _b_trashbags()
		"tires": _b_tires()
		"cones": _b_cones()
		"gasbottle": _b_gasbottle()
		"puddle": _b_puddle()
		"portal": _b_portal()
		"fridge": _b_fridge()
		"stove": _b_stove()
		"bathtub": _b_bathtub()
		"toilet": _b_toilet()
		"cupboard": _b_cupboard()
		"shoe_cabinet": _b_shoe_cabinet()
		"aircon": _b_aircon()
		"carpet": _b_carpet()
		"painting": _b_painting()
		"curtain": _b_curtain()
		"register": _b_register()
		"display_shelf": _b_display_shelf()
		"counter": _b_counter()
		"stool": _b_stool()
		"ticket_machine": _b_ticket_machine()
		"gate": _b_gate()
		"station_sign": _b_station_sign()
		# ---- 补齐（这 15 个 kind 的建模函数一直都在，只是 match 分支被注释掉了）----
		# 【曾经的 bug】分支被注释、又没有兜底 → 这些物件「有碰撞没外形」= 隐形碰撞体：
		# 玩家撞到看不见的东西，还被猫的爬墙逻辑顺着竖直面顶上天空（truck 的报案）。
		"temple": _b_temple()
		"school": _b_school()
		"hospital": _b_hospital()
		"bank": _b_bank()
		"police": _b_police()
		"library": _b_library()
		"truck": _b_truck()
		"boat": _b_boat()
		"ticket_sign": _b_ticket_sign()
		"goods": _b_goods()
		"plate": _b_plate()
		"deer": _b_deer()
		"fox": _b_fox()
		"wolf": _b_wolf()
		"turtle": _b_turtle()
		_:
			# 【兜底铁律】任何在 META 登记却没有专门建模的 kind，一律退化成「按碰撞盒
			# 大小的贴图块」—— 绝不允许再出现隐形碰撞体（撞空气 + 被爬墙弹上天）。
			_b_fallback()


## 兜底：任何没专门建模的 kind 也至少要「看得见」。按 META 的碰撞盒/点击盒做一个贴图块，
## 绝不再留隐形碰撞体 —— 「撞空气 + 被爬墙弹上天」就是这么来的。
func _b_fallback() -> void:
	var meta: Dictionary = META.get(kind, {})
	var sz := Vector3(1, 1, 1)
	var solid: Variant = meta.get("solid", null)
	if solid is Vector3:
		sz = solid
	elif meta.has("click"):
		sz = meta["click"]
	box(sz, Vector3(0, sz.y * 0.5, 0), Color("cfc7b6"), 0.0, 0.0, 0.0,
		mat_photo("concrete", Color(0.8, 0.78, 0.72), 0.0, 0.95, 0.6, ProceduralTex.plaster(71), 0.6, 2.2, 0.4))


## 商店玻璃门脸（橱窗 + 白框 + 店内货架）
func _shop_front(width: float, wall_col: Color) -> void:
	var wall_depth := 5.0 if width > 6 else 4.2
	var gz := 2.5 if width > 6 else 2.1
	var wall_c := _var(wall_col)
	# scale 0.28 = 一张贴图铺 3.5m。墙面比地面需要更密的贴图，否则瓷砖/砖缝全糊掉。
	box(Vector3(width, 3.4, wall_depth), Vector3(0, 1.7, 0), wall_c, 0.0, 0.0, 0.0,
		mat_photo("plaster_brick_01", wall_c, 0.85, 0.93, 0.42, ProceduralTex.wall_tiles(11), 1.6, 2.2, 0.45))
	_downspout(Vector3(width * 0.5 - 0.28, 0, wall_depth * 0.5 - 0.05), 3.3)
	box(Vector3(width - 1.2, 1.75, 0.08), Vector3(0, 1.02, gz - 0.03), Color("a9cede"), 0.0, 0.0, 0.0, glass_mat(Color("a9cede")))
	var n := int(width / 1.35)
	for i in n + 1:
		box(Vector3(0.09, 1.78, 0.13), Vector3(-(width - 1.2) * 0.5 + i * (width - 1.2) / n, 1.02, gz), Color.WHITE)
	box(Vector3(width - 1.2, 0.09, 0.13), Vector3(0, 0.22, gz), Color.WHITE)
	box(Vector3(width - 1.2, 0.09, 0.13), Vector3(0, 1.85, gz), Color.WHITE)
	box(Vector3(width - 1.6, 1.6, 0.2), Vector3(0, 1.05, gz - 0.9), Color("4a5560"))
	for i in 3:
		box(Vector3(width - 2.0, 0.06, 0.5), Vector3(0, 0.5 + i * 0.45, gz - 0.75), Color("d9d4c6"))
	box(Vector3(width, 0.16, wall_depth + 0.15), Vector3(0, 0.08, 0), Color("b5aea0"), 0.0, 0.0, 0.0,
		mat_photo("pavers", Color(0.82, 0.8, 0.75), 0.0, 0.94, 0.5, ProceduralTex.pavers(21), 0.5, 2.2, 0.35))
	# 【新增】店铺门口的缘石台阶：原来只有上面那条 0.16m 纯色基座，
	# 没有踏步分隔 —— 玩家看不出这是「能踩上去的台阶」，只是墙根一条塑料带。
	# 现在门前给 2 级真实踏步（每级 0.16m），用现成step_concrete 贴图。
	# 位置：基座外沿往 +z 让出0.16m，正好接在基座前面，不改基座本体。
	stairs_front(width - 1.8, 2, 0.16, 0.30, Vector3(0, 0, gz + 0.18),
		"step_concrete", false, 0.0)


func _b_konbini() -> void:
	_shop_front(6.5, Color("f4f1e8"))
	box(Vector3(6.5, 1.0, 0.3), Vector3(0, 3.0, 2.42), Color("2f6fb2"))
	text3d("コンビニ", 130, Vector3(0, 3.0, 2.6), Color.WHITE)
	box(Vector3(6.6, 0.16, 0.4), Vector3(0, 3.55, 2.42), Color("245a91"))
	var awn := box(Vector3(6.3, 0.1, 1.45), Vector3(0, 2.42, 2.9), Color("2f6fb2"))
	awn.rotation = Vector3(-0.28, 0, 0)
	box(Vector3(6.3, 0.07, 0.2), Vector3(0, 2.2, 3.55), Color.WHITE)
	box(Vector3(0.06, 1.1, 0.8), Vector3(3.26, 2.0, 0.9), Color("e05a5a"))
	box(Vector3(0.06, 1.1, 0.8), Vector3(3.26, 2.0, 1.9), Color("e6b84c"))
	_ac_unit(Vector3(-3.0, 2.6, 1.2))


func _b_super() -> void:
	_shop_front(7.6, Color("eef0e6"))
	box(Vector3(7.6, 1.1, 0.3), Vector3(0, 3.9, 2.6), Color("2f855a"))
	text3d("スーパー", 140, Vector3(0, 3.9, 2.78), Color.WHITE)
	var awn := box(Vector3(7.4, 0.1, 1.55), Vector3(0, 3.15, 3.1), Color("2f855a"))
	awn.rotation = Vector3(-0.26, 0, 0)
	box(Vector3(7.4, 0.07, 0.2), Vector3(0, 2.9, 3.82), Color.WHITE)
	box(Vector3(1.0, 1.3, 0.06), Vector3(-2.4, 1.2, 2.72), Color("d64541"))
	box(Vector3(1.0, 1.3, 0.06), Vector3(2.4, 1.2, 2.72), Color("e6b84c"))
	_ac_unit(Vector3(-3.4, 2.9, 1.3))
	_ac_unit(Vector3(3.4, 2.9, 1.3))


## 日式传统墙色序列（12 色， attested 于实际町屋/仓库立面）。
##
## 【为什么需要这一组】原先 12 栋民居**全部**用 `grey_plaster` 配 tint≈(0.98,0.96,0.92)
## —— 贴图本身就是灰水泥色，于是整条街渲染出来是一片同调灰板，
## 这正是「画面偏灰」的根因。真实的日式街道每一栋墙色都不同，
## 米黄/灰蓝/苔绿/藤茶交替出现，是这条街最重要的色彩识别特征。
##
## 颜色都刻意压到低饱和（sat < 0.18）：项目有全局饱和度上限 0.42（见 _unify），
## 高饱和墙色会在暖色夕照下变成糖果色，与 Messenger 平涂风格冲突。
## 值域 [0.72, 0.91] 明度 —— 亮到在暖光下不发黑，暗到能压住背景天空。
const HOUSE_PAINTS := [
	Color("e8dcc4"),  # 0 米黄（最常见）
	Color("dccdb0"),  # 1 浅麦
	Color("c9bda6"),  # 2 灰米
	Color("b9c2bd"),  # 3 灰蓝  ← 冷调，打破连续暖色
	Color("c2b89a"),  # 4 藤茶
	Color("d4c4ae"),  # 5 暖灰
	Color("e2d6bd"),  # 6 象牙
	Color("cdbfae"),  # 7 土白
	Color("dfd2bb"),  # 8 米白
	Color("cfc4b2"),  # 9 灰砂
	Color("b6bfb4"),  # 10 青灰  ← 第二个冷调锚点
	Color("e0d3bb"),  # 11 亚麻
]

## 按实例位置取墙色：同一栋房子在任何一次运行里都是同一个颜色（用位置哈希，
## 不用随机数），但不同房子之间会错开。
##
## 【本轮新增：贴图本身也轮转，不只换 tint】
## 原来 12 栋的**贴图**全是同一张 `grey_plaster`，只有 tint 在变。
## 但贴图决定的是「表面是什么」—— 木纹壁 / 白灰涂装 / 竹编 / 板壁的
## 纹理走向完全不一样，tint 再怎么调也只是同一张灰泥上换个色。
## 真实的日式街道每栋房子的立面材料本来就不同（板壁、抹灰、瓷砖、砖），
## 所以这里给 6 种现成 CC0 贴图，按位置哈希轮转（与 HOUSE_PAINTS 同索引，
## 两者错开取模避免「同色+同纹」锁死在一起）。
const HOUSE_WALL_TEX := [
	"wall_white_plank",# 0 白色板壁（新建町屋）
	"grey_plaster",           # 1 灰泥涂装（最常见）
	"wall_plank_siding",      # 2  weathered 木板壁
	"plaster_brick_01",       # 3 抹灰+小瓷砖
	"wall_white_rough",       # 4 粗白灰墙
	"wall_yellow",            # 5 黄灰墙（老土蔵常见）
	"concrete_tile_facade",   # 6 小口瓷砖立面
	"wall_mossy",             # 7 长苔的旧灰墙
]

## 取这栋房子该用的墙面贴图 kind。
func _house_wall_tex(pos: Vector3) -> String:
	var h := int(abs(pos.x * 13.37 + pos.z * 7.77)) % 100
	# +3 是刻意的错开：颜色和贴图同索引会让「米黄板壁」这种组合反复出现，
	# 错开后 12 栋的「颜色× 材质」组合基本不重样。
	return HOUSE_WALL_TEX[(h + 3) % HOUSE_WALL_TEX.size()]

static func _house_paint(pos: Vector3) -> Color:
	var h := int(abs(pos.x * 13.37 + pos.z * 7.77)) % 100
	return HOUSE_PAINTS[h % HOUSE_PAINTS.size()]


func _b_house() -> void:
	var wall_col := _var(Color("f2ead9"))
	var roof_col := _var(Color("4d5a74"), 0.08)
	# 墙色按实例轮转（这轮的关键改动）：原先 12 栋全是同一个灰。
	# tint_amt 从 0.9 降到 0.72 —— 让色相透出来的同时target 仍锁在 [0.82,1.0]，
	# 贴图的明暗层次（砖缝/污渍/颗粒）不会被压平。
	# 【本轮再进一步】贴图本身也按实例换（_house_wall_tex）：木板壁 / 灰泥 /
	# 瓷砖各有各的纹理走向，只换 tint 换不出「这是不同材料」。
	var paint := _house_paint(position)
	var wtex_kind := _house_wall_tex(position)
	# 材质本身有强色偏的贴图（竹编/苔痕/木板）要压低 tint_amt，
	# 否则 HOUSE_PAINTS 的色相乘上去会串色。用 _unify 的思路先看亮度：
	# 深色贴图配深色 paint 会糊成一块，所以深色贴图统一把 paint 提亮。
	var dark_tex := wtex_kind in ["wall_plank_siding", "wall_mossy", "wall_bamboo"]
	var use_paint := Color(0.95, 0.93, 0.89) if dark_tex else paint
	var tamt := 0.62 if dark_tex else 0.72
	# 墙面 scale 也随材质走：木板/竹编是长条纹理，需要更密的贴图才看得出走向；
	# 抹灰是均匀面，密了反而噪。
	var wscale := 0.62 if wtex_kind in ["wall_white_plank", "wall_plank_siding", "wall_bamboo"] else 0.4
	box(Vector3(4.2, 2.7, 3.6), Vector3(0, 1.35, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo(wtex_kind, _var(use_paint), tamt, 0.95, wscale, ProceduralTex.plaster(12), 0.55, 2.0, 0.4))
	# 屋顶：改用 patterned_slate_tiles（深色石板瓦，磁盘上一直闲置）。
	# 【为什么换】原来的 roof 贴图是 512×512 的模糊瓦片，1.3 的 tex_scale
	# 把它铺到 0.77 米/张 —— 远看是一团糊，近看没有瓦片形状。
	# patterned_slate_tiles 是 1024×1024 的清晰石板瓦，瓦片边缘/苔痕/接缝
	# 都可辨；配 0.55 的 tex_scale（1.8 米/张）刚好一块屋面能看清瓦片走向。
	# 颜色参数调暖（0.92,0.86,0.80）压掉石板的冷黑，融进黄昏暖调。
	prism(Vector3(3.9, 1.5, 4.8), Vector3(0, 3.45, 0),
		mat_photo("patterned_slate_tiles", _var(Color(0.92, 0.86, 0.80)), 0.78, 0.72, 0.55, ProceduralTex.roof_tiles(7), 1.1, 2.4, 0.45), PI * 0.5)
	box(Vector3(4.75, 0.14, 0.3), Vector3(0, 4.12, 0), roof_col.darkened(0.25))
	box(Vector3(4.4, 0.1, 0.1), Vector3(0, 2.76, 1.82), Color("d9d2c0"))  # 檐沟
	_window_unit(1.0, 1.0, Vector3(-1.25, 1.7, 1.81))
	_window_unit(1.0, 1.0, Vector3(1.25, 1.7, 1.81))
	# 格子块围墙 + 门柱（前侧留门口）
	# 围墙也按实例换贴图：原来的 rustic_stone_wall 是「圆石墙」，但代码注释写的
	# 是「格子块围墙（ブロック塀）」—— 混凝土方块墙。日式住宅这两种都常见，
	# 12栋各分一半更像真实的町屋。
	var wall_kind := "wall_block" if (int(abs(position.x * 13.37 + position.z * 7.77)) % 2 == 0) else "rustic_stone_wall"
	var wtex := mat_photo(wall_kind, Color(0.9, 0.87, 0.82), 0.9, 0.96, 0.85, ProceduralTex.pavers(31), 0.55, 2.6, 0.5)
	box(Vector3(7.4, 1.12, 0.2), Vector3(0, 0.56, -3.0), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.2, 1.12, 4.2), Vector3(-3.6, 0.56, -0.9), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.2, 1.12, 4.2), Vector3(3.6, 0.56, -0.9), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(2.3, 1.0, 0.18), Vector3(-2.5, 0.5, 1.35), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(2.3, 1.0, 0.18), Vector3(2.5, 0.5, 1.35), Color("bdb6a6"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.26, 1.5, 0.26), Vector3(-1.3, 0.75, 1.35), Color("a8a294"), 0.0, 0.0, 0.0, wtex)
	box(Vector3(0.26, 1.5, 0.26), Vector3(1.3, 0.75, 1.35), Color("a8a294"), 0.0, 0.0, 0.0, wtex)
	sph(0.45, Vector3(-3.0, 0.42, 1.9), Color("5e8f52"))
	sph(0.34, Vector3(-2.5, 0.32, 2.15), Color("6faf5f"))
	sph(0.4, Vector3(3.0, 0.38, 1.95), Color("5e8f52"))
	_ac_unit(Vector3(1.9, 2.35, 1.75))
	box(Vector3(0.34, 0.12, 0.03), Vector3(0.75, 2.1, 1.83), Color.WHITE)
	# 【新增】玄关石阶：日式民宅门口最标志性的元素。围墙门柱之间原本直接是平地，
	# 现在给 2 级石阶（每级 0.17m）+ 阶前的蹲踞石（Categorical：日式玄关必有）。
	# 用现成 step_granite（花岗岩）贴图，石材的颗粒感比纯色盒强得多。
	stairs_front(1.9, 2, 0.17, 0.28, Vector3(0, 0, 2.02), "step_granite", false, 0.0)
	# 蹲踞石（つばさ石）：门内一块立着的扁平石头
	box(Vector3(0.46, 0.30, 0.14), Vector3(0.85, 0.15, 1.92), Color("8e8b82"), 0.0, 0.0, 0.0,
		mat_photo("step_granite", Color(0.82, 0.81, 0.78), 0.88, 0.84, 2.0, ProceduralTex.pavers(66), 1.0, 3.0, 0.4))


func _b_mansion() -> void:
	var wall_col := _var(Color("ddd6c8"))
	# 大宅（4 栋）用偏冷偏深的土墙色，与民居的暖米黄拉开层级 ——
	# 富裕人家的立面在町屋里通常是深土/灰褐，与平民的浅色形成对比。
	# 不用纯灰：太深在黄昏背光面会读不出贴图，太浅又和民居没区别。
	box(Vector3(4.2, 9.5, 3.8), Vector3(0, 4.75, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("plaster_alt", _var(Color(0.80, 0.78, 0.74)), 0.72, 0.93, 0.42, ProceduralTex.wall_tiles(13), 2.0, 2.0, 0.4))
	_downspout(Vector3(-2.05, 0, 1.85), 9.4)
	box(Vector3(4.6, 0.4, 4.2), Vector3(0, 9.65, 0), Color("6a6d76"))
	for f in 5:
		var y := 1.55 + f * 1.62
		box(Vector3(3.9, 0.12, 0.85), Vector3(0, y, 2.2), Color("c4bcab"))
		box(Vector3(3.9, 0.06, 0.06), Vector3(0, y + 0.55, 2.6), Color("9aa0ab"))
		for bx in 9:
			box(Vector3(0.045, 0.55, 0.045), Vector3(-1.8 + bx * 0.45, y + 0.28, 2.6), Color("9aa0ab"))
		for wx in [-1.1, 1.1]:
			box(Vector3(1.2, 1.3, 0.1), Vector3(wx, y + 0.75, 1.88), Color("efe9da"))
			box(Vector3(1.1, 1.2, 0.08), Vector3(wx, y + 0.75, 1.92), Color("a8c4d8"), 0.0, 0.0, 0.0, glass_mat(Color("9dbfd6")))
	# 门廊平台：原来架在 y=2.5（半空，猫跳不上去、远看像块悬板），
	# 降到 y=1.9 —— 6 级 × 0.316m 刚好接上来，且每级都 < STEP_CLIMB 0.34 能踩上去。
	box(Vector3(2.2, 0.14, 1.15), Vector3(0, 1.9, 2.3), Color("8b7f6a"))
	box(Vector3(0.18, 1.9, 0.18), Vector3(-0.9, 0.95, 2.75), Color("8b7f6a"))
	box(Vector3(0.18, 1.9, 0.18), Vector3(0.9, 0.95, 2.75), Color("8b7f6a"))
	cyl(0.55, 0.55, 1.0, Vector3(-1.1, 10.3, -0.6), Color("6b8bab"))
	cyl(0.2, 0.2, 0.5, Vector3(-1.1, 9.75, -0.6), Color("55575e"))
	cyl(0.35, 0.35, 0.85, Vector3(1.2, 10.25, -0.7), Color("6b8bab"))
	for rx in [-2.0, 2.0]:
		box(Vector3(0.06, 0.7, 0.06), Vector3(rx, 10.15, 1.9), Color("8a8d96"))
	box(Vector3(4.1, 0.06, 0.06), Vector3(0, 10.5, 1.9), Color("8a8d96"))
	cyl(0.03, 0.03, 2.2, Vector3(0.6, 10.8, -0.8), Color("8a8d96"))
	# 【新增】大宅门廊台阶：连廊平台在 y=1.9（原来 2.5m 是悬空的，猫跳不上去也看不出是入口）。
	# 6 级 × 0.316m，每级都 < STEP_CLIMB 0.34，踩得上去；用现成 step_granite 贴图。
	stairs_front(2.0, 6, 0.316, 0.26, Vector3(0, 0, 2.36), "step_granite", false, 0.0)


func _b_cafe() -> void:
	box(Vector3(5.2, 1.3, 4.2), Vector3(0, 0.65, 0), Color("b08d5e"), 0.0, 0.0, 0.0,
		mat_photo("brown_planks_08", _var(Color(0.86, 0.72, 0.56)), 0.88, 0.95, 0.55, ProceduralTex.wood(15), 0.9, 2.2, 0.45))
	box(Vector3(5.2, 2.3, 4.2), Vector3(0, 2.45, 0), _var(Color("c9a876")), 0.0, 0.0, 0.0,
		mat_photo("plaster_brick_01", _var(Color(0.95, 0.86, 0.7)), 0.88, 0.95, 0.44, ProceduralTex.plaster(16), 0.55, 2.0, 0.4))
	box(Vector3(5.5, 0.32, 4.5), Vector3(0, 3.7, 0), Color("6b4a2f"))
	box(Vector3(4.6, 0.95, 0.2), Vector3(0, 3.1, 2.12), Color("6b4a2f"))
	text3d("喫茶店", 120, Vector3(0, 3.1, 2.26), Color("f2e6cf"))
	var win := cyl(0.5, 0.5, 0.1, Vector3(-1.5, 2.0, 2.1), Color("c8dcc8"), true)
	win.rotation = Vector3(PI * 0.5, 0, 0)
	win.material_override = glass_mat(Color("c8dcc8"))
	torus(0.5, 0.6, Vector3(-1.5, 2.0, 2.14), Color("6b4a2f"), true)
	box(Vector3(1.06, 0.09, 0.12), Vector3(-1.5, 2.0, 2.16), Color("6b4a2f"))
	box(Vector3(0.09, 1.06, 0.12), Vector3(-1.5, 2.0, 2.16), Color("6b4a2f"))
	_window_unit(1.0, 0.9, Vector3(1.35, 2.05, 2.11), Color("6b4a2f"))
	box(Vector3(1.2, 0.26, 0.3), Vector3(1.35, 1.35, 2.2), Color("7a5a3a"))
	for i in 3:
		sph(0.09, Vector3(1.05 + i * 0.3, 1.52, 2.2), [Color("e86a92"), Color("e6b84c"), Color("d97fb0")][i])
	var awn := box(Vector3(1.7, 0.08, 0.9), Vector3(0, 2.35, 2.5), Color("6b4a2f"))
	awn.rotation = Vector3(-0.3, 0, 0)
	sph(0.09, Vector3(0, 2.62, 2.28), Color("f2cc5a"))
	# 门口木台阶（老咖啡馆常见木缘侧）
	stairs_front(1.5, 2, 0.16, 0.28, Vector3(0, 0, 2.14), "step_wood", false, 0.0)


func _b_ramen() -> void:
	box(Vector3(6.2, 4.0, 4.6), Vector3(0, 2.0, 0), _var(Color("d9c49a")), 0.0, 0.0, 0.0,
		mat_photo("dark_planks", _var(Color(0.88, 0.74, 0.58)), 0.85, 0.95, 0.5, ProceduralTex.wood(17), 0.8, 2.2, 0.5))
	box(Vector3(6.4, 0.4, 4.8), Vector3(0, 4.1, 0), Color("5a4a3a"))
	box(Vector3(6.2, 0.55, 0.24), Vector3(0, 3.3, 2.28), Color("5a4a3a"))
	text3d("ラーメン", 110, Vector3(0, 3.3, 2.45), Color("f2e6cf"))
	for i in 3:
		box(Vector3(1.35, 1.2, 0.07), Vector3(-1.45 + i * 1.45, 2.42, 2.36), Color("3a4a6b"))
		box(Vector3(1.35, 0.06, 0.1), Vector3(-1.45 + i * 1.45, 3.05, 2.36), Color("2c3a55"))
	box(Vector3(1.6, 2.15, 0.1), Vector3(0, 1.08, 2.33), Color("4a3f33"))
	box(Vector3(1.3, 1.0, 0.08), Vector3(-2.3, 1.7, 2.3), Color("c8b890"), 0.0, 0.0, 0.0, glass_mat(Color("c8b890")))
	box(Vector3(0.07, 0.55, 0.07), Vector3(2.75, 3.62, 2.6), Color("5a4a3a"))
	var lamp := sph(0.42, Vector3(2.75, 3.05, 2.6), Color("c94f4f"))
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color("c94f4f")
	lm.emission_enabled = true
	lm.emission = Color("c94f4f")
	lm.emission_energy_multiplier = 0.45
	lamp.material_override = lm
	text3d("麺", 80, Vector3(2.75, 3.05, 3.05), Color.WHITE)
	box(Vector3(0.5, 2.0, 0.08), Vector3(-2.7, 2.1, 2.4), Color("f2e6cf"))
	box(Vector3(0.56, 0.1, 0.14), Vector3(-2.7, 3.15, 2.4), Color("5a4a3a"))
	text3d("ら\nー\nめ\nん", 56, Vector3(-2.7, 2.15, 2.47), Color("2b2b33"))
	box(Vector3(6.2, 0.18, 4.7), Vector3(0, 0.09, 0), Color("8a7a5e"))
	# 门口踏步（拉面店门前的水泥阶）
	stairs_front(1.6, 2, 0.16, 0.28, Vector3(0, 0, 2.32), "step_concrete", false, 0.0)


func _b_post() -> void:
	var wall_col := _var(Color("f0ede6"))
	box(Vector3(5.8, 4.4, 4.2), Vector3(0, 2.2, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("yellow_brick", _var(Color(0.98, 0.95, 0.88)), 0.9, 0.94, 0.5, ProceduralTex.wall_tiles(18), 1.6, 2.4, 0.5))
	box(Vector3(5.8, 1.05, 0.26), Vector3(0, 3.85, 2.12), Color("b91c1c"))
	text3d("〒 郵便局", 110, Vector3(0, 3.85, 2.3), Color.WHITE)
	_window_unit(1.3, 1.1, Vector3(-1.7, 2.2, 2.12))
	_window_unit(1.3, 1.1, Vector3(1.7, 2.2, 2.12))
	box(Vector3(5.8, 0.18, 4.3), Vector3(0, 0.09, 0), Color("c4bcab"), 0.0, 0.0, 0.0,
		mat_photo("pavers", Color(0.84, 0.82, 0.77), 0.0, 0.94, 0.5, ProceduralTex.pavers(41), 0.5, 2.2, 0.35))
	# 邮局门口：花岗岩宽台阶（公共建筑的做法，比民居的玄关石阶宽）
	stairs_front(2.4, 3, 0.18, 0.30, Vector3(0, 0, 2.16), "step_granite", true, 0.0)


func _b_station() -> void:
	var wall_col := _var(Color("efe9da"))
	# 车站（1 栋，独占画面中央）用冷调米灰：与周围暖色民居拉开，
	# 让它成为视觉焦点。冷色在暖色夕照下会显出「被夕阳斜照的灰泥」质感。
	box(Vector3(12.5, 4.6, 4.5), Vector3(0, 2.3, 0), wall_col, 0.0, 0.0, 0.0,
		mat_photo("grey_plaster", _var(Color(0.82, 0.84, 0.86)), 0.72, 0.92, 0.44, ProceduralTex.wall_tiles(19), 1.5, 2.0, 0.35))
	# 车站基座：混凝土贴图（裸色会在暖光下泛紫蓝，像一条塑料带）
	box(Vector3(12.6, 0.9, 4.6), Vector3(0, 0.45, 0), Color.WHITE, 0,0,0,
		mat_photo("concrete_pavers", Color(0.72, 0.73, 0.78), 0.9, 0.9, 0.55, ProceduralTex.pavers(51), 0.5, 2.4, 0.45))
	# 【新增】站台正面大台阶：原来 0.9m 基座是一整块光板，玩家面前是 0.9m 高的
	# 混凝土墙（要绕到两侧）。给正面来 6 级 0.15m 踏步（0.9/6，每级远低于
	# STEP_CLIMB 0.34，必过），带两侧收边 —— 这就是真实车站的进站口。
	stairs_front(4.6, 6, 0.15, 0.32, Vector3(0, 0, 2.34), "step_grey", true, 0.0)
	# 雨棚檐口：镀锌铁皮
	box(Vector3(12.9, 0.6, 4.9), Vector3(0, 4.8, 0), Color.WHITE, 0,0,0, m_metal_galva(position))
	box(Vector3(4.2, 1.4, 0.2), Vector3(-2.6, 4.0, 2.3), Color("2b6cb0"))
	text3d("駅", 132, Vector3(-2.6, 4.0, 2.44), Color.WHITE)
	var clock := cyl(0.5, 0.5, 0.07, Vector3(2.8, 3.7, 2.28), Color.WHITE, true)
	clock.rotation = Vector3(PI * 0.5, 0, 0)
	box(Vector3(0.06, 0.3, 0.03), Vector3(2.8, 3.78, 2.33), Color("3a3f4a"))
	box(Vector3(0.2, 0.06, 0.03), Vector3(2.9, 3.7, 2.33), Color("3a3f4a"))
	box(Vector3(9.5, 2.4, 0.1), Vector3(0, 1.35, 2.24), Color("a9cede"), 0.0, 0.0, 0.0, glass_mat(Color("a9cede")))
	for i in 7:
		box(Vector3(0.12, 2.45, 0.16), Vector3(-4.5 + i * 1.5, 1.35, 2.26), Color("d8d2c4"))
	# 候车亭：站台雨棚 + 立柱 + 长椅 + 售卖机（装饰）
	box(Vector3(12.0, 0.18, 3.0), Vector3(0, 3.3, -4.6), Color.WHITE, 0,0,0, m_metal_galva(position))
	for px in [-5.0, 0.0, 5.0]:
		box(Vector3(0.22, 3.2, 0.22), Vector3(px, 1.75, -3.4), Color("8a95a8"))
	for bx in [-3.0, 1.0]:
		box(Vector3(1.8, 0.08, 0.5), Vector3(bx, 1.17, -5.1), Color("6b8bab"))
		box(Vector3(1.8, 0.45, 0.07), Vector3(bx, 1.43, -5.32), Color("7a95b5"))
		box(Vector3(0.08, 0.5, 0.4), Vector3(bx - 0.8, 0.92, -5.1), Color("55575e"))
		box(Vector3(0.08, 0.5, 0.4), Vector3(bx + 0.8, 0.92, -5.1), Color("55575e"))
	box(Vector3(0.9, 1.8, 0.75), Vector3(-4.2, 1.45, -5.3), Color("d64541"))


func _b_train() -> void:
	for ci in 3:
		var cx := -6.5 + ci * 6.5
		box(Vector3(6.1, 2.3, 2.4), Vector3(cx, 1.75, 0), Color("e8eaee"))
		box(Vector3(6.1, 0.42, 2.44), Vector3(cx, 1.0, 0), Color("1d4ed8"))
		box(Vector3(5.7, 0.55, 2.2), Vector3(cx, 0.35, 0), Color("3a3d45"))
		for wi in 4:
			box(Vector3(1.0, 0.75, 0.06), Vector3(cx - 2.2 + wi * 1.45, 2.1, 1.22), Color("a8c4d8"), 0.0, 0.0, 0.0, glass_mat(Color("a8c4d8")))
		for dx in [-2.9, 2.9]:
			box(Vector3(0.95, 1.5, 0.07), Vector3(cx + dx, 1.45, 1.21), Color("9aa4b0"))
			box(Vector3(0.06, 1.5, 0.09), Vector3(cx + dx, 1.45, 1.22), Color("6a7480"))
		if ci == 1:
			box(Vector3(0.08, 0.9, 0.08), Vector3(cx - 0.5, 3.1, 0), Color("3a3d45"), 0.0, 0.0, 0.5)
			box(Vector3(0.08, 0.9, 0.08), Vector3(cx + 0.5, 3.1, 0), Color("3a3d45"), 0.0, 0.0, -0.5)
			box(Vector3(1.4, 0.06, 0.12), Vector3(cx, 3.5, 0), Color("3a3d45"))
		if ci < 2:
			box(Vector3(0.5, 0.8, 0.8), Vector3(cx + 3.25, 1.3, 0), Color("8a8d96"))
	box(Vector3(0.9, 0.24, 0.05), Vector3(-9.2, 2.4, 1.23), Color("1d4ed8"))
	box(Vector3(0.3, 2.0, 2.1), Vector3(-9.75, 1.75, 0), Color("c4c8d0"))
	box(Vector3(0.3, 2.0, 2.1), Vector3(9.75, 1.75, 0), Color("c4c8d0"))


func _b_vending() -> void:
	# 规格指定：朱红塑料机身（roughness 0.35）+ 白面板 + 冷白灯箱自发光。
	# 两种配色交替摆放（红/蓝），是日本街头的真实样貌。
	var is_red := int(abs(position.x * 40.0)) % 2 == 0
	var body_col := Color(0.78, 0.17, 0.16) if is_red else Color(0.16, 0.35, 0.62)
	var body := m_plastic_red(position) if is_red else _mat_j("pl_blue", body_col, position, 0.35, 0.1, 0.04)
	var panel := m_plastic_white(position)
	# 机身
	box(Vector3(0.95, 1.85, 0.8), Vector3(0, 0.925, 0), Color.WHITE, 0,0,0, body)
	box(Vector3(0.95, 0.16, 0.82), Vector3(0, 1.8, 0), Color.WHITE, 0,0,0, body)
	# 灯箱：冷白自发光，夜晚会被 Bloom 捕获 —— 街道氛围的重要来源
	var lit := m_glow(Color(0.86, 0.94, 1.0), 2.6)
	box(Vector3(0.72, 1.3, 0.07), Vector3(-0.06, 1.0, 0.41), Color.WHITE, 0,0,0, lit)
	# 饮料格：每排颜色不同，制造"里面有货"的密度感
	var drinks := [Color(0.35, 0.55, 0.9), Color(0.9, 0.72, 0.3), Color(0.5, 0.7, 0.4), Color(0.85, 0.5, 0.5)]
	for row in 4:
		for col in 2:
			var ci := (row * 2 + col) % 4
			box(Vector3(0.16, 0.26, 0.06), Vector3(-0.22 + col * 0.3, 0.48 + row * 0.32, 0.45),
				Color.WHITE, 0,0,0, _mat_j("drink%d" % ci, drinks[ci], position + Vector3(row, col, 0), 0.45, 0.0, 0.1))
			box(Vector3(0.16, 0.03, 0.07), Vector3(-0.22 + col * 0.3, 0.36 + row * 0.32, 0.45), Color.WHITE, 0,0,0, panel)
	# 取物口 + 操作面板
	box(Vector3(0.22, 1.15, 0.06), Vector3(0.33, 1.05, 0.41), Color(0.1, 0.11, 0.14), 0,0,0, m_rubber(position))
	box(Vector3(0.16, 0.4, 0.03), Vector3(0.33, 1.5, 0.44), Color.WHITE, 0,0,0, panel)
	box(Vector3(0.95, 0.1, 0.85), Vector3(0, 0.05, 0), Color.WHITE, 0,0,0, m_metal_dark(position))


func _b_pole() -> void:
	# 电线杆：混凝土杆（roughness 0.88）+ 镀锌横担（metallic 0.75）
	# 材质反差是"这看起来像真电线杆"的关键：哑光水泥 + 亮金属横担
	var cm := mat_photo("concrete", Color(0.6, 0.61, 0.64), 0.0, 0.94, 1.4,
		null, 0.5, 2.5, 0.4)
	_cyl_m(Vector3(0.09, 0.12, 7.0), Vector3(0, 3.5, 0), cm)
	var galva := m_metal_galva(position)
	var dark := m_metal_dark(position)
	box(Vector3(0.55, 0.95, 0.55), Vector3(0, 5.3, 0), Color.WHITE, 0,0,0, galva)
	box(Vector3(1.6, 0.13, 0.13), Vector3(0, 6.35, 0), Color.WHITE, 0,0,0, dark)
	box(Vector3(1.1, 0.1, 0.1), Vector3(0, 5.85, 0), Color.WHITE, 0,0,0, dark)
	for ox in [-0.65, 0.65, -0.42, 0.42]:
		var h := 0.24 if absf(ox) > 0.5 else 0.2
		cyl(0.05, 0.05, h, Vector3(ox, 6.55 if absf(ox) > 0.5 else 5.95, 0), Color.WHITE, false, m_glass_insulator())
	box(Vector3(0.16, 0.55, 0.16), Vector3(0, 0.27, 0), Color.WHITE, 0,0,0, dark)
	box(Vector3(0.16, 0.1, 0.02), Vector3(0, 2.6, 0.1), Color.WHITE)


## 绝缘子：白瓷，高光泽（roughness 0.12）
func m_glass_insulator() -> StandardMaterial3D:
	if _mats.has("insul"):
		return _mats["insul"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.9, 0.88)
	_attach_surface_tex(m, "tiles", 4.0)   # 白瓷绝缘子：釉面小砖纹
	m.roughness = 0.14
	m.metallic = 0.05
	m.metallic_specular = 0.7
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mats["insul"] = m
	return m


## 圆柱（电线杆、树干等）带贴图版本
## 【Messenger 视觉】material 放宽为 Material —— 调用点传的是 mat_photo() 的返回值，
## 现在可能是 ShaderMaterial。
func _cyl_m(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = size.x
	mesh.bottom_radius = size.y
	mesh.height = size.z
	mesh.radial_segments = 12
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi


## 金属/涂装表面材质（铁杆、铁轨、空调外机等）
func mat_metal(tint: Color, rough := 0.55) -> StandardMaterial3D:
	var key := "mt_%s_%f" % [tint.to_html(), rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = 0.35
	m.metallic_specular = 0.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	ToonKit.apply(m)
	_attach_surface_tex(m, "metal", 1.6)   # 铁杆/铁轨/空调外机：铁皮贴图
	_mats[key] = m
	return m


## 树皮材质（按 kind 区分树种）
func mat_bark(kind: String, tint: Color) -> StandardMaterial3D:
	var key := "bk_%s_%s" % [kind, tint.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	# 树皮是竖纹，拉伸的 UV 更像真树皮
	m.uv1_scale = Vector3(2.5, 0.35, 2.5)
	m.albedo_color = tint
	m.roughness = 0.98
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var col := _tex("res://assets/tex/%s_col.jpg" % kind)
	if col != null:
		m.albedo_texture = col
		var nrm := _tex("res://assets/tex/%s_nrm.jpg" % kind)
		if nrm != null:
			m.normal_enabled = true
			m.normal_texture = nrm
			m.normal_scale = 1.0
	_mats[key] = m
	return m


func _b_mailbox() -> void:
	# 【尺度】0.55m —— 矮型邮筒（日本街头常见的那种圆筒矮邮筒）。
	# 朱红点缀色（规格：画面占比 <5% 但吸走 80% 注意力），猫可以跳上去。
	var red := m_vermilion(position)
	var red_dark := _mat_j("verm_d", Color(0.62, 0.18, 0.15), position, 0.5, 0.05, 0.04)
	var metal := m_metal_galva(position)
	# 圆筒形（经典日式邮筒），比方形矮墩更适合猫尺度
	cyl(0.24, 0.26, 0.44, Vector3(0, 0.22, 0), Color.WHITE, false, red)
	# 顶盖：平顶圆盘，不要半球 —— 半球直径 0.5m 会在近景里大得离谱，
	# 而且猫踩半球不方便（曲面站不稳）。平顶也更像真实邮筒。
	cyl(0.27, 0.27, 0.06, Vector3(0, 0.465, 0), Color.WHITE, false, red_dark)
	cyl(0.1, 0.1, 0.04, Vector3(0, 0.51, 0), Color.WHITE, false, red_dark)
	# 投信口
	box(Vector3(0.3, 0.05, 0.05), Vector3(0, 0.36, -0.23), Color(0.1, 0.08, 0.08), 0,0,0, m_rubber(position))
	text3d("〒", 76, Vector3(0, 0.24, -0.26), Color.WHITE)
	# 底座
	cyl(0.27, 0.27, 0.05, Vector3(0, 0.025, 0), Color.WHITE, false, metal)
## 街边分类垃圾桶：【Kenney City Kit Roads】dumpster。
## 【尺度】原版是大号市政桶（约 1.2m），这里归一化到 0.85m —— 猫跳得上去，
## 又不像之前 0.52m 的圆柱那样「像个铁罐」。倒扣的桶盖 + 侧板加强筋是模型自带的。
## 成组摆放（位置哈希决定旁边是否再来一个），街边垃圾桶从来不是孤零零一个。
func _b_trash() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/dumpster.glb", 0.85, Vector3.ZERO, ry + PI)
	if _var_seed(position + Vector3(3, 0, 7)) > 0.55:
		_glb_h("kenney/dumpster.glb", 0.85, Vector3(0.95, 0, 0.1), ry + PI + 1.3)
func _b_bicycle() -> void:
	# 【Poly Pizza / Poly by Google,CC-BY】带车把、车筐、辐条、车座的完整自行车。
	# 手搭版(torus 轮 + 方盒车架)远看就是两个圆圈扛着几根棍。
	# 归一化到 1.0m(带车把的真实停车高度),车头朝向按位置哈希随机。
	var ry := _var_seed(position) * TAU
	_glb_h("polypizza/bicycle.glb", 1.0, Vector3.ZERO, ry)


func _b_car() -> void:
	# 【Kenney Car Kit / CC0】原来这台车是 1 个车身方盒 + 1 个玻璃方盒 + 4 个圆柱轮子，
	# 停在街边一眼就是「积木」。Kenney 的车有引擎盖/车窗/保险杠/后视镜的层次。
	# 归一化到 1.45m 高（对齐 META 的 solid 高度，碰撞体不用动）。
	# 车头沿街（沿 +X / -X 停），随机左右 + 一点角度歪
	# 不染色：Kenney 的 colormap 贴图自带车漆色，乘色反而会脏。
	# 车型按位置哈希轮换，一整条街不会全是同一台车。
	var kinds := ["sedan.glb", "hatchback-sports.glb", "suv.glb", "van.glb"]
	var h := _var_seed(position)
	var rel: String = kinds[int(h * 313.0) % kinds.size()]
	var ry := (0.0 if int(h * 97.0) % 2 == 0 else PI) + (h - 0.5) * 0.16
	_glb_h("kenney/" + rel, 1.45, Vector3.ZERO, ry)


func _b_traffic() -> void:
	# 金属杆(metal 0.85) + 三色信号灯(UNSHADED 自发光，Bloom 会捕获)
	var dark := m_metal_dark(position)
	cyl(0.08, 0.11, 4.5, Vector3(0, 2.25, 0), Color.WHITE, false, dark)
	box(Vector3(0.14, 0.14, 2.6), Vector3(0, 5.35, 1.3), Color.WHITE, 0,0,0, dark)
	box(Vector3(0.42, 1.15, 0.5), Vector3(0, 5.1, 2.45), Color.WHITE, 0,0,0, m_metal_cool(position))
	# 红(停) 黄(待) 绿(行)：只点亮当前相位，夜景里是街道的节奏点
	box(Vector3(0.34, 0.32, 0.1), Vector3(0, 5.1, 2.72), Color.WHITE, 0,0,0, m_glow(Color(0.95, 0.22, 0.18), 3.0))
	box(Vector3(0.34, 0.32, 0.1), Vector3(0, 5.42, 2.72), Color.WHITE, 0,0,0, m_glow(Color(0.95, 0.75, 0.2), 0.5))
	box(Vector3(0.34, 0.32, 0.1), Vector3(0, 4.78, 2.72), Color.WHITE, 0,0,0, m_glow(Color(0.3, 0.95, 0.4), 0.5))
	box(Vector3(0.45, 1.2, 0.4), Vector3(0, 5.1, 0), Color.WHITE, 0,0,0, dark)
	box(Vector3(0.3, 0.3, 0.3), Vector3(0, 0.15, 0), Color.WHITE, 0,0,0, m_rubber(position))
func _b_signboard() -> void:
	box(Vector3(0.15, 1.5, 0.15), Vector3(0, 0.75, 0), Color("6b5d4a"))
	box(Vector3(0.95, 1.7, 0.12), Vector3(0, 2.2, 0), Color("f2e6cf"), 0.0, 0.0, 0.0,
		tex_mat(ProceduralTex.wood(23), Color("f2e6cf"), 1.2, 0.9, "sb"))
	box(Vector3(1.06, 0.1, 0.2), Vector3(0, 3.08, 0), Color("6b5d4a"))
	text3d("営\n業\n中", 78, Vector3(0, 2.2, 0.09), Color("2b2b33"))
	box(Vector3(0.95, 0.12, 0.14), Vector3(0, 1.42, 0), Color("b5484d"))


func _b_streetlight() -> void:
	# 金属杆 + 暖白灯箱。灯箱是 UNSHADED 自发光，Bloom 会捕获 → 夜里街道的锚点
	var dark := m_metal_dark(position)
	cyl(0.07, 0.1, 4.2, Vector3(0, 2.1, 0), Color.WHITE, false, dark)
	box(Vector3(1.15, 0.09, 0.09), Vector3(0.48, 4.15, 0), Color.WHITE, 0,0,0, dark)
	# 灯罩：金属外壳
	box(Vector3(0.6, 0.16, 0.24), Vector3(1.0, 4.05, 0), Color.WHITE, 0,0,0, m_metal_galva(position))
	# 发光面（朝下，路面会被照亮 —— 配合 OmniLight 效果更真）
	box(Vector3(0.5, 0.05, 0.18), Vector3(1.0, 3.97, 0), Color.WHITE, 0,0,0, m_glow(Color(1.0, 0.85, 0.6), 3.2))
	box(Vector3(0.42, 0.32, 0.42), Vector3(0, 0.16, 0), Color.WHITE, 0,0,0, m_concrete(position))
## 长椅：【Kenney Holiday Kit】bench（条板座面 + 铸铁腿 + 靠背一体）。
## 【尺度】归一化到 0.45m —— 真人座高标准 0.42m，猫的跳跃极限 0.66m，两者都满足。
## 手搭版的「木块 + 4 根方腿」远看就是一条板凳，模型的靠背曲线和椅腿弯折
## 才是让长椅「像长椅」的关键。
func _b_bench() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/bench.glb", 0.45, Vector3.ZERO, ry + PI * 0.5)
func _b_busstop() -> void:
	var dark := m_metal_cool(position)
	cyl(0.05, 0.07, 2.7, Vector3(0, 1.35, 0), Color.WHITE, false, dark)
	# 站牌灯箱：蓝色自发光，夜晚是街边的一个光点
	box(Vector3(0.85, 0.85, 0.08), Vector3(0, 2.45, 0), Color.WHITE, 0,0,0, m_glow(Color(0.25, 0.5, 0.8), 2.0))
	box(Vector3(0.45, 0.24, 0.03), Vector3(0, 2.56, 0.06), Color.WHITE, 0,0,0, m_plastic_white(position))
	box(Vector3(0.1, 0.1, 0.03), Vector3(-0.12, 2.42, 0.06), Color(0.1,0.2,0.4), 0,0,0, m_rubber(position))
	box(Vector3(0.1, 0.1, 0.03), Vector3(0.12, 2.42, 0.06), Color(0.1,0.2,0.4), 0,0,0, m_rubber(position))
	text3d("バス", 52, Vector3(0, 2.16, 0.06), Color.WHITE)
	# 时刻表：纸张质感
	box(Vector3(0.5, 0.65, 0.04), Vector3(0, 1.45, 0.06), Color.WHITE, 0,0,0, m_paper(position))
	for i in 4:
		box(Vector3(0.36, 0.04, 0.05), Vector3(0, 1.62 - i * 0.13, 0.07), Color(0.35,0.33,0.3), 0,0,0, m_plastic_white(position))
func _b_tree() -> void:
	# 【art-assets 树冠 + 程序化树干】tree-leaves_0..4 是原网页游戏的大树冠
	# （原调色映射在网页层拿不到 → tint 绿），配微锥圆柱树干，比 Kenney 球堆树冠自然。
	# _var_seed ∈ ±0.45：+0.5 归一到 [0.05,0.95) 再当 [0,1) 用。
	var variants := ["tree-leaves_0", "tree-leaves_1", "tree-leaves_2", "tree-leaves_3", "tree-leaves_4"]
	var h := _var_seed(position) + 0.5
	var rel := "res://assets/art/env/planets_present_%s.glb" % variants[int(h * 4.999)]
	# 树干：微锥圆柱，深棕
	var trunk_h := 1.4 + h * 0.6
	cyl(0.14 + h * 0.06, 0.22 + h * 0.06, trunk_h, Vector3(0, trunk_h * 0.5, 0), Color("6b4f3a"))
	# 树冠：归一化到目标高度，抬到树干上部（树冠底叶会自然遮住接口）
	var crown_h := 2.4 + h * 1.2
	var tint := Color("8fbf6a").lerp(Color("5f9e52"), h)
	_glb_h(rel, crown_h, Vector3(0, trunk_h * 0.72, 0), h * TAU, {"*": tint})
	if h > 0.78:
		# 两成的树冠上停一小群鸟（birds_1 一小群 / birds_2 两三只）
		var brel := "res://assets/art/env/birds_2.glb" if h > 0.9 else "res://assets/art/env/birds_1.glb"
		_glb_h(brel, 0.34, Vector3(0.15, crown_h * 0.62, 0.1), h * TAU)


func _b_sakura() -> void:
	# 【art-assets 树冠 + 粉染】原网页游戏的树冠面片染樱粉，比手搭粉球树耐看。
	var h := _var_seed(position + Vector3(1, 0, 9)) + 0.5
	var variants := ["tree-leaves_0", "tree-leaves_1", "tree-leaves_2", "tree-leaves_3", "tree-leaves_4"]
	var rel := "res://assets/art/env/planets_present_%s.glb" % variants[int(h * 4.999)]
	var trunk_h := 1.5 + h * 0.5
	cyl(0.13 + h * 0.05, 0.2 + h * 0.05, trunk_h, Vector3(0, trunk_h * 0.5, 0), Color("5c4436"))
	var crown_h := 2.6 + h * 1.0
	var pinks := [Color("f2a8c4"), Color("f7bfd2"), Color("e894b4")]
	var pink: Color = pinks[int(h * 997.0) % pinks.size()]
	_glb_h(rel, crown_h, Vector3(0, trunk_h * 0.72, 0), h * TAU, {"*": pink})
	# 落樱的地面圆盘：淡粉半透明
	var disc := cyl(1.3, 1.3, 0.012, Vector3(0.3, 0.085, 0.3), Color.WHITE, false, m_petal())
	disc.scale = Vector3(1.0, 1.0, 0.8)


func _b_flower() -> void:
	# Kenney 的花是三片交叉面片，一丛 3~5 株才有「花丛」的感觉
	var kinds := ["flower_redA", "flower_yellowA", "flower_purpleA"]
	var h := _var_seed(position)
	for i in 3:
		var rel := "kenney/%s.glb" % kinds[int(h * 31.0 + i * 7.0) % kinds.size()]
		var ox := -0.28 + i * 0.28
		var oz := float((i * 5) % 3 - 1) * 0.22
		_glb(rel, Vector3(ox, 0, oz), 1.5 + h * 0.8, h * TAU + i * 1.7)


func _b_grass() -> void:
	var h := _var_seed(position)
	for i in 4:
		var ox := -0.3 + i * 0.2
		_glb("kenney/grass.glb", Vector3(ox, 0, float((i * 7) % 3 - 1) * 0.16),
			1.6 + h * 1.0, h * TAU + i * 1.3)
	if h > 0.6:
		_glb("kenney/plant_bushSmall.glb", Vector3(0.1, 0, 0.1), 1.8, h * 2.0)


func _b_parksign() -> void:
	box(Vector3(0.12, 1.6, 0.12), Vector3(0, 0.8, 0), Color("6b5d4a"))
	box(Vector3(1.4, 0.8, 0.07), Vector3(0, 1.98, 0), Color("5e7d4a"))
	box(Vector3(1.28, 0.68, 0.08), Vector3(0, 1.98, 0.01), Color("f2e6cf"))
	text3d("公園", 120, Vector3(0, 1.98, 0.08), Color("2b2b33"))
	sph(0.15, Vector3(0, 2.56, 0), Color("7fb069"))
	box(Vector3(0.05, 0.16, 0.05), Vector3(0, 2.4, 0), Color("6b4f3a"))


func _b_dog() -> void:
	# 【Quaternius Ultimate Animated Animal Pack / CC0】自带 12 条动画
	# （Idle / Walk / Gallop / Jump / Eating / Attack…），狗会自己甩尾踱步。
	# 归一化到 0.52m 肩高 —— 大型犬只在这个尺寸里才像「街边小狗」而不是「马」。
	var rel := "animals/dog.gltf"
	if not ResourceLoader.exists(MODEL_ROOT + rel):
		rel = "quaternius/ShibaInu.gltf"
	var n := _glb_h(rel, 0.52, Vector3.ZERO, _var_seed(position) * TAU)
	if n == null:
		return
	var ap := ModelUtil.find_anim(n, ["idle"])
	var a := ModelUtil.pick_anim(ap, ["idle", "walk"])
	if ap != null and a != "":
		ap.play(a)


func _b_cat() -> void:
	# 街头的猫用玩家猫那套外观（CatAvatar），这样玩家和 NPC 是同一个「角色资产」，
	# 以后换模型只改一个地方。缩到 0.9 并转向街边，背对镜头蹲着。
	var av := CatAvatar.new()
	av.scale = Vector3.ONE * 0.9
	av.position = Vector3(0, 0.0, 0)
	add_child(av)
	av.rotation.y = PI * 0.5 + _var_seed(position)
	av.animate(0.0, 0.0, 0.0)
	av.set_idle_only(true)


func _b_bird() -> void:
	# 【art-assets 鸟 + Poly Pizza 混用】birds_1（一小群）/ birds_2（两三只）
	# / sparrow（单只）三选一，地上啄食的鸟群更有街道生气。
	var ry := _var_seed(position) * TAU
	var h := _var_seed(position + Vector3(3, 7, 11)) + 0.5
	if h < 0.35:
		_glb_h("res://assets/art/env/birds_1.glb", 0.3, Vector3.ZERO, ry)
	elif h < 0.7:
		_glb_h("res://assets/art/env/birds_2.glb", 0.24, Vector3.ZERO, ry)
	else:
		_glb_h("polypizza/sparrow.glb", 0.22, Vector3.ZERO, ry)


func _b_delivery() -> void:
	# 【art-assets deliveries】投递物道具：map.json 用 {"kind":"delivery","model":"<名>"} 选型，
	# 可选 "h" 指定归一化高度（米）。model 取 deliveries_<名>.glb。
	var m := String(extra.get("model", "postcard"))
	_glb_h("res://assets/art/env/deliveries_%s.glb" % m,
		float(extra.get("h", 0.35)), Vector3.ZERO, _var_seed(position) * TAU)


func _b_npc() -> void:
	# 美术包角色（.drc 转换的 glb，见 tools/art_convert）：任务发布者。
	# map.json 条目 {"kind":"npc","npc":"<npc_id>"}；目录/身高/显示名在 data/npcs.json。
	# 面向：模型原朝向未知，先背对镜头（PI）+ 随机微转（_var_seed ±0.45），Godot 里看了再统一调。
	var npc := ArtNpc.new()
	npc.npc_id = String(extra.get("npc", ""))
	add_child(npc)
	npc.rotation.y = PI + _var_seed(position) * 2.0


func _b_bowl() -> void:
	# 【Kenney Food Kit / CC0】bowl-broth 自带汤面 + 碗沿层次,
	# 手搭版(圆柱碗 + 圆环沿 + 两颗球)远看就是一摞圆盘。
	_glb_h("kenney/bowl-broth.glb", 0.3, Vector3.ZERO, _var_seed(position) * TAU)


func _b_cans() -> void:
	# 【Kenney Food Kit / CC0】can-open 自带拉环 + 顶盖凹陷。
	# 一罐立着、两罐倒下,空罐才有的散乱感。
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/can-open.glb", 0.18, Vector3(-0.2, 0, 0.05), ry)
	var t1 := _glb_h("kenney/can-open.glb", 0.18, Vector3(0.12, 0.06, -0.08), ry + 1.4)
	if t1 != null:
		t1.rotation.z = PI * 0.5
	var t2 := _glb_h("kenney/can-open.glb", 0.18, Vector3(0.3, 0.06, 0.12), ry + 2.3)
	if t2 != null:
		t2.rotation.z = PI * 0.5
		t2.rotation.x = 0.12


func _b_onigiri() -> void:
	# 【Kenney Food Kit / CC0】rice-ball 自带海苔贴片三角饭团。
	_glb_h("kenney/rice-ball.glb", 0.28, Vector3.ZERO, _var_seed(position) * TAU)


func _b_bread() -> void:
	box(Vector3(1.35, 0.4, 0.75), Vector3(0, 0.2, 0), Color("a8794e"), 0.0, 0.0, 0.0,
		tex_mat(ProceduralTex.wood(29), Color("a8794e"), 1.1, 0.9, "cr"))
	box(Vector3(1.37, 0.06, 0.77), Vector3(0, 0.42, 0), Color("8f6540"))
	for i in 3:
		var b := sph(0.17, Vector3(-0.42 + i * 0.42, 0.56, 0), Color("e6b84c"))
		b.scale = Vector3(1.0, 0.62, 0.75)


func _b_door() -> void:
	var col := Color("8b5e3c")
	var host := String(extra.get("host", ""))
	if host == "konbini":
		col = Color("9fc2d6")
	elif host == "mansion":
		col = Color("6b5d4a")
	box(Vector3(1.05, 2.2, 0.1), Vector3(0, 1.1, 0), col, 0.0, 0.0, 0.0, glass_mat(col.lightened(0.1)))
	box(Vector3(0.05, 2.2, 0.12), Vector3(0, 1.1, 0), Color(0.9, 0.9, 0.88, 0.6))
	sph(0.045, Vector3(0.38, 1.05, 0.08), Color("d8d2c4"))
	box(Vector3(1.2, 0.09, 0.18), Vector3(0, 2.26, 0), Color(0.25, 0.22, 0.2, 0.9))


func _b_window() -> void:
	_window_unit(1.15, 1.15, Vector3(0, _door_dy if _door_dy > 0 else 1.95, 0))


func _b_crosswalk() -> void:
	var dir := String(extra.get("dir", "v"))
	for i in 7:
		var off := -2.7 + i * 0.9
		if dir == "v":
			box(Vector3(0.5, 0.03, 2.9), Vector3(off, 0.075, 0), Color(1, 1, 1, 0.9))
		else:
			box(Vector3(2.9, 0.03, 0.5), Vector3(0, 0.075, off), Color(1, 1, 1, 0.9))


# ================================================================
# 批次 5 前置：专为「猫能跳上去」设计的矮物件
# 尺度基准：猫跳高 0.66m，所以台面全部 ≤ 0.5m。
# 这些是 Stray 里「猫在城市里钻来钻去」的主要落脚点。
# ================================================================

## 街边窨井盖（水泥井盖）：0.38m 高的凸台。Stray 里猫最爱跳的东西之一。
## 【坑】CylinderMesh 是开口的，横放时能直接看进内壁 → 变成一个黑洞。
## 做法：竖放 + 顶盖盖住口 + 井盖花纹。做实心的最稳。
func _b_pipe() -> void:
	var conc := m_concrete(position)
	var dark := m_metal_dark(position)
	# 井壁（竖放圆筒，不用 axis_z）
	cyl(0.3, 0.32, 0.34, Vector3(0, 0.17, 0), Color.WHITE, false, conc)
	# 井盖（顶面，猫踩这里）—— 略微凸出 + 深色金属
	cyl(0.31, 0.31, 0.06, Vector3(0, 0.35, 0), Color.WHITE, false, dark)
	# 盖面花纹（十字筋，让井盖一眼可认）
	for a in [0.0, PI * 0.5]:
		box(Vector3(0.52, 0.025, 0.05), Vector3(0, 0.385, 0), Color(0.16, 0.16, 0.17), a, 0, 0)
	# 提手小孔
	_sph2(0.035, Vector3(0, 0.39, 0), Color(0.1, 0.1, 0.11))
	# 井壁竖向裂纹（打破水泥的平整感）
	for i in 3:
		var an := float(i) * 2.1
		box(Vector3(0.02, 0.2, 0.02), Vector3(cos(an) * 0.3, 0.16, sin(an) * 0.3),
			Color(0.56, 0.54, 0.5), an, 0, 0)


## 纯色球（不接材质工厂的简版，用于小装饰）
func _sph2(r: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	mi.mesh = mesh
	mi.material_override = mat(color, r * 2.0)
	mi.position = pos
	add_child(mi)
	return mi


## 店铺门口的塑料周转箱：0.4m。猫跳上去可以俯瞰街面。
func _b_crate() -> void:
	# 三种颜色随机，跟街道色调协调（不是纯蓝塑料）
	var cols := [Color(0.42, 0.5, 0.56), Color(0.56, 0.44, 0.36), Color(0.4, 0.52, 0.44)]
	var c: Color = cols[int(abs(position.x * 7.3 + position.z * 3.1)) % 3]
	var m := _mat_j("crate", c, position, 0.5, 0.0, 0.07)
	# 箱体（略微收口，像真的周转箱）
	box(Vector3(0.72, 0.34, 0.58), Vector3(0, 0.17, 0), Color.WHITE, 0,0,0, m)
	box(Vector3(0.68, 0.06, 0.54), Vector3(0, 0.36, 0), Color.WHITE, 0,0,0, m)
	# 边缘加强筋
	for ex in [-0.34, 0.34]:
		box(Vector3(0.05, 0.3, 0.6), Vector3(ex, 0.17, 0), Color.WHITE, 0,0,0, m)
	# 里面露一点东西（空箱子太假）
	box(Vector3(0.4, 0.1, 0.3), Vector3(0.05, 0.33, 0.05), Color(0.7, 0.68, 0.6), 0,0,0.3, m)


## 花坛矮沿（公园/店铺前）：【Kenney City Kit Suburban】planter 自带池壁 + 泥土 +
## 植株，0.5m 沿口高度不变。手搭版的四面墙 + 单独一排「草杆」远看是一块空水泥台。
func _b_planter() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/planter.glb", 0.5, Vector3.ZERO, ry)
	# 位置哈希决定边上再插一株灌木，让花坛不至于千篇一律
	if _var_seed(position + Vector3(7, 0, 3)) > 0.45:
		_glb_h("kenney/plant_bushSmall.glb", 0.34, Vector3(0.86, 0.06, 0.28), ry + 1.7)


## 巷口矮墙：0.55m。猫能跳上去看过去，Stray 里爬墙是标志性动作。
func _b_lowwall() -> void:
	var conc := m_concrete(position)
	# 墙帽（顶面比墙体略宽，猫踩着有 overhang 的感觉）
	box(Vector3(2.3, 0.1, 0.4), Vector3(0, 0.5, 0), Color(0.66, 0.64, 0.6), 0,0,0, conc)
	# 墙体
	box(Vector3(2.2, 0.45, 0.32), Vector3(0, 0.225, 0), Color(0.72, 0.7, 0.66), 0,0,0, conc)
	# 压顶纹（横向凹槽，让大面积水泥不那么平）
	for i in 3:
		box(Vector3(2.24, 0.02, 0.34), Vector3(0, 0.12 + i * 0.13, 0), Color(0.64, 0.62, 0.58), 0,0,0, conc)


# ================================================================
# 批次 6：家具（家具屋门口的沿街展示品）
# 尺度沿用批次 5 的铁律：能跳的台面 ≤ 0.5m（桌子 0.45 / 椅子 0.44 /
# 沙发座 0.45 / 床台 0.33），柜子电视这种高的保持实心不可跳。
# ================================================================

## 家具屋：木色门脸 + 橱窗里透出店内家具的剪影
func _b_furniture() -> void:
	_shop_front(7.0, Color("e8dcc4"))
	box(Vector3(7.0, 1.0, 0.3), Vector3(0, 3.9, 2.6), Color("8b5e3c"))
	text3d("家具屋", 130, Vector3(0, 3.9, 2.78), Color("f2e6cf"))
	var awn := box(Vector3(6.8, 0.1, 1.5), Vector3(0, 3.15, 3.1), Color("8b5e3c"))
	awn.rotation = Vector3(-0.26, 0, 0)
	box(Vector3(6.8, 0.07, 0.2), Vector3(0, 2.9, 3.8), Color.WHITE)
	# 店内剪影：透过橱窗能看见本棚 + 桌子，暗示「这里面卖家具」
	var in_wood := tex_mat(ProceduralTex.wood(43), Color(0.55, 0.4, 0.28), 1.1, 0.9, "fw")
	box(Vector3(1.3, 1.4, 0.5), Vector3(-2.2, 0.7, 1.4), Color.WHITE, 0,0,0, in_wood)
	for i in 3:
		box(Vector3(1.16, 0.035, 0.44), Vector3(-2.2, 0.35 + i * 0.42, 1.4), Color.WHITE, 0,0,0, in_wood)
		for b in 4:
			box(Vector3(0.08, 0.24, 0.26), Vector3(-2.6 + b * 0.2, 0.52 + i * 0.42, 1.42),
				Color.WHITE, 0,0,0, _mat_j("fib%d%d" % [i, b],
				[Color("c94f4f"), Color("4a6fa5"), Color("5e9c54"), Color("e6b84c")][(i + b) % 4],
				position + Vector3(i, b, 0), 0.85, 0.0, 0.1))
	box(Vector3(1.1, 0.05, 0.7), Vector3(2.1, 0.43, 1.4), Color.WHITE, 0,0,0, in_wood)
	for lx in [-0.45, 0.45]:
		for lz in [-0.25, 0.25]:
			box(Vector3(0.06, 0.41, 0.06), Vector3(2.1 + lx, 0.21, 1.4 + lz), Color.WHITE, 0,0,0, in_wood)


## 木桌：0.45m 台面（猫可跳），四条腿留出可以钻的桌底
## 【Kenney Furniture Kit / CC0】手搭的方盒桌在近景里就是四根柱子一块板。
## 归一化到 0.45m 台面高 —— 正好卡在 META 的 stand 数值上，碰撞体不用动。
func _b_table() -> void:
	_glb_h("kenney/tableRound.glb", 0.45, Vector3.ZERO, _var_seed(position) * TAU, TINT_WOOD)


## 木椅：座面 0.44m + 靠背，四条腿
func _b_chair() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/chair.glb", 0.9, Vector3.ZERO, ry, TINT_WOOD)
	# 坐垫：给猫一个更愿意趴的平面，也让木椅不至于太硬
	_glb_h("kenney/chairCushion.glb", 0.5, Vector3(0, 0.44, 0.02), ry)


## 和式矮床：木台 + 布団 + 枕头 —— 猫最爱卧的那种
func _b_bed() -> void:
	var ry := _var_seed(position) * 0.6 - 0.3
	_glb_h("kenney/bedSingle.glb", 0.42, Vector3.ZERO, ry, TINT_WOOD)
	_glb_h("kenney/pillow.glb", 0.16, Vector3(0.62, 0.4, -0.28), ry + 0.2, TINT_FABRIC)
	_glb_h("kenney/rugRectangle.glb", 0.02, Vector3(1.1, 0.005, 0.5), ry)


## 布艺沙发：灰绿底座 + 靠背扶手 + 米色坐垫
func _b_sofa() -> void:
	_glb_h("kenney/loungeSofa.glb", 0.72, Vector3.ZERO, PI * 0.5 + _var_seed(position) * 0.4,
		TINT_FABRIC)


## 电视机：木电视柜 + 深色屏（玻璃反射天空）
func _b_tv() -> void:
	var ry := _var_seed(position) * 0.5 - 0.25
	_glb_h("kenney/cabinetTelevision.glb", 0.5, Vector3.ZERO, ry, TINT_WOOD)
	_glb_h("kenney/televisionModern.glb", 0.62, Vector3(0, 0.5, 0.02), ry)


## 本棚：四层隔板 + 彩色书脊
func _b_shelf() -> void:
	_glb_h("kenney/bookcaseOpen.glb", 1.5, Vector3.ZERO, PI + _var_seed(position) * 0.3, TINT_WOOD)
	# 书：按位置哈希塞几排，空书架太干净
	var h := _var_seed(position)
	for i in 3:
		if fmod(h * 7.0 + float(i) * 3.0, 2.0) < 0.6:
			continue
		_glb_h("kenney/books.glb", 0.24, Vector3(-0.1 + i * 0.06, 0.34 + i * 0.42, 0.06),
			h * 2.0 + i * 0.4)


## 落地灯：金属杆 + 米色和纸灯罩（m_paper 的 emission 由 TimeOfDay 点亮，白天不发假光）
func _b_lamp() -> void:
	_glb_h("kenney/lampRoundFloor.glb", 1.5, Vector3.ZERO, _var_seed(position) * TAU)


## 洗濯機：日本人家门口的标配。白机身 + 圆窗 + 控制面板
## 换 Kenney 的 washer：圆窗、面板、脚座都是现成的，比方盒上贴两个圆柱像洗衣机得多
func _b_wash() -> void:
	_glb_h("kenney/washer.glb", 0.9, Vector3.ZERO, PI + _var_seed(position) * 0.6)


# ================================================================
# 批次 7：街景杂物
# 定位：不参与学词的「生活痕迹」道具。日式街道的质感一半靠这些
# 零碎：消火栓、盆栽、晾衣杆、垃圾袋、旧轮胎、路锥、燃气罐、水洼。
# 矮件台面全部 ≤ 0.66m（猫的跳跃极限），沿袭批次 5 铁律。
# ================================================================

## 道路標識：灰色杆 + 板面。修复 map.json 里 roadsign 无 META 的隐形 bug。
## 两种板面（止まれ 红色 / 一方通行 蓝色）按位置哈希交替。
## 道路標識：【Kenney City Kit Roads】三款按位置哈希轮换（街名牌 / 止まれ /
## 警告牌）。手搭版用 Label3D 贴「止まれ」，近距离看字是贴图糊的；Kenney 的牌面
## 是真几何 + 原生 CC0 图文，远看轮廓也更接近现实路牌。
## 高度 2.4m 不变（猫爬电线杆那一段的尺度参照）。
func _b_roadsign() -> void:
	var ry := _var_seed(position) * TAU
	var pick := int(abs(position.x * 13.7 + position.z * 5.1)) % 3
	var rel := "kenney/roadsign_stop.glb"
	if pick == 1:
		rel = "kenney/roadsign_street.glb"
	elif pick == 2:
		rel = "kenney/roadsign_warning.glb"
	_glb_h(rel, 2.4, Vector3.ZERO, ry)


## 消火栓（柱形）：0.62m，猫可跳。
## 【Poly Pizza,CC0】firehydrant 自带侧出水口盖 + 顶盖链条造型,
## 手搭版(圆柱堆)远看就是一根红柱子,完全认不出是消火栓。
func _b_fireplug() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("polypizza/fire_hydrant.glb", 0.62, Vector3.ZERO, ry)


## 鉢植え：陶盆 + 土面 + 两种植物（灌木 / 开花）按位置哈希。
func _b_potplant() -> void:
	# 【Kenney Furniture Kit】原来的「陶盆 + 两团圆球」远看就是一团绿疙瘩。
	# pottedPlant 自带盆 + 土 + 植株，0.45m 台面高度不变。
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/pottedPlant.glb", 0.62, Vector3.ZERO, ry)
	# 高的那盆：多摆一株小盆栽，门口才不会只有一盆
	if _var_seed(position + Vector3(3, 0, 1)) > 0.5:
		_glb_h("kenney/plantSmall1.glb", 0.34, Vector3(0.42, 0, 0.16), ry + 1.2)


## 物干し竿：两根镀锌 T 杆 + 3 条下垂电线 + 4 条毛巾 + 1 张床单。
## solid = null：杆太细不值得碰撞，布是布（猫穿过去也算钻晾衣杆）。
func _b_laundry() -> void:
	var pole_m := m_metal_galva(position)
	for px in [-1.15, 1.15]:
		cyl(0.03, 0.042, 1.9, Vector3(px, 0.95, 0), Color.WHITE, false, pole_m)
		box(Vector3(0.52, 0.045, 0.045), Vector3(px, 1.87, 0), Color.WHITE, 0, 0, 0, pole_m)
	for lz in [-0.14, 0.0, 0.14]:
		_wire(self, Vector3(-1.15, 1.85, lz), Vector3(1.15, 1.85, lz), 0.008, Color("3a3d44"))
	# 毛巾：四种颜色，微差明度
	var tcols := [Color("e8e2d4"), Color("9fc2d6"), Color("e6b84c"), Color("d97fb0")]
	for i in 4:
		var tx := -0.75 + i * 0.5
		box(Vector3(0.4, 0.5, 0.02), Vector3(tx, 1.58, 0.0), Color.WHITE, 0, 0, 0,
			_mat_j("towel%d" % i, tcols[i], position + Vector3(i, 0, 0), 0.9, 0.0, 0.07))
	# 床单：更大更白，挂中间偏后
	box(Vector3(0.62, 0.72, 0.02), Vector3(-0.35, 1.47, 0.12), Color.WHITE, 0, 0, 0,
		_mat_j("sheet", Color(0.94, 0.94, 0.96), position + Vector3(5, 0, 0), 0.92, 0.0, 0.04))


## ゴミ袋：半透明乙烯基袋（清晨收垃圾堆在路边）。
## 材质要带一点 alpha（0.9）+ 低 roughness，才有「塑料袋反光」的感觉。
func _b_trashbags() -> void:
	if not _mats.has("gbag"):
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.87, 0.89, 0.92, 0.9)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.roughness = 0.28
		bm.metallic = 0.05
		bm.metallic_specular = 0.6
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_mats["gbag"] = bm
	if not _mats.has("gbag_b"):
		var bb := StandardMaterial3D.new()
		bb.albedo_color = Color(0.55, 0.68, 0.8, 0.9)
		bb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bb.roughness = 0.28
		bb.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_mats["gbag_b"] = bb
	var bag_m: StandardMaterial3D = _mats["gbag"]
	var bag_b: StandardMaterial3D = _mats["gbag_b"]
	# 大袋 + 小袋 + 蓝袋，扁球形（装满垃圾的下坠感）
	var b1 := sph(0.28, Vector3(-0.2, 0.22, 0.05), Color.WHITE, bag_m)
	b1.scale = Vector3(1.0, 0.75, 0.95)
	var b2 := sph(0.22, Vector3(0.16, 0.17, -0.1), Color.WHITE, bag_m)
	b2.scale = Vector3(1.0, 0.72, 1.0)
	var b3 := sph(0.24, Vector3(0.1, 0.19, 0.22), Color.WHITE, bag_b)
	b3.scale = Vector3(1.0, 0.75, 0.9)
	# 扎口：袋顶一小节深色结
	cyl(0.05, 0.07, 0.09, Vector3(-0.2, 0.46, 0.05), Color.WHITE, false, m_rubber(position))
	cyl(0.045, 0.06, 0.08, Vector3(0.16, 0.35, -0.1), Color.WHITE, false, m_rubber(position))


## 旧轮胎堆：店后巷/修车铺门口。三层 torus 叠放，0.51m 可跳。
func _b_tires() -> void:
	var rubber := m_rubber(position)
	for i in 3:
		# 每层稍微错位 + 微倾，堆过的轮胎不会齐得像烤架
		var t := torus(0.26, 0.37, Vector3(0.02 * (i - 1), 0.09 + i * 0.17, -0.01 * i), Color.WHITE, false, rubber)
		t.rotation = Vector3(0.03 * (i % 2 - 1), float(i) * 0.7, 0.02 * i)
	# 顶上放一盆野草（久置的轮胎会长草——生活痕迹）
	cyl(0.1, 0.13, 0.09, Vector3(0.02, 0.55, -0.01), Color.WHITE, false, _mat_j("tpot", Color(0.4, 0.36, 0.3), position, 0.85, 0.0, 0.1))
	sph(0.12, Vector3(0.02, 0.66, -0.01), Color.WHITE, m_foliage(position + Vector3(1, 0, 0)))


## 工事コーン：【Kenney City Kit Roads】construction-cone 自带橙身 + 白反光圈，
## 手搭版的「圆锥 + 单独 torus 反光圈」远看只是一个橙三角，连不成「施工道具」。
## 两个锥按位置哈希错开摆放，保持「不挡路」的施工边缘语义。
func _b_cones() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/construction_cone.glb", 0.48, Vector3(-0.25, 0, 0.0), ry + 0.4)
	_glb_h("kenney/construction_cone.glb", 0.48, Vector3(0.3, 0, 0.12), ry + 2.1)


## ガスボンベ：饮食店后面靠墙的液化气罐 ×3。
## 【Poly Pizza,CC0】PropaneTank 自带罐身收肩 + 顶阀 + 提手,
## 手搭版(两根圆柱 + 方箍)被看成「油桶」——收肩和阀才是「煤气罐」的识别特征。
func _b_gasbottle() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("polypizza/propane_tank.glb", 0.7, Vector3(-0.26, 0, -0.12), ry + 0.3)
	_glb_h("polypizza/propane_tank.glb", 0.7, Vector3(0.26, 0, -0.06), ry + 1.1)
	_glb_h("polypizza/propane_tank.glb", 0.7, Vector3(0.0, 0, 0.16), ry + 2.2)


## 水洼：路面的一层薄水膜。
## 【Messenger 视觉】改走 ToonKit.water —— 移植自 Messenger 的 waterFragmentShader：
## 噪声推着一条白色浪花带在水面世界坐标上滚动，切成硬边色块；
## 浪花只在靠边处出现，中心是干净的平涂水面。
## 原来的做法是 roughness 0.06 + metallic 0.4 的 PBR 反光片 ——
## 在 Messenger 的无高光体系里那会变成一块突兀的镜子。
func _b_puddle() -> void:
	if not _mats.has("puddle"):
		_mats["puddle"] = ToonKit.water(Color(0.3, 0.38, 0.46, 0.62))
	var h := int(abs(position.x * 3.3 + position.z * 9.7)) % 1000
	var s := 0.9 + float(h % 40) / 40.0 * 1.1   # 0.9~2.0m
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(s, s * (0.55 + float(h % 20) / 20.0 * 0.3))
	mi.mesh = quad
	mi.material_override = _mats["puddle"]
	mi.rotation = Vector3(-PI * 0.5, 0, float(h) / 1000.0 * TAU)
	mi.position = Vector3(0, 0.078, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## 传送点：车站/路口的金属指路牌（双立柱 + 横梁 + 目的地名牌 + 地面箭头）。
## 走近由 street.gd 弹出【前往 ▸ 目的地】上下文按钮，按下走 Game.travel_to。
## extra：label（目的地名）、accent（可选强调色，用来区分不同街区）。
func _b_portal() -> void:
	var label := String(extra.get("label", ""))
	var accent := Color(String(extra.get("accent", "#2b6cb0")))
	var post := m_metal_galva(position)
	# 双立柱 + 横梁（镀锌铁皮，和车站雨棚同一套材质语言）
	for px in [-1.0, 1.0]:
		cyl(0.055, 0.075, 3.0, Vector3(px, 1.5, 0), Color.WHITE, false, post)
	box(Vector3(2.3, 0.13, 0.13), Vector3(0, 2.98, 0), Color.WHITE, 0, 0, 0, post)
	# 名牌：底色 + 顶部白条 + 目的地名
	box(Vector3(2.3, 0.95, 0.1), Vector3(0, 2.35, 0), accent)
	box(Vector3(2.36, 0.06, 0.12), Vector3(0, 2.8, 0), Color("f2efe6"))
	if not label.is_empty():
		text3d(label, 116, Vector3(0, 2.32, 0.09), Color.WHITE)
	# 立柱上的小箭头（指向站牌），指示「从这里出发」
	for sx in [-1.0, 1.0]:
		box(Vector3(0.22, 0.22, 0.06), Vector3(sx, 1.75, 0.06), Color("f2efe6"), 0, 0, 0.785)
	# 地面：混凝土圆盘 + 发光箭头（自发光，夜里由 TimeOfDay 点亮）
	cyl(0.95, 0.95, 0.06, Vector3(0, 0.03, 0), Color.WHITE, false, m_concrete(position))
	var glow := m_glow(accent, 1.4)
	box(Vector3(0.36, 0.04, 0.9), Vector3(0, 0.08, -0.1), accent, 0, 0, 0, glow)
	box(Vector3(0.62, 0.04, 0.42), Vector3(0, 0.08, 0.22), accent, 0, 0, 0, glow)


# ================================================================
# 批次 8：可进入室内的家具
# 定位：house_basic / apartment / konbini_shop / super_market / cafe_hall /
#       ramen_counter / station_hall 模板里的道具（data/interiors.json）。
# 全部沿用低多边形 box/cyl/sph + 材质语义工厂；矮件台面 ≤ 0.66m（猫跳得上）。
# 高挂件（エアコン/絵画/駅名標）在 _b_xxx 里直接把网格建在高处，
# 点击盒高度由 META 的 click_y 指定（见 _ready）。
# ================================================================

## 冷蔵庫：白灰双门冰箱（冷冻室在上），镀铬竖把手 + 两枚冰箱贴。
func _b_fridge() -> void:
	var body := _mat_j("fridge", Color(0.9, 0.91, 0.92), position, 0.38, 0.05, 0.03)
	var dark := m_metal_dark(position)
	var chrome := m_metal_galva(position)
	box(Vector3(0.95, 1.85, 0.75), Vector3(0, 0.925, 0), Color.WHITE, 0, 0, 0, body)
	# 冷藏/冷冻分缝 + 门面板
	box(Vector3(0.97, 0.035, 0.76), Vector3(0, 1.28, 0), Color.WHITE, 0, 0, 0, dark)
	box(Vector3(0.94, 0.92, 0.03), Vector3(0, 0.72, 0.375), Color.WHITE, 0, 0, 0, body)
	box(Vector3(0.94, 0.5, 0.03), Vector3(0, 1.56, 0.375), Color.WHITE, 0, 0, 0, body)
	# 镀铬竖把手
	cyl(0.018, 0.018, 0.5, Vector3(0.28, 0.72, 0.41), Color.WHITE, false, chrome)
	cyl(0.018, 0.018, 0.34, Vector3(0.28, 1.56, 0.41), Color.WHITE, false, chrome)
	# 冰箱贴
	box(Vector3(0.09, 0.09, 0.02), Vector3(-0.24, 1.52, 0.4), Color("d64541"))
	box(Vector3(0.06, 0.06, 0.02), Vector3(-0.36, 1.36, 0.4), Color("e6b84c"))
	# 底部踢脚
	box(Vector3(0.95, 0.08, 0.75), Vector3(0, 0.04, 0), Color.WHITE, 0, 0, 0, dark)


## コンロ：厨房灶台（白柜体 + 不锈钢台面 + 2 个燃气灶眼 + 锅/煎锅）。
func _b_stove() -> void:
	var body := _mat_j("stove", Color(0.88, 0.89, 0.9), position, 0.4, 0.1, 0.04)
	var steel := m_metal_galva(position)
	var dark := m_metal_dark(position)
	box(Vector3(1.15, 0.8, 0.72), Vector3(0, 0.4, 0), Color.WHITE, 0, 0, 0, body)
	box(Vector3(1.2, 0.06, 0.75), Vector3(0, 0.84, 0), Color.WHITE, 0, 0, 0, steel)
	# 柜门缝 + 拉手
	box(Vector3(1.1, 0.02, 0.02), Vector3(0, 0.55, 0.37), Color.WHITE, 0, 0, 0, dark)
	box(Vector3(0.5, 0.03, 0.03), Vector3(0, 0.66, 0.38), Color.WHITE, 0, 0, 0, steel)
	# 2 个灶眼 + 十字炉架
	for bx in [-0.28, 0.28]:
		cyl(0.15, 0.15, 0.025, Vector3(bx, 0.885, 0), Color.WHITE, false, dark)
		box(Vector3(0.3, 0.02, 0.02), Vector3(bx, 0.9, 0), Color.WHITE, 0, 0, 0, dark)
		box(Vector3(0.02, 0.02, 0.3), Vector3(bx, 0.9, 0), Color.WHITE, 0, 0, 0, dark)
	# 旋钮
	for bx in [-0.4, 0.4]:
		cyl(0.03, 0.03, 0.04, Vector3(bx, 0.68, 0.38), Color.WHITE, true, dark)
	# 锅（左）+ 煎锅（右）
	cyl(0.11, 0.1, 0.13, Vector3(-0.28, 0.97, 0), Color.WHITE, false, steel)
	sph(0.025, Vector3(-0.28, 1.05, 0), Color.WHITE, dark)
	box(Vector3(0.26, 0.05, 0.26), Vector3(0.28, 0.93, 0), Color.WHITE, 0, 0, 0, dark)
	box(Vector3(0.2, 0.02, 0.04), Vector3(0.28, 0.93, 0.16), Color.WHITE, 0, 0, 0, dark)
	# 背板挡墙
	box(Vector3(1.15, 0.12, 0.04), Vector3(0, 0.9, -0.35), Color.WHITE, 0, 0, 0, body)


## 浴槽：白瓷浴缸（四壁 + 缸底 + 水面），缸沿 0.12m 圆边可跳。
func _b_bathtub() -> void:
	var porc := _mat_j("tub", Color(0.94, 0.95, 0.95), position, 0.32, 0.02, 0.02)
	var chrome := m_metal_galva(position)
	# 四壁 + 缸底（拼出能看见的内部空腔）
	box(Vector3(1.6, 0.1, 0.8), Vector3(0, 0.05, 0), Color.WHITE, 0, 0, 0, porc)
	box(Vector3(0.1, 0.62, 0.8), Vector3(-0.75, 0.31, 0), Color.WHITE, 0, 0, 0, porc)
	box(Vector3(0.1, 0.62, 0.8), Vector3(0.75, 0.31, 0), Color.WHITE, 0, 0, 0, porc)
	box(Vector3(1.6, 0.62, 0.1), Vector3(0, 0.31, -0.35), Color.WHITE, 0, 0, 0, porc)
	box(Vector3(1.6, 0.62, 0.1), Vector3(0, 0.31, 0.35), Color.WHITE, 0, 0, 0, porc)
	# 缸沿加厚（圆边感）
	box(Vector3(1.66, 0.05, 0.86), Vector3(0, 0.62, 0), Color.WHITE, 0, 0, 0, porc)
	# 半透明水面
	box(Vector3(1.4, 0.04, 0.62), Vector3(0, 0.5, 0), Color.WHITE, 0, 0, 0, glass_mat(Color("8fb8d8")))
	# 水龙头 + 淋浴头（靠 -x 端的墙侧）
	cyl(0.025, 0.025, 0.32, Vector3(-0.7, 0.8, 0), Color.WHITE, false, chrome)
	box(Vector3(0.24, 0.04, 0.04), Vector3(-0.59, 0.95, 0), Color.WHITE, 0, 0, 0, chrome)
	box(Vector3(0.03, 0.24, 0.03), Vector3(-0.7, 1.02, 0.12), Color.WHITE, 0, 0, 0, chrome)
	cyl(0.08, 0.02, 0.05, Vector3(-0.7, 1.14, 0.2), Color.WHITE, false, chrome)


## トイレ：便器（底座 + 便座 + 便盖）+ 水箱，座面 0.1m 薄台可跳。
func _b_toilet() -> void:
	var porc := _mat_j("wc", Color(0.95, 0.96, 0.96), position, 0.3, 0.02, 0.02)
	var seat_m := _mat_j("wc_seat", Color(0.9, 0.9, 0.88), position, 0.45, 0.0, 0.03)
	var chrome := m_metal_galva(position)
	# 底座 + 便盆口 + 便座 + 便盖
	box(Vector3(0.3, 0.34, 0.42), Vector3(0, 0.17, 0.03), Color.WHITE, 0, 0, 0, porc)
	cyl(0.19, 0.16, 0.08, Vector3(0, 0.38, 0.03), Color.WHITE, false, porc)
	cyl(0.2, 0.2, 0.05, Vector3(0, 0.435, 0.03), Color.WHITE, false, seat_m)
	cyl(0.2, 0.2, 0.035, Vector3(0, 0.475, -0.03), Color.WHITE, false, porc)
	# 水箱 + 水箱盖 + 冲水手柄
	box(Vector3(0.5, 0.4, 0.2), Vector3(0, 0.55, -0.26), Color.WHITE, 0, 0, 0, porc)
	box(Vector3(0.54, 0.05, 0.24), Vector3(0, 0.775, -0.26), Color.WHITE, 0, 0, 0, porc)
	box(Vector3(0.12, 0.03, 0.03), Vector3(0.2, 0.72, -0.15), Color.WHITE, 0, 0, 0, chrome)


## 戸棚：高身木柜（双门 + 圆形把手 + 顶冠），实心不可跳。
func _b_cupboard() -> void:
	var wood := _mat_j("cup", Color(0.72, 0.58, 0.42), position, 0.75, 0.0, 0.08)
	var dark := m_metal_dark(position)
	var steel := m_metal_galva(position)
	box(Vector3(1.1, 1.9, 0.64), Vector3(0, 0.95, 0), Color.WHITE, 0, 0, 0, wood)
	box(Vector3(1.16, 0.07, 0.7), Vector3(0, 1.965, 0), Color.WHITE, 0, 0, 0, wood)   # 顶冠
	box(Vector3(1.1, 0.06, 0.64), Vector3(0, 0.03, 0), Color.WHITE, 0, 0, 0, dark)   # 踢脚
	# 双门 + 门缝
	box(Vector3(0.52, 1.72, 0.03), Vector3(-0.27, 0.97, 0.33), Color.WHITE, 0, 0, 0, wood)
	box(Vector3(0.52, 1.72, 0.03), Vector3(0.27, 0.97, 0.33), Color.WHITE, 0, 0, 0, wood)
	box(Vector3(0.02, 1.72, 0.04), Vector3(0, 0.97, 0.34), Color.WHITE, 0, 0, 0, dark)
	# 把手
	sph(0.025, Vector3(-0.08, 1.0, 0.37), Color.WHITE, steel)
	sph(0.025, Vector3(0.08, 1.0, 0.37), Color.WHITE, steel)


## 靴箱：玄关矮柜（百叶双门 + 顶上一双鞋），台面 0.12m 可跳。
func _b_shoe_cabinet() -> void:
	var wood := _mat_j("shoec", Color(0.66, 0.5, 0.36), position, 0.78, 0.0, 0.08)
	var dark := m_metal_dark(position)
	var steel := m_metal_galva(position)
	box(Vector3(1.05, 0.86, 0.38), Vector3(0, 0.43, 0), Color.WHITE, 0, 0, 0, wood)
	box(Vector3(1.1, 0.05, 0.42), Vector3(0, 0.905, 0), Color.WHITE, 0, 0, 0, wood)   # 台面
	box(Vector3(1.05, 0.06, 0.38), Vector3(0, 0.03, 0), Color.WHITE, 0, 0, 0, dark)   # 踢脚
	# 百叶双门
	for dx in [-0.27, 0.27]:
		box(Vector3(0.5, 0.74, 0.03), Vector3(dx, 0.46, 0.2), Color.WHITE, 0, 0, 0, wood)
		for i in 4:
			box(Vector3(0.42, 0.025, 0.02), Vector3(dx, 0.17 + i * 0.18, 0.22),
				Color.WHITE, 0, 0, 0, dark)
	box(Vector3(0.02, 0.74, 0.04), Vector3(0, 0.46, 0.21), Color.WHITE, 0, 0, 0, dark)
	sph(0.022, Vector3(-0.08, 0.5, 0.23), Color.WHITE, steel)
	sph(0.022, Vector3(0.08, 0.5, 0.23), Color.WHITE, steel)
	# 顶上的一双鞋（鞋身 + 圆鞋头）
	for sx in [-0.16, 0.16]:
		box(Vector3(0.2, 0.08, 0.16), Vector3(sx, 0.975, -0.01), Color("efe9dc"))
		sph(0.055, Vector3(sx, 0.975, 0.07), Color("e6ded0"))


## エアコン：壁挂式室内机，装在高处（视觉中心 y≈2.0m）。无碰撞；点击盒由 click_y 抬升。
func _b_aircon() -> void:
	var body := m_plastic_white(position)
	var dark := m_metal_dark(position)
	var y := 2.0
	box(Vector3(0.92, 0.3, 0.28), Vector3(0, y, 0), Color.WHITE, 0, 0, 0, body)
	box(Vector3(0.86, 0.22, 0.02), Vector3(0, y + 0.02, 0.15), Color.WHITE, 0, 0, 0, body)
	# 导风板（下沿微前倾）
	box(Vector3(0.86, 0.05, 0.06), Vector3(0, y - 0.13, 0.16), Color.WHITE, 0, -0.4, 0, dark)
	# LED 指示灯
	box(Vector3(0.05, 0.022, 0.012), Vector3(0.33, y - 0.05, 0.16), Color.WHITE, 0, 0, 0,
		m_glow(Color(0.5, 0.9, 0.6), 2.0))
	# 墙面安装板
	box(Vector3(0.96, 0.05, 0.06), Vector3(0, y + 0.14, -0.14), Color.WHITE, 0, 0, 0,
		m_metal_galva(position))


## カーペット：平织地毯（双色边框 + 内里纹样），贴地 y≈0.02。
func _b_carpet() -> void:
	var base := _mat_j("rug", Color(0.62, 0.28, 0.26), position, 0.95, 0.0, 0.05)
	var border := _mat_j("rug_b", Color(0.88, 0.83, 0.72), position, 0.95, 0.0, 0.04)
	var accent := _mat_j("rug_a", Color(0.28, 0.42, 0.5), position, 0.95, 0.0, 0.05)
	box(Vector3(2.4, 0.02, 1.8), Vector3(0, 0.02, 0), Color.WHITE, 0, 0, 0, base)
	# 边框
	box(Vector3(2.4, 0.025, 0.16), Vector3(0, 0.022, 0.82), Color.WHITE, 0, 0, 0, border)
	box(Vector3(2.4, 0.025, 0.16), Vector3(0, 0.022, -0.82), Color.WHITE, 0, 0, 0, border)
	box(Vector3(0.16, 0.025, 1.8), Vector3(1.12, 0.022, 0), Color.WHITE, 0, 0, 0, border)
	box(Vector3(0.16, 0.025, 1.8), Vector3(-1.12, 0.022, 0), Color.WHITE, 0, 0, 0, border)
	# 内里：中央菱形 + 两道横条
	box(Vector3(0.5, 0.028, 0.5), Vector3(0, 0.024, 0), Color.WHITE, 0.785, 0, 0, accent)
	box(Vector3(1.6, 0.028, 0.08), Vector3(0, 0.024, 0.5), Color.WHITE, 0, 0, 0, accent)
	box(Vector3(1.6, 0.028, 0.08), Vector3(0, 0.024, -0.5), Color.WHITE, 0, 0, 0, accent)


## 絵画：木框 + 画布 + 抽象色块，挂墙（视觉中心 y≈1.6m）。无碰撞；点击盒由 click_y 抬升。
func _b_painting() -> void:
	var frame := m_wood(position)
	var canvas := _mat_j("canvas", Color(0.92, 0.89, 0.8), position, 0.95, 0.0, 0.03)
	var y := 1.6
	box(Vector3(1.2, 0.8, 0.06), Vector3(0, y, 0), Color.WHITE, 0, 0, 0, frame)
	box(Vector3(1.06, 0.66, 0.02), Vector3(0, y, 0.035), Color.WHITE, 0, 0, 0, canvas)
	# 抽象色块
	box(Vector3(0.34, 0.34, 0.012), Vector3(-0.24, y + 0.1, 0.05), Color("c9543f"))
	box(Vector3(0.2, 0.5, 0.012), Vector3(0.28, y - 0.02, 0.05), Color("2f5f8a"))
	sph(0.09, Vector3(0.0, y + 0.16, 0.055), Color("e0b84a"))


## カーテン：吊轨 + 分幅布帘（前后错位模拟波浪），从地面挂到接近天花板。
func _b_curtain() -> void:
	var rail := m_metal_galva(position)
	var cloth := _mat_j("curtain", Color(0.74, 0.7, 0.6), position, 0.95, 0.0, 0.05)
	var band := _mat_j("curtain_b", Color(0.45, 0.52, 0.6), position, 0.95, 0.0, 0.05)
	# 顶轨（横放的圆柱）
	var r := cyl(0.03, 0.03, 2.05, Vector3(0, 2.16, 0), Color.WHITE, false, rail)
	r.rotation = Vector3(0, 0, PI * 0.5)
	# 顶带 + 分幅帘身
	box(Vector3(2.02, 0.26, 0.06), Vector3(0, 1.96, 0), Color.WHITE, 0, 0, 0, band)
	for i in 4:
		var x := -0.75 + i * 0.5
		var wob := 0.03 if i % 2 == 0 else -0.03
		var ry := 0.05 if i % 2 == 0 else -0.05
		box(Vector3(0.48, 1.86, 0.03), Vector3(x, 1.0, wob), Color.WHITE, ry, 0, 0, cloth)


## レジ：收银 POS（底座抽屉 + 屏 + 键位 + 小票机）。
func _b_register() -> void:
	var body := _mat_j("reg", Color(0.28, 0.3, 0.34), position, 0.4, 0.15, 0.05)
	var panel := m_plastic_white(position)
	var dark := m_metal_dark(position)
	# 底座 + 抽屉缝
	box(Vector3(0.78, 0.5, 0.68), Vector3(0, 0.25, 0), Color.WHITE, 0, 0, 0, body)
	box(Vector3(0.7, 0.02, 0.02), Vector3(0, 0.34, 0.345), Color.WHITE, 0, 0, 0, panel)
	# 屏支臂 + 发光屏
	box(Vector3(0.12, 0.28, 0.12), Vector3(0, 0.62, -0.14), Color.WHITE, 0, 0, 0, body)
	box(Vector3(0.52, 0.34, 0.04), Vector3(0, 0.86, 0.05), Color.WHITE, 0, -0.18, 0, body)
	box(Vector3(0.44, 0.26, 0.02), Vector3(0, 0.865, 0.075), Color.WHITE, 0, -0.18, 0,
		m_glow(Color(0.6, 0.85, 1.0), 1.8))
	# 键盘 + 键帽
	box(Vector3(0.5, 0.03, 0.26), Vector3(0, 0.52, 0.16), Color.WHITE, 0, -0.35, 0, panel)
	for kx in 5:
		box(Vector3(0.05, 0.015, 0.05), Vector3(-0.16 + kx * 0.08, 0.535, 0.2),
			Color.WHITE, 0, 0, 0, dark)
	# 小票打印机 + 吐出的小票
	box(Vector3(0.24, 0.16, 0.22), Vector3(-0.26, 0.58, -0.1), Color.WHITE, 0, 0, 0, body)
	box(Vector3(0.2, 0.01, 0.03), Vector3(-0.26, 0.665, -0.1), Color.WHITE, 0, 0, 0, panel)
	box(Vector3(0.17, 0.14, 0.006), Vector3(-0.26, 0.74, -0.1), Color("f4f2ec"))


## 陳列棚：超市/便利店的开口货架（背板 + 侧板 + 4 层货板 + 彩色商品）。
func _b_display_shelf() -> void:
	var frame := m_metal_galva(position)
	var back := _mat_j("disp", Color(0.7, 0.71, 0.73), position, 0.5, 0.3, 0.05)
	var goods := [Color("d64541"), Color("2f6fb2"), Color("5e9c54"),
		Color("e6b84c"), Color("d97fb0"), Color("e08a3c")]
	# 背板 + 两侧板
	box(Vector3(1.95, 1.6, 0.05), Vector3(0, 0.8, -0.285), Color.WHITE, 0, 0, 0, back)
	box(Vector3(0.05, 1.6, 0.62), Vector3(-0.95, 0.8, 0), Color.WHITE, 0, 0, 0, frame)
	box(Vector3(0.05, 1.6, 0.62), Vector3(0.95, 0.8, 0), Color.WHITE, 0, 0, 0, frame)
	# 货板 + 每层商品（罐 / 盒交替）
	for i in 4:
		var y := 0.2 + i * 0.42
		box(Vector3(1.95, 0.04, 0.6), Vector3(0, y, -0.02), Color.WHITE, 0, 0, 0, frame)
		for j in 6:
			var col: Color = goods[(i * 6 + j) % goods.size()]
			if (i + j) % 3 == 0:
				cyl(0.05, 0.05, 0.18, Vector3(-0.75 + j * 0.3, y + 0.11, 0.02), Color.WHITE, false,
					_mat_j("can%d%d" % [i, j], col, position + Vector3(i, j, 0), 0.35, 0.4, 0.06))
			else:
				box(Vector3(0.18, 0.22, 0.16), Vector3(-0.75 + j * 0.3, y + 0.13, 0.02),
					Color.WHITE, 0, 0, 0,
					_mat_j("good%d%d" % [i, j], col, position + Vector3(i, j, 0), 0.5, 0.0, 0.08))
	# 顶板
	box(Vector3(1.95, 0.05, 0.62), Vector3(0, 1.6, 0), Color.WHITE, 0, 0, 0, frame)


## カウンター：吧台/收银台（柜体 + 出挑木台面 + 台上杯盘），台面 0.12m 可跳。
func _b_counter() -> void:
	var body := _mat_j("cnt", Color(0.82, 0.79, 0.72), position, 0.8, 0.0, 0.05)
	var top := m_wood(position)
	var dark := m_metal_dark(position)
	box(Vector3(2.2, 0.95, 0.6), Vector3(0, 0.475, 0), Color.WHITE, 0, 0, 0, body)
	box(Vector3(2.4, 0.08, 0.72), Vector3(0, 0.99, 0), Color.WHITE, 0, 0, 0, top)   # 出挑台面
	box(Vector3(2.2, 0.05, 0.02), Vector3(0, 0.15, 0.31), Color.WHITE, 0, 0, 0, dark)  # 踢脚线
	# 台上：托盘 + 马克杯 + 小屏
	box(Vector3(0.5, 0.03, 0.34), Vector3(-0.6, 1.045, 0), Color.WHITE, 0, 0, 0, dark)
	cyl(0.055, 0.05, 0.11, Vector3(0.5, 1.085, 0.05), Color("f2ece0"))
	cyl(0.06, 0.06, 0.012, Vector3(0.5, 1.145, 0.05), Color.WHITE, false, top)
	box(Vector3(0.3, 0.22, 0.03), Vector3(0.95, 1.14, -0.1), Color.WHITE, -0.2, 0, 0, dark)


## スツール：圆凳（座面 + 4 条外撇金属脚 + 脚踏圈），座面 0.1m 可跳。
func _b_stool() -> void:
	var seat := _mat_j("stool", Color(0.72, 0.5, 0.32), position, 0.6, 0.0, 0.07)
	var metal := m_metal_dark(position)
	cyl(0.22, 0.22, 0.05, Vector3(0, 0.55, 0), Color.WHITE, false, seat)
	cyl(0.23, 0.23, 0.02, Vector3(0, 0.585, 0), Color.WHITE, false, metal)
	for lx in [-0.13, 0.13]:
		for lz in [-0.13, 0.13]:
			var leg := cyl(0.015, 0.02, 0.55, Vector3(lx, 0.275, lz), Color.WHITE, false, metal)
			leg.rotation = Vector3(lz * 0.18, 0, -lx * 0.18)
	torus(0.15, 0.17, Vector3(0, 0.16, 0), Color.WHITE, false, metal)


## 券売機：车站/拉面店的自动售票机（机身 + 蓝光屏 + 按钮 + 投币口 + 招牌）。
func _b_ticket_machine() -> void:
	var body := _mat_j("tkm", Color(0.86, 0.87, 0.88), position, 0.4, 0.1, 0.04)
	var dark := m_metal_dark(position)
	box(Vector3(0.9, 1.8, 0.9), Vector3(0, 0.9, 0), Color.WHITE, 0, 0, 0, body)
	box(Vector3(0.95, 0.1, 0.95), Vector3(0, 0.05, 0), Color.WHITE, 0, 0, 0, dark)  # 底座
	box(Vector3(0.82, 1.5, 0.03), Vector3(0, 1.0, 0.46), Color.WHITE, 0, 0, 0, dark)  # 面板
	# 发光蓝屏
	box(Vector3(0.62, 0.5, 0.03), Vector3(0, 1.45, 0.48), Color.WHITE, 0, 0, 0,
		m_glow(Color(0.45, 0.7, 1.0), 2.2))
	# 按钮（3 行 × 4 列）
	for r in 3:
		for c in 4:
			box(Vector3(0.12, 0.09, 0.03), Vector3(-0.27 + c * 0.18, 1.08 - r * 0.14, 0.48),
				Color("2f4a72"))
	# 投币口 + 退币口 + 取票口
	box(Vector3(0.03, 0.12, 0.03), Vector3(0.33, 0.9, 0.48), Color.WHITE, 0, 0, 0, dark)
	box(Vector3(0.16, 0.06, 0.03), Vector3(0.3, 0.75, 0.48), Color("efe9dc"))
	box(Vector3(0.4, 0.08, 0.04), Vector3(-0.05, 0.62, 0.48), Color.WHITE, 0, 0, 0, dark)
	# 顶部招牌
	box(Vector3(0.92, 0.24, 0.94), Vector3(0, 1.9, 0), Color("2b6cb0"))
	text3d("きっぷ", 96, Vector3(0, 1.9, 0.49), Color.WHITE)


## 改札機：自动检票闸机（两端机箱 + 斜面顶 + 红绿指示灯 + 挡板）。
func _b_gate() -> void:
	var body := m_metal_cool(position)
	var dark := m_metal_dark(position)
	var panel := _mat_j("gate", Color(0.78, 0.79, 0.8), position, 0.4, 0.3, 0.05)
	# 两端机箱
	box(Vector3(0.34, 1.04, 0.58), Vector3(-0.73, 0.52, 0), Color.WHITE, 0, 0, 0, body)
	box(Vector3(0.34, 1.04, 0.58), Vector3(0.73, 0.52, 0), Color.WHITE, 0, 0, 0, body)
	# 斜面顶盖 + 连接顶
	box(Vector3(1.8, 0.14, 0.58), Vector3(0, 1.06, 0), Color.WHITE, 0, 0, 0, panel)
	box(Vector3(1.8, 0.1, 0.6), Vector3(0, 1.14, 0), Color.WHITE, 0, 0, 0, body)
	# 读卡区
	box(Vector3(0.26, 0.02, 0.2), Vector3(-0.73, 1.1, 0.06), Color.WHITE, 0, 0, 0, dark)
	box(Vector3(0.26, 0.02, 0.2), Vector3(0.73, 1.1, 0.06), Color.WHITE, 0, 0, 0, dark)
	# 指示灯：两端一红一绿，按位置哈希决定亮哪颗
	var green := m_glow(Color(0.4, 0.9, 0.5), 2.4)
	var red := m_glow(Color(1.0, 0.4, 0.35), 2.4)
	var lit := green if _var_seed(position) > 0.0 else red
	var off := red if _var_seed(position) > 0.0 else green
	box(Vector3(0.08, 0.05, 0.03), Vector3(-0.73, 0.98, 0.3), Color.WHITE, 0, 0, 0, lit)
	box(Vector3(0.08, 0.05, 0.03), Vector3(0.73, 0.98, 0.3), Color.WHITE, 0, 0, 0, off)
	# 挡板（中间两片斜的深色板）
	for sx in [-0.36, 0.36]:
		box(Vector3(0.5, 0.5, 0.04), Vector3(sx, 0.6, 0.0), Color("3a4a66"),
			0, 0, -0.18 if sx < 0 else 0.18)


## 駅名標：吊挂站名板（两根吊杆 + 白板 + 彩色色带 + 站名文字），视觉中心 y≈2.4m。
## 无碰撞；点击盒由 click_y 抬升。
func _b_station_sign() -> void:
	var board := m_plastic_white(position)
	var band := _mat_j("sign_band", Color(0.2, 0.42, 0.66), position, 0.5, 0.05, 0.04)
	var rod := m_metal_galva(position)
	var y := 2.4
	# 吊杆（从板顶伸向天花板）
	for rx in [-0.9, 0.9]:
		cyl(0.02, 0.02, 0.55, Vector3(rx, y + 0.59, 0), Color.WHITE, false, rod)
	# 板体 + 上下边条 + 色带
	box(Vector3(2.4, 0.62, 0.1), Vector3(0, y, 0), Color.WHITE, 0, 0, 0, board)
	box(Vector3(2.42, 0.02, 0.11), Vector3(0, y + 0.31, 0), Color.WHITE, 0, 0, 0, band)
	box(Vector3(2.42, 0.02, 0.11), Vector3(0, y - 0.31, 0), Color.WHITE, 0, 0, 0, band)
	box(Vector3(2.4, 0.16, 0.11), Vector3(0, y + 0.16, 0), Color.WHITE, 0, 0, 0, band)
	text3d("みなと駅", 120, Vector3(0, y - 0.1, 0.06), Color("2b2f38"))


# ================================================================
# 批次 9：公共设施 / 交通 / 单词牌 / 动物
# ================================================================
# 【为什么加这一批】words.json 有 514 个词，但改版星球地图上只有 44 个带 word
# （室内再补 26 个）—— 十个分类是 0%，其中学校/寺/病院这类具象词完全没载体。
# 本批用「已经下载到本机的 CC0 模型 + 程序化几何」补载体，不新增任何素材文件。
# 授权边界：只用 Kenney / Quaternius / Poly Haven（CC0）；不碰 assets/art（来源不明的
# 商业游戏提取物）。

# ---- 公共设施：屋顶沿用 prism，墙面走 mat_photo，招牌用 text3d ----

## 寺：町屋形 + 大挑檐 + 朱色柱。挑檐是寺的识别特征（比民居出挑 1.2m）。
func _b_temple() -> void:
	var wall := _var(Color("e8e0cd"))
	box(Vector3(5.0, 3.6, 4.4), Vector3(0, 1.8, 0), wall, 0.0, 0.0, 0.0,
		mat_photo("grey_plaster", _var(Color(0.95, 0.90, 0.80)), 0.72, 0.94, 0.42, ProceduralTex.wall_tiles(23), 1.5, 2.2, 0.4))
	# 屋顶：宽出挑的 double-pitch（比墙宽 1.2m）
	prism(Vector3(6.4, 1.5, 5.6), Vector3(0, 4.35, 0),
		mat_photo("patterned_slate_tiles", _var(Color(0.86, 0.80, 0.74)), 0.78, 0.72, 0.55, ProceduralTex.roof_tiles(11), 1.1, 2.4, 0.45), PI * 0.5)
	box(Vector3(6.5, 0.16, 0.26), Vector3(0, 5.14, 0), Color("4a4038"))
	# 拜殿前廊：朱色立柱 + 木质栏间
	var verm := m_vermilion(position)
	for cx in [-2.2, -0.75, 0.75, 2.2]:
		cyl(0.16, 0.17, 3.0, Vector3(cx, 1.5, 2.6), Color.WHITE, false, verm)
	box(Vector3(5.2, 0.14, 0.16), Vector3(0, 3.1, 2.6), Color("6a5344"))
	box(Vector3(5.2, 0.1, 0.14), Vector3(0, 0.55, 2.6), Color("6a5344"))
	# 鸱尾（屋顶两端的翘角）
	box(Vector3(0.16, 0.7, 0.5), Vector3(-3.1, 5.3, -2.0), Color("4a4038"))
	box(Vector3(0.16, 0.7, 0.5), Vector3(3.1, 5.3, -2.0), Color("4a4038"))
	# 额縁「寺」匾额
	box(Vector3(1.7, 0.62, 0.1), Vector3(0, 3.62, 2.5), Color("3a3128"))
	text3d("寺", 96, Vector3(0, 3.62, 2.58), Color("f2e6cf"))
	# 石阶
	for i in 3:
		box(Vector3(3.0 - i * 0.2, 0.16, 0.34), Vector3(0, 0.08 + i * 0.16, 2.9 + i * 0.32), Color("b9b2a4"))


## 学校：长条形校舍 + Kenney 雨棚（awning，当前未用）。窗做成上下两排教室格。
func _b_school() -> void:
	var wall := _var(Color("e6e4dc"))
	box(Vector3(8.8, 4.4, 4.6), Vector3(0, 2.2, 0), wall, 0.0, 0.0, 0.0,
		mat_photo("plaster_paint", _var(Color(0.92, 0.91, 0.88)), 0.72, 0.9, 0.45, ProceduralTex.plaster(29), 1.6, 2.2, 0.4))
	box(Vector3(9.2, 0.34, 5.0), Vector3(0, 4.58, 0), Color("6d7278"))
	# 两排教室窗（沿 X 每 1.6m 一扇）
	for row in 2:
		var wy := 1.5 + row * 1.75
		for i in 5:
			_window_unit(1.2, 0.95, Vector3(-3.2 + i * 1.6, wy, 2.32))
	# 校门雨棚：Kenney awning（挂在门楣上）
	_glb_h("kenney/awning.glb", 1.9, Vector3(0, 3.05, 2.9))
	# 校门 + 铭牌
	box(Vector3(1.5, 2.15, 0.12), Vector3(-2.6, 1.08, 2.36), Color("4a5560"))
	box(Vector3(2.6, 0.5, 0.1), Vector3(1.9, 3.3, 2.36), Color("e8e4d8"))
	text3d("学校", 76, Vector3(1.9, 3.3, 2.44), Color("2b3340"))
	# 操场侧旗杆 + 体操棒
	cyl(0.06, 0.07, 3.4, Vector3(-3.9, 1.7, 2.7), Color.WHITE, false, m_plastic_white(position))
	box(Vector3(0.5, 0.34, 0.02), Vector3(-3.66, 3.05, 2.7), Color("c94f4f"))


## 病院：白墙平屋顶 + 绿十字灯箱（夜间发光）。
func _b_hospital() -> void:
	var wall := _var(Color("f4f2ee"))
	box(Vector3(6.8, 4.8, 4.8), Vector3(0, 2.4, 0), wall, 0.0, 0.0, 0.0,
		mat_photo("concrete_wall_001", _var(Color(0.97, 0.96, 0.94)), 0.7, 0.88, 0.42, ProceduralTex.plaster(31), 1.4, 2.2, 0.35))
	box(Vector3(7.2, 0.36, 5.2), Vector3(0, 4.98, 0), Color("9aa0a6"))
	# 正门雨棚
	box(Vector3(4.6, 0.2, 1.3), Vector3(0, 3.05, 2.8), Color.WHITE, 0, 0, 0, m_metal_galva(position))
	for sx in [-2.1, 2.1]:
		cyl(0.09, 0.09, 3.0, Vector3(sx, 1.5, 3.35), Color.WHITE, false, m_plastic_white(position))
	# 绿十字灯箱（self-lit，夜里是街上的一个绿点）
	var green := m_glow(Color(0.36, 0.78, 0.5), 1.6)
	box(Vector3(1.15, 1.15, 0.12), Vector3(0, 4.0, 2.46), Color.WHITE, 0, 0, 0, green)
	box(Vector3(0.74, 0.24, 0.06), Vector3(0, 4.0, 2.54), Color.WHITE, 0, 0, 0, green)
	box(Vector3(0.24, 0.74, 0.06), Vector3(0, 4.0, 2.54), Color.WHITE, 0, 0, 0, green)
	text3d("病院", 66, Vector3(2.1, 2.3, 2.42), Color("3d4a44"))
	# 大窗（病房采光）
	for i in 4:
		_window_unit(1.25, 1.3, Vector3(-2.55 + i * 1.7, 2.1, 2.38))


## 銀行：石材立面 + 深檐 + 石柱。比民居厚重，用石材贴图拉开层级。
func _b_bank() -> void:
	box(Vector3(5.4, 4.0, 4.2), Vector3(0, 2.0, 0), _var(Color("d8d4c8")), 0.0, 0.0, 0.0,
		mat_photo("rustic_stone_wall", _var(Color(0.90, 0.88, 0.82)), 0.88, 0.92, 0.8, ProceduralTex.pavers(37), 0.6, 2.2, 0.45))
	box(Vector3(6.0, 0.5, 4.8), Vector3(0, 4.24, 0), Color("6a6f78"))
	# 四根石柱撑檐
	for cx in [-2.3, -0.78, 0.78, 2.3]:
		cyl(0.24, 0.27, 3.2, Vector3(cx, 1.6, 2.5), Color.WHITE, false, m_concrete(position))
	box(Vector3(5.6, 0.2, 1.0), Vector3(0, 3.32, 2.5), Color("7c828c"))
	# 铜绿色「銀行」匾额
	box(Vector3(2.0, 0.56, 0.1), Vector3(0, 3.95, 2.36), Color("3f6b5c"))
	text3d("銀行", 78, Vector3(0, 3.95, 2.44), Color("f2e6cf"))
	# 柱础
	for cx in [-2.3, -0.78, 0.78, 2.3]:
		cyl(0.32, 0.32, 0.16, Vector3(cx, 0.08, 2.5), Color("b8b2a4"))
	_window_unit(1.5, 1.7, Vector3(-1.5, 1.5, 2.13))
	_window_unit(1.5, 1.7, Vector3(1.5, 1.5, 2.13))


## 警察署：蓝白配色 + 门前警灯柱。蓝用低饱和的藏青，不用饱和警蓝（过饱和违反 §3）。
func _b_police() -> void:
	var wall := _var(Color("dfe4ea"))
	box(Vector3(5.4, 3.8, 4.2), Vector3(0, 1.9, 0), wall, 0.0, 0.0, 0.0,
		mat_photo("grey_plaster", _var(Color(0.88, 0.90, 0.94)), 0.72, 0.9, 0.42, ProceduralTex.wall_tiles(41), 1.5, 2.0, 0.4))
	box(Vector3(5.9, 0.34, 4.7), Vector3(0, 4.0, 0), Color("4a5666"))
	# 蓝色腰带（沿墙一圈）
	box(Vector3(5.44, 0.4, 0.06), Vector3(0, 1.5, 2.12), Color("3d5674"))
	# 招牌
	box(Vector3(1.9, 0.5, 0.1), Vector3(0, 3.4, 2.14), Color("2f4460"))
	text3d("警察署", 68, Vector3(0, 3.4, 2.22), Color("f2e6cf"))
	# 门前警灯柱（红蓝交替的小灯）
	cyl(0.13, 0.15, 1.1, Vector3(-2.9, 0.55, 3.1), Color.WHITE, false, m_plastic_white(position))
	sph(0.15, Vector3(-2.9, 1.2, 3.1), Color("3d5674"))
	# 窗
	_window_unit(1.3, 1.0, Vector3(-1.4, 2.1, 2.12))
	_window_unit(1.3, 1.0, Vector3(1.4, 2.1, 2.12))


## 図書館：木柱檐廊 + 高窗。木头+纸白的配色，和学校的灰石拉开。
func _b_library() -> void:
	var wall := _var(Color("ece4d2"))
	box(Vector3(5.8, 4.0, 4.4), Vector3(0, 2.0, 0), wall, 0.0, 0.0, 0.0,
		mat_photo("plaster_alt", _var(Color(0.94, 0.89, 0.78)), 0.75, 0.93, 0.44, ProceduralTex.plaster(37), 1.6, 2.2, 0.4))
	prism(Vector3(6.6, 1.3, 5.2), Vector3(0, 4.6, 0),
		mat_photo("roof", _var(Color(0.78, 0.70, 0.62)), 0.8, 0.74, 0.55, ProceduralTex.roof_tiles(13), 1.0, 2.4, 0.45), PI * 0.5)
	# 木柱檐廊
	var wood := m_wood(position)
	for cx in [-2.5, -0.85, 0.85, 2.5]:
		cyl(0.14, 0.16, 3.3, Vector3(cx, 1.65, 2.5), Color.WHITE, false, wood)
	box(Vector3(5.8, 0.18, 1.0), Vector3(0, 3.42, 2.5), Color.WHITE, 0, 0, 0, wood)
	# 高窗 + 书架纹理暗示（竖向格栅）
	for i in 5:
		var wx := -2.2 + i * 1.1
		_window_unit(0.85, 1.6, Vector3(wx, 2.3, 2.22))
	box(Vector3(2.0, 0.5, 0.1), Vector3(0, 3.75, 2.28), Color("6b5236"))
	text3d("図書館", 66, Vector3(0, 3.75, 2.36), Color("f7f1e0"))
	for i in 6:
		box(Vector3(0.06, 1.0, 0.04), Vector3(-2.4 + i * 0.96, 1.4, 2.24), Color("8a6c48"))


# ---- 交通 ----

## トラック：【Kenney Car Kit / CC0】body + 货箱。比 car 高一截，META 已按 2.2m 给碰撞。
func _b_truck() -> void:
	var ry := _var_seed(position) * TAU
	_glb_h("kenney/truck.glb", 2.2, Vector3.ZERO, ry)


## 船：程序化舢板（船体 + 座板 + 桅杆 + 系缆桩）。船不能有碰撞 ——
## 摆在岸上时它是个「可走近拍照」的道具，猫掉进海里比撞到船更符合直觉。
func _b_boat() -> void:
	var ry := _var_seed(position) * TAU
	var hull := _mat_j("boat_hull", Color("e6e2d6"), position, 0.8, 0.0)
	var wood := m_wood(position)
	var g := Node3D.new()
	add_child(g)
	g.rotation.y = ry
	# 船体：前后收窄（用两块不同宽度的 box 近似锥形）
	box(Vector3(2.3, 0.52, 0.9), Vector3(0, 0.3, 0), Color.WHITE, 0, 0, 0, hull)
	box(Vector3(1.7, 0.52, 0.9), Vector3(0.95, 0.32, 0), Color.WHITE, 0, 0, 0, hull)
	box(Vector3(1.7, 0.52, 0.9), Vector3(-0.95, 0.32, 0), Color.WHITE, 0, 0, 0, hull)
	box(Vector3(0.5, 0.56, 0.9), Vector3(1.85, 0.3, 0), Color.WHITE, 0, 0, 0, hull)
	box(Vector3(0.5, 0.56, 0.9), Vector3(-1.85, 0.3, 0), Color.WHITE, 0, 0, 0, hull)
	# 舷侧 + 座板
	box(Vector3(4.4, 0.09, 0.94), Vector3(0, 0.62, 0), Color.WHITE, 0, 0, 0, wood)
	box(Vector3(1.0, 0.08, 0.8), Vector3(-0.6, 0.5, 0), Color.WHITE, 0, 0, 0, wood)
	# 桅杆 + 缆绳
	cyl(0.045, 0.055, 1.7, Vector3(0.2, 1.4, 0), Color.WHITE, false, wood)
	box(Vector3(0.04, 0.04, 1.5), Vector3(0.2, 1.9, 0), Color.WHITE, 0, 0, 0, m_wood(position))
	# 系缆桩
	for sx in [-1.5, 1.5]:
		cyl(0.09, 0.11, 0.2, Vector3(sx, 0.72, 0), Color.WHITE, false, wood)


## 切符：券売機/改札旁的木牌，写着「切符」。贴在木杆上，小道具。
func _b_ticket_sign() -> void:
	var ry := _var_seed(position) * TAU
	var wood := m_wood(position)
	cyl(0.06, 0.07, 1.2, Vector3(0, 0.6, 0), Color.WHITE, false, wood)
	box(Vector3(0.72, 0.9, 0.06), Vector3(0, 1.3, 0), Color("f2e6cf"), 0, 0, 0,
		mat_photo("wooden_panels", Color(0.94, 0.88, 0.74), 0.7, 0.94, 0.8, ProceduralTex.wood(27), 0.5, 1.0, 0.3))
	box(Vector3(0.8, 0.07, 0.09), Vector3(0, 1.78, 0.01), Color("6a5344"))
	box(Vector3(0.8, 0.07, 0.09), Vector3(0, 0.82, 0.01), Color("6a5344"))
	var l := text3d("切符", 88, Vector3(0, 1.3, 0.06), Color("2b2b33"))
	l.rotation.y = ry


## 商店货架：程序化三层货架 + Kenney 集装箱（container_a，未用）当底座 + 价签。
## 台面 0.5m —— 猫能跳上去（jump 0.66m）。
func _b_goods() -> void:
	var ry := _var_seed(position) * TAU
	var wood := m_wood(position)
	var g := Node3D.new()
	add_child(g)
	g.rotation.y = ry
	# 底座集装箱（Kenney CC0）
	_glb_h("kenney/container_a.glb", 0.42, Vector3(0, 0, 0), 0.0)
	# 三层货架
	for i in 3:
		var y := 0.5 + i * 0.34
		box(Vector3(1.6, 0.06, 0.66), Vector3(0, y, 0), Color.WHITE, 0, 0, 0, wood)
		# 层板上的货（随机高度的小方块/球）
		for j in 4:
			var h := _var_seed(position + Vector3(i * 3, j * 5, 1))
			var bx := -0.6 + j * 0.4
			if h < 0.5:
				box(Vector3(0.24, 0.22, 0.24), Vector3(bx, y + 0.14, 0), _var(Color("c8b89a"), 0.12))
			else:
				cyl(0.1, 0.1, 0.26, Vector3(bx, y + 0.16, 0), _var(Color("b8a888"), 0.1))
	# 侧板 + 顶棚
	for sx in [-0.82, 0.82]:
		box(Vector3(0.06, 1.1, 0.66), Vector3(sx, 0.86, 0), Color.WHITE, 0, 0, 0, wood)
	box(Vector3(1.8, 0.08, 0.8), Vector3(0, 1.42, 0), Color("6a5344"))
	# 价签条
	box(Vector3(1.5, 0.14, 0.03), Vector3(0, 1.3, 0.36), Color("f2e6cf"))


## 单词牌：立式看板，抽象词（色/数/时间/身体/衣服）的载体。
## 【教学妥协 —— 唯一一处】牌面直接写着词。取舍：0% 分类要么这样补上，
## 要么永远学不到。只给抽象分类用；具象分类一律走真实物件（寺/学校/动物…）。
## 底色按词的实际颜色取，让「赤」真的是红牌、「白」真的是白牌 —— 近看有信息量。
func _b_plate() -> void:
	var ry := _var_seed(position) * TAU
	# 牌面对应的词：planet.json 只写 word（= words.json 的 id），
	# 日文从 Game.word() 取；取不到就画一块无字牌（宁可空白也不显示错的字）。
	var wid := String(extra.get("word", ""))
	var wd: Dictionary = Game.word(wid) if wid != "" else {}
	# 语义色表优先；没登记的词退回米色
	var tint: Color = PLATE_TINTS.get(wid, Color("efe6d2"))
	var ink: Color = PLATE_INK.get(wid, Color("2b2b33"))
	var wood := m_wood(position)
	var g := Node3D.new()
	add_child(g)
	g.rotation.y = ry
	# 两根木腿
	for sx in [-0.36, 0.36]:
		box(Vector3(0.08, 1.5, 0.08), Vector3(sx, 0.75, 0), Color.WHITE, 0, 0, 0, wood)
	# 牌面（略后倾 7°，像真的告示牌）
	var face := box(Vector3(0.94, 1.14, 0.07), Vector3(0, 1.12, 0.01), Color.WHITE, 0, 0, 0,
		_mat_j("plate_face_%s" % wid, tint, position, 0.86, 0.0, 0.04))
	face.rotation = Vector3(-0.12, 0, 0)
	# 上下的木压条
	for sy in [-0.57, 0.57]:
		var bar := box(Vector3(1.0, 0.09, 0.09), Vector3(0, 1.12 + sy, 0.045), Color.WHITE, 0, 0, 0, wood)
		bar.rotation = Vector3(-0.12, 0, 0)
	# 词：ja（漢字/汉字）写在牌面上
	var ja := String(wd.get("ja", ""))
	if ja != "":
		var lbl := text3d(ja, 112, Vector3(0, 1.12, 0.09), ink)
		lbl.rotation = Vector3(-0.12, 0, 0)
	# 顶檐小帽
	var cap := box(Vector3(1.06, 0.06, 0.22), Vector3(0, 1.76, 0.02), Color.WHITE, 0, 0, 0, wood)
	cap.rotation = Vector3(-0.12, 0, 0)


## 【plate 牌的语义色表】只覆盖 color 分类的 14 个词 + 少量中性色。
## 键 = words.json 的 word id。牌面底色 = 该词的真实颜色。
const PLATE_TINTS := {
	"aka": Color("d05a5a"), "ao": Color("5b7fb0"), "kiiro": Color("e0c04a"),
	"midori": Color("6f9e63"), "shiro": Color("f2f0ea"), "kuro": Color("4a4a52"),
	"haiiro": Color("a8a8a4"), "chairo": Color("b98a5e"), "pinku": Color("e8a8c0"),
	"orenji": Color("e08b45"), "murasaki": Color("8b6fa8"), "kiniro": Color("d4b64a"),
	"giniro": Color("a8aab0"), "iro": Color("e4dcc8"),
}
## 牌面字色：浅色牌用深字，深色牌用浅字，保证可读。
const PLATE_INK := {
	"shiro": Color("3a3a42"), "kiiro": Color("4a3f18"), "kiniro": Color("4a3f18"),
	"ao": Color("f0f4fa"), "midori": Color("f2f6ee"), "murasaki": Color("f2eefa"),
	"kuro": Color("f0f0f2"), "haiiro": Color("3a3a42"),
}


# ---- 动物：全部 Quaternius Ultimate Animal Pack / CC0，自带 idle/walk 动画 ----
# 照抄 _b_dog() 的写法：_glb_h 归一化到肩高，再 find_anim/pick_anim 播动画。

## 山羊（Deer 模型 / CC0）：归一化到 0.62m 肩高。
func _b_deer() -> void:
	var n := _glb_h("animals/Deer.gltf", 0.62, Vector3.ZERO, _var_seed(position) * TAU)
	if n == null:
		return
	var ap := ModelUtil.find_anim(n, ["idle"])
	var a := ModelUtil.pick_anim(ap, ["idle", "walk"])
	if ap != null and a != "":
		ap.play(a)


## きつね（Fox 模型 / CC0）：0.4m，狐狸本就该比狗小一圈。
func _b_fox() -> void:
	var n := _glb_h("animals/Fox.gltf", 0.4, Vector3.ZERO, _var_seed(position) * TAU)
	if n == null:
		return
	var ap := ModelUtil.find_anim(n, ["idle"])
	var a := ModelUtil.pick_anim(ap, ["idle", "walk"])
	if ap != null and a != "":
		ap.play(a)


## 狼（Husky 模型 / CC0）：0.55m。
func _b_wolf() -> void:
	var n := _glb_h("animals/Husky.gltf", 0.55, Vector3.ZERO, _var_seed(position) * TAU)
	if n == null:
		return
	var ap := ModelUtil.find_anim(n, ["idle"])
	var a := ModelUtil.pick_anim(ap, ["idle", "walk"])
	if ap != null and a != "":
		ap.play(a)


## かめ（Alpaca 模型 / CC0）：刻意压扁成 0.28m 的低矮圆壳 —— 素材库里没有龟模型，
## 这是最接近的替代（读起来是「一只慢慢挪的小动物」）。压扁只改 scale.y，不破坏归一化。
func _b_turtle() -> void:
	var n := _glb_h("animals/Alpaca.gltf", 0.28, Vector3.ZERO, _var_seed(position) * TAU)
	if n == null:
		return
	n.scale = n.scale * Vector3(1.25, 0.6, 1.25)
	var ap := ModelUtil.find_anim(n, ["idle"])
	var a := ModelUtil.pick_anim(ap, ["idle"])
	if ap != null and a != "":
		ap.play(a)
