extends SceneTree

## The garage radio's station list, and the dial math that puts a frequency under the pointer.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	var stations: Array = state.get("RADIO_STATIONS")
	assert(stations.size() == 2)
	var all: Dictionary = stations[0]
	var originals: Dictionary = stations[1]
	assert(str(all["id"]) == "all")
	assert(is_equal_approx(float(all["frequency"]), 620.0))
	assert(str(originals["id"]) == "originals")
	assert(is_equal_approx(float(originals["frequency"]), 830.0))
	var memory: Array = state.get("RADIO_MEMORY")
	assert(memory.size() == 5)
	assert(is_equal_approx(float(memory[0]), float(all["frequency"])))
	var all_songs: Array = all["songs"]
	assert(all_songs.size() == 7)
	assert(str(all_songs[0]).ends_with("garage.mp3"))
	assert(str(all_songs[1]).ends_with("race.mp3"))
	assert(str(all_songs[2]).ends_with("sr1-1.mid"))
	assert(str(all_songs[6]).ends_with("sr1-5.mid"))
	var original_songs: Array = originals["songs"]
	assert(original_songs.size() == 5)
	assert(str(original_songs[0]).ends_with("sr1-1.mid"))
	assert(str(original_songs[4]).ends_with("sr1-5.mid"))
	var midi := load("res://scripts/midi_song.gd").call("stream", str(original_songs[0])) as AudioStreamWAV
	assert(midi != null)
	assert(midi.mix_rate == 22050)
	var midi_seconds := float(midi.data.size() / 2) / float(midi.mix_rate)
	assert(midi_seconds > 60.0 and midi_seconds < 66.0)
	assert(absi(midi.data.decode_s16(200)) > 1000)
	var tone := _square_midi()
	var tone_path := "/tmp/radio-tone-%d.mid" % Time.get_ticks_usec()
	var tone_file := FileAccess.open(tone_path, FileAccess.WRITE)
	assert(tone_file != null)
	tone_file.store_buffer(tone)
	tone_file.close()
	var tone_wav := load("res://scripts/midi_song.gd").call("stream", tone_path) as AudioStreamWAV
	assert(tone_wav != null)
	var tone_frames := tone_wav.data.size() / 2
	assert(tone_frames > 11000 and tone_frames < 11050)
	assert(tone_wav.data.decode_s16(0) > 1000)
	assert(tone_wav.data.decode_s16(100) < -1000)
	assert(str((state.call("radio_station_at", 620.0) as Dictionary)["id"]) == "all")
	assert(str((state.call("radio_station_at", 840.0) as Dictionary)["id"]) == "originals")
	assert((state.call("radio_station_at", 1000.0) as Dictionary).is_empty())
	assert(is_equal_approx(float(state.call("radio_memory_frequency", 1)), 620.0))
	assert(is_equal_approx(float(state.call("radio_memory_frequency", 2)), float(memory[1])))
	assert(float(state.call("radio_memory_frequency", 6)) < 0.0)

	var face: Script = load("res://scripts/radio.gd")
	assert(is_equal_approx(float(face.call("dial_shift", 540.0, 540.0, 1600.0, 2100.0, 640.0)), 320.0))
	assert(is_equal_approx(float(face.call("dial_shift", 1600.0, 540.0, 1600.0, 2100.0, 640.0)), 320.0 - 2100.0))

	var empty_path := "/tmp/radio-empty-%d.json" % Time.get_ticks_usec()
	var empty_file := FileAccess.open(empty_path, FileAccess.WRITE)
	assert(empty_file != null)
	empty_file.store_string('{"songs":[{"id":"garage","file":"garage.mp3"},{"id":"sr1-1","file":"sr1-1.mid"},{"id":"race","file":"race.mp3"}],"stations":[{"id":"fresh","frequency":700,"songs":[]}],"memory":[700,800,900,1000,1100]}')
	empty_file.close()
	var fresh: Dictionary = load("res://scripts/radio_register.gd").call("load_path", empty_path)
	assert((fresh["errors"] as Array).is_empty())
	var fresh_songs: Array = (fresh["stations"] as Array)[0]["songs"]
	assert(fresh_songs.size() == 3)
	assert(str(fresh_songs[0]).ends_with("garage.mp3"))
	assert(str(fresh_songs[1]).ends_with("sr1-1.mid"))
	assert(str(fresh_songs[2]).ends_with("race.mp3"))
	assert((fresh["memory"] as Array).size() == 5)
	assert(is_equal_approx(float((fresh["memory"] as Array)[0]), 700.0))

	var listed_path := "/tmp/radio-listed-%d.json" % Time.get_ticks_usec()
	var listed_file := FileAccess.open(listed_path, FileAccess.WRITE)
	assert(listed_file != null)
	listed_file.store_string('{"songs":[{"id":"garage","file":"garage.mp3"},{"id":"race","file":"race.mp3"}],"stations":[{"id":"one","frequency":900,"songs":["garage"]},{"id":"two","frequency":910,"songs":["race","missing"]}],"memory":[900,"nope",2000]}')
	listed_file.close()
	var listed: Dictionary = load("res://scripts/radio_register.gd").call("load_path", listed_path)
	var listed_errors: Array = listed["errors"]
	assert(listed_errors.size() >= 3)
	var listed_stations: Array = listed["stations"]
	assert(listed_stations.size() == 2)
	assert((listed_stations[0]["songs"] as Array).size() == 1)
	var listed_memory: Array = listed["memory"]
	assert(listed_memory.size() == 5)
	assert(is_equal_approx(float(listed_memory[0]), 900.0))
	assert(is_equal_approx(float(listed_memory[1]), 540.0))
	assert(is_equal_approx(float(listed_memory[2]), 1600.0))

	var save_dir := "/tmp/radio-garage-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.set("save_dir", save_dir)
	state.set("legacy_save_path", "")
	var before_time := float(state.get("_radio_time"))
	var before: Dictionary = state.call("_broadcast_at", "all")
	state.call("set_radio_frequency", float(memory[1]))
	state.call("new_game")
	assert(int(state.get("radio_preset")) == 1)
	assert(is_equal_approx(float(state.get("radio_frequency")), float(memory[0])))
	assert(is_equal_approx(float(state.get("_radio_time")), before_time))
	var opened: Dictionary = state.call("_broadcast_at", "all")
	assert(str(opened["path"]) == str(before["path"]))
	assert(is_equal_approx(float(opened["offset"]), float(before["offset"])))
	assert(str(opened["path"]).ends_with("garage.mp3"))
	state.set("radio_frequency", 1000.0)
	var garage := (load("res://scenes/garage.tscn") as PackedScene).instantiate()
	root.add_child(garage)
	current_scene = garage
	await process_frame
	await physics_frame
	garage.call("_fit_view_above_status")
	garage.call("_bring_radio_forward")
	garage.set("_radio_blend", 1.0)
	garage.call("_update_radio_transform")
	await process_frame
	await physics_frame

	var cam := garage.get("_camera") as Camera3D
	var tune := garage.get_node("InteractDesk/Shelf/Radio/Face/Tune") as Node3D
	var power := garage.get_node("InteractDesk/Shelf/Radio/Face/Power") as Node3D
	var memory_button := garage.get_node("InteractDesk/Shelf/Radio/Face/Memory1") as Node3D
	assert(garage.call("_radio_hit", cam.unproject_position(tune.global_position)) == "tune")
	assert(garage.call("_radio_hit", cam.unproject_position(power.global_position)) == "power")
	assert(garage.call("_radio_hit", cam.unproject_position(memory_button.global_position)) == "1")
	var memory_last := garage.get_node("InteractDesk/Shelf/Radio/Face/Memory5") as Node3D
	assert(power.get_node_or_null("Mark") != null)
	assert(power.get_node_or_null("Lever") == null)
	assert((memory_button.get_node("Caption") as Label3D).text == "1")
	assert((memory_button.get_node("Caption") as Label3D).position.y < -0.02)
	var memory_next := garage.get_node("InteractDesk/Shelf/Radio/Face/Memory2") as Node3D
	var preset_step := memory_button.position.x - memory_next.position.x
	assert(preset_step < 0.022)
	assert(is_equal_approx(power.get_node("Mark").position.y, (memory_button.get_node("Caption") as Node3D).position.y))
	assert(is_equal_approx(power.get_node("Mark").position.y, tune.get_node("Mark").position.y))
	assert(memory_button.position.x > memory_last.position.x)
	assert(memory_last.position.x > tune.position.x)
	var volume := garage.get_node("InteractDesk/Shelf/Radio/Face/Volume") as Node3D
	assert(power.position.x > volume.position.x)
	assert(volume.position.x > memory_button.position.x)
	var tune_hit := ((tune.get_node("Hit") as CollisionShape3D).shape as BoxShape3D).size.x
	var volume_hit := ((volume.get_node("Hit") as CollisionShape3D).shape as BoxShape3D).size.x
	assert(tune_hit > volume_hit * 1.5)
	assert(volume.get_node_or_null("Mark") != null)
	assert(tune.get_node_or_null("Mark") != null)
	var power_icon := ((power.get_node("Mark") as MeshInstance3D).material_override as StandardMaterial3D).albedo_texture as ImageTexture
	assert(power_icon.get_image().get_pixel(32, 20).a > 0.5)
	assert(garage.call("_radio_hit", cam.unproject_position(volume.global_position)) == "volume")
	var kept_volume := float(state.get("music_volume"))
	state.call("set_music_volume", 0.4)
	# process_frame resumes before _process, so the knob turns on the frame after.
	await process_frame
	await process_frame
	var spin := volume.get_node("Spin") as Node3D
	assert(is_equal_approx(spin.rotation.z, 0.4 * 4.8))
	var music := state.get_node("MusicPlayer") as AudioStreamPlayer
	assert(is_equal_approx(music.volume_db, linear_to_db(0.4)))
	state.call("set_music_dimmed", true)
	assert(is_equal_approx(music.volume_db, linear_to_db(0.4) - 16.0))
	state.call("set_music_dimmed", false)
	state.call("set_music_volume", kept_volume)
	assert(is_equal_approx(float(state.get("radio_frequency")), 1000.0))
	garage.call("_press_radio_memory", 1)
	await create_timer(0.7).timeout
	assert(is_equal_approx(float(state.get("radio_frequency")), 620.0))
	assert(int(state.get("radio_preset")) == 1)
	garage.call("_press_radio_memory", 2)
	await create_timer(0.7).timeout
	assert(is_equal_approx(float(state.get("radio_frequency")), float(memory[1])))
	garage.call("_drag_radio", 10.0)
	assert(is_equal_approx(float(state.get("radio_frequency")), float(memory[1]) + 22.0))
	state.call("_reset_radio_broadcast", 99)
	var first: Dictionary = state.call("_broadcast_at", "all")
	assert(not first.is_empty())
	var pos0 := float(first["start"]) + float(first["offset"])
	state.set("_radio_time", float(state.get("_radio_time")) + 5.0)
	var later: Dictionary = state.call("_broadcast_at", "all")
	var pos1 := float(later["start"]) + float(later["offset"])
	assert(is_equal_approx(pos1, pos0 + 5.0))
	var nxt: Dictionary = state.call("_broadcast_after", "all", float(first["start"]))
	assert(str(nxt["path"]) != str(first["path"]))
	var originals_now: Dictionary = state.call("_broadcast_at", "originals")
	assert(str(originals_now["path"]).ends_with(".mid"))
	state.set("music_enabled", true)
	state.call("set_radio_frequency", 1000.0)
	assert(int(state.get("radio_preset")) == 0)
	assert(str(state.get("_music_track")) == "radio-static")
	var player := state.get_node("MusicPlayer") as AudioStreamPlayer
	assert(player.stream is AudioStreamGenerator)
	assert(player.playing)
	var low: PackedFloat32Array = state.call("_static_preview", 700.0)
	var high: PackedFloat32Array = state.call("_static_preview", 1500.0)
	var again: PackedFloat32Array = state.call("_static_preview", 700.0)
	assert(not is_equal_approx(low[8], high[8]))
	assert(is_equal_approx(low[8], again[8]))
	state.call("set_radio_frequency", 620.0)
	var on_air: Dictionary = state.call("_broadcast_at", "all")
	assert(str(state.get("_music_track")) == str(on_air["path"]))
	assert(str(state.get("_music_station")) == "all")
	assert(state.call("save_game", 1))
	state.call("set_radio_frequency", float(memory[1]))
	assert(int(state.get("radio_preset")) == 2)
	assert(state.call("save_game", 1))
	state.call("set_radio_frequency", 1000.0)
	assert(state.call("load_game", 1))
	assert(int(state.get("radio_preset")) == 2)
	assert(is_equal_approx(float(state.get("radio_frequency")), float(memory[1])))

	print("radio register ok")
	quit(0)


## One beat of A4, 120 bpm, 480 ticks to a quarter note. Half a second of square wave.
func _square_midi() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.append_array("MThd".to_utf8_buffer())
	for b: int in [0, 0, 0, 6, 0, 0, 0, 1, 1, 224]:
		bytes.append(b)
	var track := PackedByteArray()
	for b: int in [0, 0xff, 0x51, 3, 0x07, 0xa1, 0x20, 0, 0x90, 69, 100, 0x83, 0x60, 0x80, 69, 0, 0, 0xff, 0x2f, 0]:
		track.append(b)
	bytes.append_array("MTrk".to_utf8_buffer())
	bytes.append(0)
	bytes.append(0)
	bytes.append((track.size() >> 8) & 0xff)
	bytes.append(track.size() & 0xff)
	bytes.append_array(track)
	return bytes
