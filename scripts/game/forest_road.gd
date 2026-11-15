extends "res://scripts/game/test_cave.gd"
## An outdoor level built from data/maps/<MAP>.json by TerrainBuilder: the same
## party, camera, combat and interface as the cave test, in daylight.

const MAP := "triboar_trail"


func _build_world() -> void:
	cave = TerrainBuilder.new()
	add_child(cave)
	cave.build(MAP)


func _hero_starts() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in cave.map.get("party", []):
		out.append(Vector3(p[0], 0, p[1]))
	return out


func _hero_lamps() -> bool:
	return false


func _spawn_monsters() -> void:
	for m in cave.map.get("monsters", []):
		var at: Array = m.get("at", [0, 0])
		var g := _spawn_unit(Vector3(at[0], 0, at[1]))
		g.setup_monster(str(m.get("id", "goblin")))
		g.rotation.y = PI


func _camera_start_offset() -> Vector3:
	return Vector3(0, 0, -4)


func _intro() -> void:
	for line in cave.map.get("intro", []):
		log_line("[i]%s[/i]" % line if not str(line).begins_with("[") else str(line))


func _setup_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = load("res://assets/nature/hdri/kloofendal_48d_partly_cloudy_puresky_2k.hdr")
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.72
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.68, 0.72)
	env.fog_density = 0.0025
	env.fog_aerial_perspective = 0.5
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
