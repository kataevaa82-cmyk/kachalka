# Качалка

3D-симулятор качалки для **Яндекс Игр**. Ассеты собираются в Blender 5.2, игра запускается в Godot 4.7.1 (Compatibility / WebGL 2.0).

Ходишь по залу, занимаешь станок, **жмёшь в такт**. Идеальные повторы дают массу, деньги и комбо. Руки героя растут в сессии (вид от первого лица). Энергия кончается — протеин, магазин или rewarded-ролик.

Станции: 15 тренажёров (жим, присед, гантели, турник, дорожка, велосипед, тяги, брусья, жим ногами, гребля, канаты, гири и другие).

Звук и музыка синтезируются самой игрой во время загрузки — аудиофайлов в репозитории нет.

Прогрессия: 6 уровней зала. После стартового подвала открываются ещё 5 этапов на 70 / 82 / 96 / 112 / 128 кг.

## Что нужно для разработки

- [Godot 4.7.1](https://godotengine.org/) с export templates
- [Blender 5.2](https://www.blender.org/) — только если пересобираете зал
- Git, опционально [GitHub CLI](https://cli.github.com/)

Клон:

```text
git clone https://github.com/kataevaa82-cmyk/kachalka.git
cd kachalka
```

## Запуск Godot

```text
godot --path godot
```

Главная сцена: `godot/scenes/boot/title.tscn`.

## Сборка ассетов (Blender)

Скрипт идемпотентный: чистит сцену, собирает зал и станки, пишет GLB в `blender/export/` и копирует их в `godot/assets/models/`.

```text
blender --background --python blender/scripts/build_gym.py
```

Масштаб: **1 BU = 1 m**. После копирования новых GLB удалите рядом лежащие `godot/assets/models/gym_*.glb.import`, чтобы Godot переимпортировал модели.

Руки от первого лица:

```text
blender --background --python blender/scripts/convert_fp_arms.py
```

Исходник рук: `blender/vendor/fp_arms/wrad/src/` (WRAD, CC0).

## Экспорт в Яндекс Игры

1. Установить export templates Godot 4.7.
2. Preset **YandexGamesWeb**, threads **Off**, custom HTML `godot/export/yandex_shell.html`.
3. Выход: `godot/export/web/index.html`.
4. В zip класть **содержимое** `web/` (`index.html` в корне архива).
5. Чеклист: `docs/YANDEX_GAMES.md`.

Windows-сборка: preset **Windows Desktop** → `godot/export/windows/Kachalka.exe`.

## Автопроверки

```text
godot --headless --path godot res://tools/smoke_scene.tscn
godot --headless --path godot res://tools/walk_scene.tscn
node tools/browser_smoke.mjs
```

Smoke-тест проверяет данные, GLB, синтез звука, миграцию сохранений и достижимость всех 6 уровней. Walk-тест строит сетку проходимости. Browser smoke гоняет Web-сборку с локальным mock Яндекс SDK. Chrome ищется автоматически (Windows / macOS / Linux), путь можно задать через `CHROME_PATH`.

## Языки

Русский и английский. Язык берётся из Яндекс SDK (`ysdk.environment.i18n.lang`): ru/be/kk/uk/uz — русский, остальные — английский. Новые строки пишутся по-русски; английский вариант — в `godot/data/i18n_en.json`.

## Управление

| | Desktop | Mobile |
|--|---------|--------|
| Ходьба | WASD | левый стик |
| Камера | мышь (клик — захват) | свайп справа |
| Занять станок | E | подсказка + E / тап зоны |
| Повтор | Пробел | кнопка ЖМИ |
| Пауза | Esc | кнопка II |

В паузе: таблица рекордов, титры, отключение звука и музыки.

## Структура

```
kachalka/
  blender/scripts/     сборка зала и рук
  blender/vendor/      Kenney (нужные GLB) + WRAD FPS arms
  docs/                GDD, пайплайн, Яндекс
  godot/               runnable-проект
  marketing/yandex/    карточка магазина
  marketing/source/    исходники обложек и скрипты пакета
  tools/               browser smoke
```

Документация продакшена: `docs/00_PRODUCTION_BRIEF.md`, `docs/GDD.md`, `docs/TECHNICAL.md`, `docs/ART_BIBLE.md`, `docs/ASSET_PIPELINE.md`, `docs/NAMING.md`, `docs/YANDEX_GAMES.md`.

Предпросмотр карточки Яндекс Игр: `marketing/yandex/preview.html`.

В репозиторий не входят: `godot/.godot/`, готовые `export/web` и `export/windows`, локальные exe.

## Сторонние ассеты

- Kenney Furniture Kit и Food Kit — [CC0](https://creativecommons.org/publicdomain/zero/1.0/)
- WRAD first-person arms — CC0, см. `blender/vendor/fp_arms/wrad/src/LICENSE.txt`
- Inter — SIL OFL, `godot/assets/fonts/LICENSE_Inter.txt`

Тексты лицензий попадают в сборку (`include_filter` содержит `*.txt`) и перечислены на экране «Титры» в паузе.
