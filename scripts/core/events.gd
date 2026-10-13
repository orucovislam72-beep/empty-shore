extends Node
## Шина событий (autoload «Events»). Узлы общаются через сигналы, а не через жёсткие ссылки.

## Настройки изменились и уже применены к движку (FPS, масштаб). Сцены применяют свою часть.
signal settings_changed
## Автоснижение качества сработало; preset_name — новый пресет или "custom".
signal quality_auto_lowered(preset_name: String)
## Показать короткое сообщение игроку (текст — ключ перевода или готовая строка).
signal toast_requested(text: String)
## Свайп обзора с сенсорной панели, в пикселях экрана.
signal look_input(relative: Vector2)
## Автобег включён/выключен.
signal autorun_changed(enabled: bool)
## Просьба переключить автобег (двойное нажатие на стик или кнопка геймпада).
signal autorun_toggle_requested
## Просьба открыть/закрыть меню паузы.
signal pause_requested
## Переключить отладочную панель.
signal debug_overlay_toggled
## Персонаж смотрит на объект, который можно взять (пустая строка — ничего).
signal interact_target_changed(label: String)
