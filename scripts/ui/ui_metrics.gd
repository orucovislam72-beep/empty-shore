class_name UiMetrics
extends RefCounted
## Перевод dp (density-independent pixels, как в Android) в единицы холста Godot.
## Минимальная зона нажатия по брифу — 48 dp.

const MIN_TOUCH_DP: float = 48.0
const DEFAULT_DPI: float = 160.0


## dp -> физические пиксели экрана.
static func dp_to_px(dp: float, dpi: float) -> float:
	var d: float = dpi if dpi > 0.0 else DEFAULT_DPI
	return dp * d / 160.0


## dp -> единицы холста при растяжении canvas_items.
## canvas_scale = во сколько раз холст растянут на экран (window_px / base_units).
static func dp_to_units(dp: float, dpi: float, canvas_scale: float) -> float:
	var s: float = canvas_scale if canvas_scale > 0.0 else 1.0
	return dp_to_px(dp, dpi) / s


## Минимальный размер кнопки в единицах холста (не меньше 48 dp и не меньше floor_units).
static func min_touch_units(dpi: float, canvas_scale: float, floor_units: float = 64.0) -> float:
	return maxf(dp_to_units(MIN_TOUCH_DP, dpi, canvas_scale), floor_units)
