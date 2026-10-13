class_name ProjectileView
extends Node3D
## Отрисовка снарядов (Projectiles): один MultiMesh на все стрелы и пули, позиции каждый кадр.

var _sim: Projectiles
var _mmi: MultiMeshInstance3D


func bind(sim: Projectiles) -> void:
	_sim = sim
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = WorldMeshes.get_mesh("arrow")
	mm.instance_count = Projectiles.MAX
	mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Projectiles"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)


func _process(_delta: float) -> void:
	if _sim == null:
		return
	var mm: MultiMesh = _mmi.multimesh
	var n: int = _sim.count()
	for i: int in n:
		var v: Vector3 = _sim.velocities[i]
		var b: Basis = Basis.IDENTITY
		if v.length_squared() > 0.01:
			var up: Vector3 = Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT
			b = Basis.looking_at(v, up)
		mm.set_instance_transform(i, Transform3D(b, _sim.positions[i]))
	mm.visible_instance_count = n
