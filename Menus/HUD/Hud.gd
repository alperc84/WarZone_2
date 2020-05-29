extends CanvasLayer

var user
var kill_msg_slots : Kill_Message_slots
var score_board = preload("res://Objects/Misc/ScoreBoard.tscn").instance()
var admin_menu = null
var frames : int = 0

onready var reload_node = $reload
onready var reload_progress = get_node("reload/TextureProgress")

func _ready():
	if not game_states.is_android:
		$controller.queue_free()
	
	kill_msg_slots = Kill_Message_slots.new(self,8)
	$fps_timer.start()
	score_board.connect("scoreboard_closed", self, "_on_scoreboard_closed")
	
	#Enable admin menu if admin
	if get_tree().is_network_server():
		$Panel2/admin_menu.disabled = false
		admin_menu = load("res://Menus/HUD/AdminPanel.tscn").instance()
		admin_menu.connect("adminPanel_closed", self, "_on_admin_menu_closed")


#setup user
func setUser(u):
	user = u
	$controller.user = u
	user.connect("gun_picked",self,"_on_gun_picked")
	user.connect("gun_loaded", self, "setWeaponInfo")
	user.connect("gun_switched", self, "setWeaponInfo")


#show mags remaining in hud
func setClipCount(count):
	var n = $reload
	for i in range(1,5):
		n.get_node("b" + String(i)).hide()
	
	for i in range(1, count):
		n.get_node("b" + String(i)).show()


func _process(_delta):
	frames += 1
	reload_progress.value =  user.selected_gun.rounds_left

#handle quit pressed
func _on_quit_pressed():
	if get_tree().is_network_server():
		network.kick_player(game_states.player_info.net_id,"Disconnected From Server")
	else:
		network.rpc_id(1,"kick_player",game_states.player_info.net_id,"Disconnected From Server")

#handle paused pressed
func _on_pause_pressed():
	$Panel2.show()
	pauseMenuOpenTween()


class MyPlayerSorter:
	static func sort(a, b):
		if a["kills"] < b["kills"]:
			return false
		return true


func _on_score_pressed():
	pauseMenuCloseTween()
	updateScoreBoard()
	add_child(score_board)

#remove scoreboard when closed
func _on_scoreboard_closed():
	remove_child(score_board)

func updateScoreBoard():
	score_board.setBoardData(game_server._player_data_list)

func _on_zoom_pressed():
	user.get_node("Camera2D").zoom = user.selected_gun.getNextZoom()

func _on_HE_pressed():
	if game_states.player_data.nade_count > 0:
		game_states.player_data.nade_count -= 1
		user.rpc_id(1,"server_throwGrenade")


func addCash(val):
	$Tween.stop_all()
	$cash.visible = true
	$cash.text = "+ $" + String(val)
	$Tween.interpolate_property($cash, "rect_scale", Vector2(0.5,0.5), Vector2(1,1),1.5,Tween.TRANS_ELASTIC,Tween.EASE_IN_OUT)
	$Tween.interpolate_property($cash, "rect_scale", Vector2(1,1), Vector2(0.5,0.5),1,Tween.TRANS_QUAD,Tween.EASE_IN_OUT,1.5)
	$Tween.interpolate_property($cash, "visible", true,false,0.5,Tween.TRANS_LINEAR,Tween.EASE_OUT,3)
	$Tween.start()

class Message_slot:
	var is_free : bool
	var msg : String
	
	func _init():
		is_free = true
		
	func clear_slot():
		msg = ""
		is_free = true
	
	func addMessage(_msg):
		msg = _msg
		is_free = false
	

class Kill_Message_slots:
	var msg_slots : Array
	var timer : Timer
	var active_slots : int
	var max_slots
	var hud
	
	func _init(usr,num = 8):
		hud = usr
		active_slots = 0
		max_slots = num
		for _i in range(0,num):
			msg_slots.append(Message_slot.new())
		timer = Timer.new()
		timer.wait_time = 3.0
		timer.one_shot = true
		timer.connect("timeout",self,"_on_timeout")
		usr.add_child(timer)
	
	func _on_timeout():
		if active_slots:
			active_slots -= 1
			for i in range(active_slots):
				msg_slots[i].addMessage(msg_slots[i + 1].msg)
				msg_slots[i + 1].clear_slot()
			timer.start()
			showKillMsg()
	
	func forceRemove():
		active_slots -= 1
		for i in range(active_slots):
			msg_slots[i].addMessage(msg_slots[i + 1].msg)
			msg_slots[i + 1].clear_slot()
		

	func addKillMessage(msg):
		if not active_slots:
			timer.start()
			
		active_slots += 1
		if active_slots > max_slots:
			active_slots = max_slots
			forceRemove()
			active_slots += 1
		
		msg_slots[active_slots - 1].addMessage(msg)
		showKillMsg()
	
	func showKillMsg():
		var labels = hud.get_node("kill_msg")
		for i in range(active_slots):
			labels.get_node(String(i + 1)).text = msg_slots[i].msg
		for i in range(active_slots,max_slots):
			labels.get_node(String(i + 1)).text = ""
		

func addKillMessage(msg):
	kill_msg_slots.addKillMessage(msg)

#set weapon info in hud
func setWeaponInfo():
	if not user.selected_gun:
		return
	 
	reload_node.get_node("gun_s").texture = user.selected_gun.gun_portrait
	reload_progress.max_value = user.selected_gun.clip_size
	reload_progress.value =  user.selected_gun.rounds_left
	setClipCount(user.selected_gun.clip_count)
	user.get_node("Camera2D").zoom = user.selected_gun.getCurrentZoom()

	if not user.selected_gun.is_connected("gun_reloaded",self,"_on_gun_reload"):
		user.selected_gun.connect("gun_reloaded",self,"_on_gun_reload")


#switch weapon when "next gun" is pressed
func _on_nextGun_pressed():
	user.rpc("switchGun")


func _on_gun_reload():
	setClipCount(user.selected_gun.clip_count)


func _on_gun_picked():
	setClipCount(user.selected_gun.clip_count)
	if not user.selected_gun.is_connected("reloading_gun",self,"_on_gun_reload"):
		user.selected_gun.connect("reloading_gun",self,"_on_gun_reload")

func _on_btn_pressed():
	user.selected_gun.reload()

func _on_back_pressed():
	pauseMenuCloseTween()


func _on_admin_menu_pressed():
	pauseMenuCloseTween()
	add_child(admin_menu)

func _on_admin_menu_closed():
	remove_child(admin_menu)


func _on_fps_timer_timeout():
	$fps.text = String(frames)
	frames = 0

############################Tweeennnnnning##################################

func pauseMenuOpenTween():
	$Panel2.rect_pivot_offset = $Panel2.rect_size / 2
	$Tween.remove_all()
	$Panel2.rect_scale = Vector2(0.01,0.01)
	$Tween.interpolate_property($Panel2,"rect_scale",$Panel2.rect_scale,
		Vector2(1,1),0.5,Tween.TRANS_QUAD,Tween.EASE_OUT)
	$Tween.start()

func pauseMenuCloseTween():
	$Tween.remove_all()
	$Tween.interpolate_property($Panel2,"rect_scale",$Panel2.rect_scale,
		Vector2(0.01,0.01),0.5,Tween.TRANS_QUAD,Tween.EASE_OUT)
	$Tween.interpolate_property($Panel2,"visible",true,false,0.5,Tween.TRANS_LINEAR,Tween.EASE_OUT)
	$Tween.start()




func _on_pick_pressed():
	if user.alive:
		user.pickItem()
		$pick.hide()


func _on_melee_pressed():
	user.performMeleeAttack()


func _on_pic_touch_pressed():
	if user.alive:
		user.pickItem()
		$pick.hide()
