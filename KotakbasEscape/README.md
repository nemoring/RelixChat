# Котакбас побег от ТЦК

**Kotakbas Studio** · «Игра, которую никто не просил»

Абсурдная сатирическая Android-игра на Godot 4.4 (GDScript, Compatibility renderer / OpenGL ES 3.0) из трёх связанных глав:

1. **Обычное утро Котакбаса** — 2D визуальная новелла (6 локаций, диалоги с печатью по буквам, портреты с эмоциями, журнал, пропуск прочитанного, авто-режим, выборы с таймером, подозрение, 7 вариантов при стуке в дверь, кат-сцена прыжка из окна).
2. **БЕГИ, КОТАКБАС!** — 3D-раннер с конечной целью (2000 / 5000 / 10000 / 20000 очков), 8 сменяющихся локаций, генератор препятствий с гарантией проходимости, бонусы (пряник, кроссовки, шлем, голубь, магнит, Nokia), чекпоинты, «упоротые» анимации (ноги-пропеллер, сальто 720°, плоский подкат «как PNG», T-pose, ragdoll).
3. **Лес Котакбаса** — 3D-выживание в открытом мире 512×512 м с подгрузкой участков: лес, болото, река, деревня, завод, пещера, холмы, поляна; голод/жажда/выносливость/температура, крафт с очередью, 13 видов построек, день/ночь (сутки = 24 мин), погода, животные и враги, NPC, 12 сюжетных заданий, финал с титрами и сценой с Интерполом.

### НЛО ТЦК
Каждые 1,5–2 игровых дня (по игровому времени, с учётом сна; таймер сохраняется) над базой появляется тарелка с надписью «ТЦК»: предупреждения за 30 и 10 игровых минут, облёт, луч захвата, **реальная кража** ресурсов (сначала ящики, потом инвентарь игрока в луче; сюжетные предметы и ящики у бункера защищены, доля кражи зависит от сложности). Прогнать её можно только камнями — физическими снарядами (RigidBody3D) — **в кабину** (отдельный CollisionShape3D; удары по корпусу отскакивают): 10 / 13 / 17 / 20 попаданий. Прицел, видимая траектория, «умный бросок» с упреждением, груды камней во время налёта — безвыходных ситуаций нет.

## Структура
```
scenes/    intro, menu, difficulty, novel, runner, survival, ending
scripts/   core (GameManager, SaveManager, DifficultyManager, AudioManager, SceneManager, Settings…)
           novel, runner, survival, ai, inventory, crafting, building, ufo (UFOController,
           UFOSpawnManager, UFOResourceStealing, UFOHealth, StoneProjectile, UFOAttackUI), ending, ui
resources/ items, recipes, difficulty      shaders/  glitch, ufo_beam, water
assets/    audio (сгенерировано tools/gen_audio.py), textures/icons (tools/gen_images.py), fonts (OFL)
localization/  английский перевод интерфейса      tests/  автотесты
```

## Тесты
```
godot --headless --path . res://tests/run_tests.tscn        # юнит-тесты логики (228 проверок)
godot --headless --path . res://tests/ufo_combat_test.tscn  # бой с НЛО на всех сложностях
godot --headless --path . res://tests/flow_test.tscn        # сквозной: новелла → раннер → выживание → сохранение
godot --headless --path . res://tests/compile_all.tscn      # компиляция всех скриптов
```
Отладка (только debug-сборка): пауза → «Вызвать НЛО сейчас», ресурсы, ускорение времени, пропуск главы/задания.

## Сборка Android
Нужны: Godot 4.4.1 + export templates, OpenJDK 17, Android SDK (build-tools с apksigner, platform-tools).
```
tools/build_android.sh debug      # build/KotakbasEscape-debug.apk (arm64-v8a)
tools/build_android.sh release    # нужен свой ключ: GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD
tools/build_android.sh aab        # Android App Bundle: нужен Gradle build template и полный Android SDK (platform 34)
```
Идентификатор `com.kotakbasstudio.escape` меняется в `export_presets.cfg` (`package/unique_name`).
Разрешения: только вибрация. Ни сети, ни рекламы, ни аналитики — игра работает офлайн.
