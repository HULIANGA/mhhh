class_name FieldArena
extends Node3D

const WAYPOINTS: Array[Vector3] = [Vector3(-8, 0, 0), Vector3(6, 0, -7), Vector3(8, 0, 6)]
var beacons: Array[Node3D] = []
var training_dummy: TrainingDummy
var breakable_obstacles: Array[BreakableObstacle] = []

func _ready() -> void:
	_build_lighting()
	training_dummy = TrainingDummy.new()
	training_dummy.position = Vector3(0, 0, 0)
	add_child(training_dummy)
	var ground_material := ShaderMaterial.new()
	ground_material.shader = preload("res://assets/ground.gdshader")
	_solid_box("Ground", Vector3(36, 0.6, 30), Vector3(0, -0.3, 0), ground_material)
	var wall_material := FieldGeometry.material(Color("344440"))
	_solid_box("NorthBoundary", Vector3(36, 0.85, 1), Vector3(0, 0.425, -14.5), wall_material)
	_solid_box("SouthBoundary", Vector3(36, 0.65, 1), Vector3(0, 0.325, 14.5), wall_material)
	_solid_box("WestBoundary", Vector3(1, 0.85, 28), Vector3(-17.5, 0.425, 0), wall_material)
	_solid_box("EastBoundary", Vector3(1, 0.85, 28), Vector3(17.5, 0.425, 0), wall_material)
	_solid_box("CentralMonolith", Vector3(2.4, 2.8, 2.4), Vector3(-3.0, 1.4, -1.0), FieldGeometry.material(Color("3e504c")))
	var wood := FieldGeometry.material(Color("8a6545"))
	_breakable_box(Vector3(-9.0, 0.0, -7.0), Vector3(2.6, 1.55, 0.7), wood)
	_breakable_box(Vector3(10.0, 0.0, -8.0), Vector3(0.7, 1.55, 2.6), wood)
	_breakable_box(Vector3(-11.0, 0.0, 8.5), Vector3(2.6, 1.55, 0.7), wood)
	var stone := FieldGeometry.material(Color("51605a"))
	var trim := FieldGeometry.material(Color("81907a"))
	# M1 route markers remain as dim landmarks around the M2 combat lane.
	var amber := FieldGeometry.material(Color("816f50"), 0.18)
	for i in range(9):
		var x := -16.0 + i * 4.0
		for z in [-13.8, 13.8]:
			FieldGeometry.box(self, Vector3(0.6, 1.3, 0.6), Vector3(x, 0.65, z), stone)
			FieldGeometry.box(self, Vector3(0.73, 0.15, 0.73), Vector3(x, 1.35, z), trim)
	for x in [-16.0, 16.0]:
		for z in [-10.0, 0.0, 10.0]:
			FieldGeometry.box(self, Vector3(0.4, 1.8, 0.4), Vector3(x, 0.9, z), stone)
			FieldGeometry.box(self, Vector3(0.5, 0.17, 0.5), Vector3(x, 1.9, z), amber)
	for i in WAYPOINTS.size():
		var beacon := Node3D.new()
		add_child(beacon)
		beacon.position = WAYPOINTS[i]
		beacons.append(beacon)
		FieldGeometry.ring(beacon, 1.05, 0.055, Vector3(0, 0.055, 0), amber)
		FieldGeometry.box(beacon, Vector3(0.25, 0.03, 0.25), Vector3(0, 0.04, 0), amber)
		var label := Label3D.new()
		label.text = "0%d" % (i + 1)
		label.font_size = 64
		label.pixel_size = 0.008
		label.modulate = Color("e6c998")
		label.position = Vector3(0, 0.8, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		beacon.add_child(label)
	# Peripheral rocks are decorative; keep the first movement exercise unobstructed.
	var random := RandomNumberGenerator.new()
	random.seed = 12843
	for i in range(22):
		var x := random.randf_range(-16, 16)
		var z := random.randf_range(-13, -11) if i % 2 == 0 else random.randf_range(11, 13)
		var mesh := SphereMesh.new()
		mesh.radius = random.randf_range(0.35, 0.85)
		mesh.height = mesh.radius * 1.4
		mesh.radial_segments = 5
		mesh.rings = 3
		var rock := FieldGeometry.instance(self, mesh, Vector3(x, 0.22, z), stone)
		rock.scale = Vector3(1.3, 0.8, 1)
		rock.rotation.y = random.randf_range(0, TAU)

func _solid_box(node_name: String, dimensions: Vector3, at: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	add_child(body)
	body.position = at
	var shape := BoxShape3D.new()
	shape.size = dimensions
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	FieldGeometry.box(body, dimensions, Vector3.ZERO, material)

func _breakable_box(at: Vector3, dimensions: Vector3, material: Material) -> void:
	var obstacle := BreakableObstacle.new()
	obstacle.position = at
	add_child(obstacle)
	obstacle.setup(dimensions, material)
	breakable_obstacles.append(obstacle)

func reset_obstacles() -> void:
	for obstacle in breakable_obstacles:
		obstacle.reset_obstacle()

func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("132328")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bdd8cf")
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color("ffe4ba")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
