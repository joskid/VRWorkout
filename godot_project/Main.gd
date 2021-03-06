extends Spatial


signal level_finished

var song_index_parameter = 0

var beats = []
var bpm = 60 #only used in freeplay mode
var first_beat = 0 #only used in freeplay mode
var beat_index = 0
var selected_song = 0
var stream
var fly_time = 3.0
var emit_early = 0 #Time it takes the cue to reach the target area. autocalculated
var fly_distance = 0.0 #How far the cue flies, autocalculated
var player_height = 0
var run_point_multiplier = 1
	
var running_speed = 0
	
var current_difficulty = 0

var cue_horiz = preload("res://cue_h_obj.tscn")
var cue_vert = preload("res://cue_v_obj.tscn")
var cue_head = preload("res://cue_head_obj.tscn")
var environment = preload("res://outdoor_env.tres")
var infolayer

var cue_emitter
var target

var CUE_STATE_STAND = 0
var CUE_STATE_SQUAT = 1
var CUE_STATE_PUSHUP = 2
var CUE_STATE_CRUNCH = 3

var CUE_SELECTOR_HEAD = 0
var CUE_SELECTOR_HAND = 1

var cue_emitter_state = CUE_STATE_STAND
var cue_selector = CUE_SELECTOR_HEAD

var level_min_cue_space = 1.0
var level_min_state_duration = 10.0

var min_cue_space = 1.0 #Hard: 1.0 Medium: 2.0 Easy: 3.0
var min_state_duration = 10.0 #Hard 5 Medium 15 Easy 30
var last_emit = 0.0
var state_transition_pause = 1.5
var head_y_pos = 0
var state_changed = true
var last_state_change = 0.0

var rng = RandomNumberGenerator.new()



func state_string(state):
	if state == CUE_STATE_STAND:
		return "stand"
	elif state == CUE_STATE_SQUAT:
		return "squat"
	elif state == CUE_STATE_PUSHUP:
		return "pushup"
	elif state == CUE_STATE_CRUNCH:
		return "crunch"
	
	return "unknown"

func display_state(state):
	var psign = get_node("PositionSign")
	if state == CUE_STATE_STAND:
		psign.stand()
	elif state == CUE_STATE_SQUAT:
		psign.squat()
	elif state == CUE_STATE_PUSHUP:
		psign.pushup()
	elif state == CUE_STATE_CRUNCH:
		psign.crunch()
	
var update_counter = 0
func update_info(hits, max_hits, points):
	var song_pos = int(cue_emitter.current_playback_time)
	var total = int(stream.stream.get_length())
	infolayer.print_info("Hits %d/%d - Song: %d/%.1f%% - Points: %d - Speed: %.1f"% [hits,max_hits,song_pos,float(100*song_pos)/total,points,running_speed])
	if update_counter % 5 == 0:
		infolayer.print_info("Player height: %.2f Difficulty: %d/%.2f/%.2f"%[player_height, current_difficulty, min_cue_space, min_state_duration], "debug")
	update_counter += 1
	
func _ready():
	rng.randomize()
	
	infolayer = get_node("Viewport/InfoLayer")
	cue_emitter = get_node("cue_emitter")
	target = get_node("target")
	update_cue_timing()
	
	var songs = File.new()
	songs.open('res://audio/songs.json', File.READ)
	
	var tmp = songs.get_as_text()
	var song_dict = JSON.parse(tmp).result
	songs.close()
	
	beat_index = 0

	setup_difficulty(current_difficulty)
	
	if song_index_parameter < 0:
		#freeplay mode
		stream = DummyAudioStream.new(abs(song_index_parameter)*100)
		selected_song = "Freeplay"
		print ("BPM %.2f"%bpm)
		beats = []
		var delta = max(0.1, 60.0/float(max(1,bpm)))
		
		var now = OS.get_ticks_msec()
		
		var pos = 0
		#get the correct starting time
		var elapsed = (now - first_beat)/1000.0
		pos =  (ceil(elapsed/delta) - elapsed/delta)*delta
		print ("Start at: %.2f"%pos)
		
		while pos < stream.stream.get_length()-delta:
			beats.append(pos)
			pos += delta
		stream.connect("stream_finished", self, "_on_AudioStreamPlayer_finished")
		self.add_child(stream)
	
	else:
		selected_song = song_dict.keys()[song_index_parameter]
	
		beats = song_dict[selected_song]

		var audio_file = File.new()
		var audio_filename = "res://audio/%s"%selected_song
		
		infolayer.print_info("Loading song %s"%audio_filename)
		audio_file.open(audio_filename,File.READ)
		infolayer.append_info(" / File opened %s" % str(audio_file.is_open()))
		infolayer.print_info(state_string(cue_emitter_state).to_upper(), "main")
		infolayer.print_info("Player height: %.2f Difficulty: %.2f/%.2f"%[player_height, min_cue_space, min_state_duration], "debug")

		var audio_resource = ResourceLoader.load(audio_filename)
		stream = get_node("AudioStreamPlayer")
		stream.stream = audio_resource
	
	stream.play()
	
func setup_difficulty(d):
	if d == 2:
		level_min_cue_space = 0.5
		level_min_state_duration = 10.0 
	elif d == 1:
		level_min_cue_space = 1.0
		level_min_state_duration = 15.0 
	else:	
		level_min_cue_space = 1.5
		level_min_state_duration = 20.0
	min_cue_space = level_min_cue_space
	min_state_duration = level_min_state_duration
	current_difficulty = d
		
var last_playback_time = 0
func _process(delta):
	#cue_emitter.current_playback_time += delta
	cue_emitter.current_playback_time = stream.get_playback_position()
	if beat_index < len(beats)-1 and cue_emitter.current_playback_time + emit_early > beats[beat_index]:	
		if last_emit + min_cue_space < cue_emitter.current_playback_time and last_state_change + state_transition_pause < cue_emitter.current_playback_time:
			emit_cue_node(beats[beat_index])
			last_emit = cue_emitter.current_playback_time
		beat_index += 1
	elif beat_index == len(beats)-1:
		beat_index += 1
		infolayer.print_info("FINISHED", "main")
	
	if cue_emitter.current_playback_time < last_playback_time:
		stream.stop()
	else:		
		last_playback_time = cue_emitter.current_playback_time
	
func _on_exit_timer_timeout():
	print ("End of level going back to main")
	emit_signal("level_finished")
	

func _on_tween_completed(obj,path):
	obj.queue_free()


func update_cue_timing():
	fly_distance = abs(cue_emitter.translation.z-target.translation.z) + 2	
	var time_to_target = abs(cue_emitter.translation.z-target.translation.z) / fly_distance
	emit_early = fly_time * time_to_target


func create_and_attach_cue(cue_type, x, y, target_time, fly_offset=0):
	cue_emitter.max_hits += 1
	var cue_node

	if cue_type == "right":
		cue_node = cue_horiz.instance()
	elif cue_type == "left":
		cue_node = cue_vert.instance()
	else:
		head_y_pos = y
		cue_node = cue_head.instance()

	cue_node.target_time = target_time
	cue_node.start_time = cue_emitter.current_playback_time
	
	var main_node = get_node("cue_emitter")
	var move_modifier = Tween.new()
	move_modifier.set_name("tween")
	cue_node.add_child(move_modifier)
	main_node.add_child(cue_node)
	cue_node.translation = Vector3(x,y,0+fly_offset)
	if cue_type == "head_inverted":
		cue_node.set_transform( cue_node.get_transform().rotated(Vector3(0,0,1), 3.1415926))
	
	if cue_type == "left" or cue_type == "right":
		var alpha = atan2(x,y-head_y_pos)
		cue_node.set_transform(cue_node.get_transform().rotated(Vector3(0,0,1),-alpha))
	
	move_modifier.interpolate_property(cue_node,"translation",Vector3(x,y,0+fly_offset),Vector3(x,y,fly_distance+fly_offset),fly_time,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0)
	move_modifier.connect("tween_completed",self,"_on_tween_completed")
	move_modifier.start()
	return cue_node
	
var state_model = { CUE_STATE_STAND: { CUE_STATE_SQUAT: 10, CUE_STATE_PUSHUP: 10, CUE_STATE_CRUNCH: 10},
					CUE_STATE_SQUAT: { CUE_STATE_STAND: 10, CUE_STATE_PUSHUP: 10, CUE_STATE_CRUNCH: 10},
					CUE_STATE_PUSHUP: { CUE_STATE_STAND: 10, CUE_STATE_SQUAT: 10},
					CUE_STATE_CRUNCH: { CUE_STATE_STAND: 10, CUE_STATE_SQUAT: 10}
					}
	
func state_transition(old_state):
	var state_selector = rng.randi()%100
	var new_state = old_state
	var probabilities = state_model[old_state]
	var cumulative_probability = 0
	for k in probabilities.keys():
		cumulative_probability += probabilities[k]
		if state_selector < cumulative_probability:
			new_state = k
			break
	return new_state
	

func emit_cue_node(target_time):
	print ("State: %s"%state_string(cue_emitter_state))
	
	var node_selector = rng.randi()%100
	
	var x = rng.randf() * 1.0 -0.5
	var y_hand = 1.0
	var y_head = 1.0
	var x_head = 0
	if cue_emitter_state == CUE_STATE_STAND:
		y_hand = player_height-0.2 + rng.randf() * 0.3
		y_head = player_height
		x = 0.2 + rng.randf() * 0.45
		x_head = rng.randf() - 0.5
	elif cue_emitter_state == CUE_STATE_SQUAT:
		y_head = player_height/2 + rng.randf() * 0.4
		y_hand = y_head + (rng.randf() * 0.4 - 0.2)
		x = 0.3 + rng.randf() * 0.45
		x_head = rng.randf() *0.6 - 0.3
	else:
		x_head = rng.randf() * 0.4
		y_head = 0.4 + rng.randf() * 0.5
		x = 0.3 + rng.randf() * 0.25
		x_head = rng.randf() *0.8 - 0.4
		y_hand = 0.3 + rng.randf() * 0.4
		if cue_emitter_state == CUE_STATE_CRUNCH:
			y_hand = 0.8 + rng.randf() * 0.4
			x = -0.225 + rng.randf() * 0.45

	var double_punch = cue_emitter_state == CUE_STATE_STAND && rng.randf() < 0.5
	var double_punch_delay = 0.25
	var dd_df = fly_distance/fly_time


	if not state_changed and cue_selector == CUE_SELECTOR_HAND and cue_emitter_state == CUE_STATE_CRUNCH:
		var spread = 0.2+rng.randf()*0.3
		create_and_attach_cue("right", x+spread,y_hand, target_time)
		create_and_attach_cue("left", x-spread,y_hand, target_time)
	elif not state_changed and cue_selector == CUE_SELECTOR_HAND and node_selector < 50:
		var n = create_and_attach_cue("right", x,y_hand, target_time)
		if double_punch:
			var n2 = create_and_attach_cue("right", x*rng.randf(),(y_hand+player_height*(0.5+rng.randf()*0.2))/2, target_time + double_punch_delay, -double_punch_delay*dd_df)
			n.activate_path_cue(n2)
	elif not state_changed and cue_selector == CUE_SELECTOR_HAND and node_selector >= 50:
		var n = create_and_attach_cue("left", -x,y_hand, target_time)
		if double_punch:
			var n2 = create_and_attach_cue("left", -x*rng.randf(),(y_hand+player_height*(0.5+rng.randf()*0.2))/2, target_time + double_punch_delay, -double_punch_delay*dd_df)
			n.activate_path_cue(n2)
	else:
		state_changed = false
		if cue_emitter_state == CUE_STATE_PUSHUP:
			create_and_attach_cue("head_inverted", x_head, y_head, target_time)
		else:
			create_and_attach_cue("head", x_head, y_head, target_time)

	if cue_selector == CUE_SELECTOR_HAND:
		if cue_emitter_state == CUE_STATE_STAND:
			if node_selector < 10:
				cue_selector = CUE_SELECTOR_HEAD
		elif cue_emitter_state == CUE_STATE_CRUNCH:
			if node_selector < 80:
				cue_selector = CUE_SELECTOR_HEAD
		elif node_selector < 30:
			cue_selector = CUE_SELECTOR_HEAD
	elif cue_selector == CUE_SELECTOR_HEAD:
		if cue_emitter_state == CUE_STATE_STAND:
			if node_selector < 50:
				cue_selector = CUE_SELECTOR_HAND
		elif cue_emitter_state == CUE_STATE_CRUNCH:
			if node_selector < 80:
				cue_selector = CUE_SELECTOR_HAND
		elif node_selector < 25:
			cue_selector = CUE_SELECTOR_HAND
			
	# Increase the cue speed for hand cues
	if cue_selector == CUE_SELECTOR_HAND:
		min_cue_space = level_min_cue_space / 2
	else:
		min_cue_space = level_min_cue_space
			
	if last_state_change + min_state_duration < cue_emitter.current_playback_time:
		var old_state = cue_emitter_state
		cue_emitter_state = state_transition(cue_emitter_state)
		if old_state != cue_emitter_state:
			#Emit a head cue if the state has changed
			state_changed = true
			last_state_change = cue_emitter.current_playback_time
			infolayer.print_info(state_string(cue_emitter_state).to_upper(), "main")
			get_node("PositionSign").start_sign(cue_emitter.translation, get_node("target").translation, emit_early)
			display_state(cue_emitter_state)

func _on_exit_button_pressed(body):
	emit_signal("level_finished")

func setup_multiplier(running_speed):
	var xx = get_node("RunIndicator")
	if running_speed > 13.5:
		xx.play("hyperspeed")
		run_point_multiplier = 4
	elif running_speed > 10:
		xx.play("runx3")
		run_point_multiplier = 3
	elif running_speed > 7:
		xx.play("runx2")
		run_point_multiplier = 2
	else:
		xx.stop()
		run_point_multiplier = 1

func get_points():
	return {"points": cue_emitter.points, "hits": cue_emitter.hits, "max_hits": cue_emitter.max_hits,"time": last_playback_time}
		
var gui_update = 0	
func _on_UpdateTimer_timeout():
	running_speed = self.get_parent().get_running_speed()
	setup_multiplier(running_speed)
	if gui_update % 10 == 0:
		self.update_info(cue_emitter.hits, cue_emitter.max_hits, cue_emitter.points)
	gui_update += 1


func _on_AudioStreamPlayer_finished():
	stream.stop()
	var t = Timer.new()
	t.connect("timeout", self, "_on_exit_timer_timeout")
	t.set_wait_time(5)
	self.add_child(t)
	t.start()
