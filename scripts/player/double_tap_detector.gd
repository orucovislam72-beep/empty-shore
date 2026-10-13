class_name DoubleTapDetector
extends RefCounted
## Распознаёт «двойное нажатие на стик вперёд»: два толчка стика вперёд
## (пересечение порога снизу вверх) за короткое время. Без аллокаций.

var threshold: float = 0.8
var max_interval: float = 0.35

var _was_forward: bool = false
var _last_push_time: float = -1000.0


func reset() -> void:
	_was_forward = false
	_last_push_time = -1000.0


## forward_amount: 0..1 (насколько стик отклонён вперёд), now: время в секундах.
## Возвращает true в момент распознавания двойного толчка.
func update(forward_amount: float, now: float) -> bool:
	var is_forward: bool = forward_amount >= threshold
	var triggered: bool = false
	if is_forward and not _was_forward:
		if now - _last_push_time <= max_interval:
			triggered = true
			_last_push_time = -1000.0
		else:
			_last_push_time = now
	_was_forward = is_forward
	return triggered
