class_name ContainerView
extends Node3D
## Мешки с вещами и туши животных (WorldContainers, динамические контейнеры): MultiMesh на вид,
## перестраивается только по событию (появился/исчез), не каждый кадр. Точки лута рисует WorldStreamer по чанкам.

const POOL: int = 24

var _boxes: WorldContainers
var _mmis: Dictionary = {}


func bind(boxes: WorldContainers) -> void:
	_boxes = boxes
	boxes.dynamic_added.connect(_on_changed)
	boxes.dynamic_removed.connect(_on_changed)
	_rebuild()


func _on_changed(_handle: int) -> void:
	_rebuild()


func _mmi_for(kind: String) -> MultiMeshInstance3D:
	if _mmis.has(kind):
		return _mmis[kind]
	var mesh_id: String = kind.trim_prefix(WorldContainers.CORPSE_PREFIX)
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = WorldMeshes.get_mesh(mesh_id)
	mm.instance_count = POOL
	mm.visible_instance_count = 0
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.name = "Containers_" + kind
	mmi.multimesh = mm
	add_child(mmi)
	_mmis[kind] = mmi
	return mmi


func _rebuild() -> void:
	var counts: Dictionary = {}
	for k: Variant in _mmis:
		counts[k] = 0
	for j: int in _boxes.dynamic_count():
		var kind: String = _boxes.d_kind[j]
		var mmi: MultiMeshInstance3D = _mmi_for(kind)
		var n: int = int(counts.get(kind, 0))
		if n >= POOL:
			continue
		var b: Basis = Basis(Vector3.UP, _boxes.d_yaw[j])
		var p: Vector3 = _boxes.d_pos[j]
		if kind.begins_with(WorldContainers.CORPSE_PREFIX):
			# Туша лежит на боку.
			b = b * Basis(Vector3.BACK, PI * 0.5)
			p.y += 0.25
		mmi.multimesh.set_instance_transform(n, Transform3D(b, p))
		counts[kind] = n + 1
	for k2: Variant in _mmis:
		(_mmis[k2] as MultiMeshInstance3D).multimesh.visible_instance_count = int(counts.get(k2, 0))
