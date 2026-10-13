# Сторонние компоненты и ассеты

Разрешены только лицензии MIT, Apache 2.0, BSD, CC0, OFL (см. `AGENTS.md`). Каждый компонент — отдельной строкой.

| Название | Автор | Ссылка | Лицензия | Где используется | Попадает в сборку |
|----------|-------|--------|----------|------------------|-------------------|
| Godot Engine 4.7.2 | Juan Linietsky, Ariel Manzur и участники Godot Engine | https://godotengine.org/license | MIT | движок | да |
| Open Sans (шрифт интерфейса по умолчанию, встроен в Godot) | The Open Sans Project Authors | https://github.com/googlefonts/opensans | OFL 1.1 | весь интерфейс | да (в составе движка) |
| GUT — Godot Unit Test 9.7.1 | Tom "Butch" Wesley и участники | https://github.com/bitwes/Gut | MIT | `addons/gut`, тесты | нет (исключён в пресетах экспорта) |
| Шрифты GUT: Anonymous Pro, Courier Prime, Lobster Two | авторы шрифтов, см. `addons/gut/fonts/OFL.txt` | https://github.com/bitwes/Gut/tree/main/addons/gut/fonts | OFL 1.1 | панель GUT в редакторе | нет |

Собственные ассеты проекта (созданы для «Пустого Берега»): иконка `assets/icons/app_icon.svg`, тема интерфейса
`assets/ui_theme.tres`, процедурные модели травы, деревьев и камней (генерируются кодом в `scripts/world/test_terrain.gd`).

Внешних моделей, текстур и звуков на этапе 0 нет.
