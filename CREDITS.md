# Сторонние компоненты и ассеты

Разрешены только лицензии MIT, Apache 2.0, BSD, CC0, OFL (см. `AGENTS.md`). Каждый компонент — отдельной строкой.

| Название | Автор | Ссылка | Лицензия | Где используется | Попадает в сборку |
|----------|-------|--------|----------|------------------|-------------------|
| Godot Engine 4.7.2 | Juan Linietsky, Ariel Manzur и участники Godot Engine | https://godotengine.org/license | MIT | движок | да |
| Open Sans (шрифт интерфейса по умолчанию, встроен в Godot) | The Open Sans Project Authors | https://github.com/googlefonts/opensans | OFL 1.1 | весь интерфейс | да (в составе движка) |
| GUT — Godot Unit Test 9.7.1 | Tom "Butch" Wesley и участники | https://github.com/bitwes/Gut | MIT | `addons/gut`, тесты | нет (исключён в пресетах экспорта) |
| Шрифты GUT: Anonymous Pro, Courier Prime, Lobster Two | авторы шрифтов, см. `addons/gut/fonts/OFL.txt` | https://github.com/bitwes/Gut/tree/main/addons/gut/fonts | OFL 1.1 | панель GUT в редакторе | нет |

| Иконка приложения «топор в скале и волна» (`assets/icons/source/icon_*.png`, производные `assets/icons/app_icon_*.png`, `adaptive_*_432.png`) | сгенерирована для проекта: Viktor AI image generation (модель gpt-image-2.5-sunburst, OpenAI GPT Image); уменьшение — Pillow (LANCZOS) | https://openai.com/policies/terms-of-use | собственная иконка проекта (сгенерирована по заказу; права на выход — у пользователя по условиям OpenAI), см. `docs/LICENSES.md` | иконка проекта и Android (обычная и адаптивная) | да |

Собственные ассеты проекта (созданы для «Пустого Берега», без сторонних источников):
- тема интерфейса `assets/ui_theme.tres`;
- иконки предметов `assets/icons/items/*.svg` и показателей `assets/icons/hud/*.svg` — нарисованы вручную в SVG (плоский стиль);
- процедурные модели: трава, вода (`scripts/world/test_terrain.gd`), деревья, камни, рудные камни, кусты
  (`scripts/world/resource_view.gd`), костёр и верстак (`scripts/world/deployable_view.gd`), топор и кирка в руке
  (`scripts/player/held_item_view.gd`) — строятся кодом из примитивов Godot.

Внешних моделей, текстур и звуков на этапе 1 нет. Иконка этапа 0 (`app_icon.svg`) заменена сгенерированной иконкой.
