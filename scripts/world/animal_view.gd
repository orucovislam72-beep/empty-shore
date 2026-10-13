class_name AnimalView
extends Node3D
## Отрисовка животных (AnimalSim): MultiMesh на вид (пул POOL экземпляров, 1 draw call на вид),
## позиции пишутся каждый кадр без выделения памяти; при ходьбе — лёгкое покачивание.

const POOL: int = 16

var _sim: AnimalSim
var _mmis: Array[MultiMeshInstance3D] = []
var _counts: PackedInt32Array = PackedInt32Array()
var _time: float = 0.0


func bind(sim: AnimalSim) -> void:
	_sim = sim
	for id: String in sim.kind_ids:
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = WorldMeshes.get_mesh(id)
		mm.instance_count = POOL
		mm.visible_instance_count = 0
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.name = "Animals_" + id
		mmi.multimesh = mm
		add_child(mmi)
		_mmis.append(mmi)
	_counts.resize(sim.kind_ids.size())


func set_draw_distance(distance: float) -> void:
	for mmi: MultiMeshInstance3D in _mmis:
		mmi.visibility_range_end = distance


func _process(delta: float) -> void:
	if _sim == null:
		return
	_time += delta
	_counts.fill(0)
	for i: int in _sim.count():
		var k: int = _sim.kinds[i]
		var n: int = _counts[k]
		if n >= POOL:
			continue
		var p: Vector3 = _sim.positions[i]
		if _sim.speeds[i] > 0.0:
			p.y += absf(sin(_time * _sim.speeds[i] * 2.2 + float(i))) * 0.06
		_mmis[k].multimesh.set_instance_transform(n, Transform3D(Basis(Vector3.UP, _sim.yaws[i]), p))
		_counts[k] = n + 1
	for k2: int in _mmis.size():
		_mmis[k2].multimesh.visible_instance_count = _counts[k2]
