# Godot-клиент (`game/`)

Каркас v0.4.0: меню, настройки, сейвы, связь с мастером, черновой экран игры с чатом и dev-инструменты. Правила, персонаж и мир переезжают из прототипа в v0.5.x ([roadmap](../production/roadmap.md)). Решения: [ADR-0007](adr/0007-godot-client-python-llm-backend.md) (Godot владеет UI, состоянием, сейвами и правилами), [ADR-0008](adr/0008-engine-decides-llm-narrates.md), [ADR-0009](adr/0009-godot-backend-protocol.md). Соглашения — по образцу `hive_world_shop`, свод — скилл `godot_conventions`.

## Структура

```
game/
  project.godot           1920×1080, canvas_items + expand, окно 1600×900 (мин. 1280×720), GL Compatibility
  main.tscn + main.gd     единственная сцена: тема, тост, переключение экранов по EventBus.navigate
  autoload/
    event_bus.gd          только сигналы
    catalog.gd            data/*.json
    save_manager.gd       слоты, профили (--profile), настройки окна
    backend.gd            связь с мастером: BackendClient, журнал протокола, engine.*, диагностика
    game_state.gd         текущая сессия и цикл хода
    dev.gd                консоль, F3, F12
    launch_args.gd        флаги после `--` в виде --name=value
  core/                   чистый слой: RefCounted, без нод, autoload-ов и tr()
    net/                  BackendConfig, JsonRpcPeer, RpcCall, BackendClient, ProtocolLog (спайк связи)
    session/game_session.gd   seed, RNG, счётчики, чат
    save/save_format.gd       SAVE_VERSION, migrate()
    rules/check_engine.gd     engine.check: DC, d20, преимущество, nat 20/1
  ui/
    ui_theme.gd           тема «тёмная книга»: цвета, шрифты, вариации
    game_entry.gd         вход в игру только при живом мастере
    screens/              main_menu, slots_screen, settings_screen, offline_screen, game_screen
    components/           chat_view, check_card, backend_status, pause_menu, toast
    dev/                  dev_console, dev_overlay
  data/                   rules.json (лестница DC, навыки), game.json (слоты, чат, окно)
  localization/strings.csv   ключи и ru (en — позже); *.translation генерируются при импорте
  assets/fonts/           Literata (текст мастера), Inter (интерфейс) — OFL, кириллица и стрелки
  test/                   gdUnit4: core/, saves/, fixtures/saves/save_v<N>.json
  tools/                  connectivity_check.gd, playtest/ (живые сценарии)
  addons/gdUnit4/         сторонний код, не править
```

## Поток экранов

`MainMenu` → «Новая игра» / «Продолжить» / «Загрузить» идут через `GameEntry.enter()`: если мастер не на связи, открывается `OfflineScreen`. Он называет причину и сам продолжает, когда связь появится. Меню, настройки и список сейвов работают без мастера.

`GameScreen` — лента слева (наррация, реплики игрока, карточки бросков, системные сообщения), варианты-кнопки и ввод, справа панель-заглушка персонажа и статус мастера. Пока мастер думает или связи нет, ввод заблокирован. Esc открывает паузу: сохранить, загрузить, настройки, выход в меню.

## Ход

`GameState.submit(text)` → `turn.request` (`turn_id` = `t-N`, `mode=exploration`, `kind=action`, снимок с последними репликами) → бэкенд может вызвать `engine.check` → `GameState.handle_engine_check()` бросает через `CheckEngine` с RNG сессии и кладёт карточку в чат → `turn.result`: наррация и варианты → автосейв. Новая игра начинается ходом `kind=enter`.

Ошибка, отмена или таймаут — системное сообщение «мир не изменился» и кнопка «Повторить ход». Повтор — новый `turn_id` ([ADR-0009 §5](adr/0009-godot-backend-protocol.md)). Бонус к проверкам — 0, пока нет персонажа (v0.5.0).

## Связь с мастером

- Адрес, токен и корневой сертификат — в «Настройки → Мастер». Сохраняются в `backend.cfg` профиля, вне репозитория. Env `BTR_BACKEND_TOKEN` и флаги `--backend-url` / `--backend-ca` перекрывают файл. Токен не передаётся аргументом: он виден в списке процессов.
- `Backend` подключается при старте и переподключается сам (1 → 30 с). Статус — точка в меню, в настройках и на экране игры.
- **Диагностика** ([ADR-0009 §9](adr/0009-godot-backend-protocol.md)): сокет не различает «сервер лежит», HTTP 401 и ошибку TLS, поэтому `Backend.request_diagnosis()` делает `GET /healthz` с теми же настройками TLS. Нет ответа — сервер не запущен; ошибка TLS — сертификат; `/healthz` отвечает, а сокет нет — токен.
- Журнал протокола: `<профиль>/logs/protocol.jsonl`, прошлый запуск — `protocol.prev.jsonl`.

## Сейвы

- `<профиль>/saves/slot_1..10.json` и `autosave.json` (после каждого удачного хода). Запись атомарная: временный файл, потом замена.
- Формат: `{save_version, game_version, saved_at, meta, session}`. `meta` (ходы, превью, дата начала) — для списка слотов. `session` — `GameSession.to_dict()`: seed, состояние RNG строкой (64 бита), счётчики, чат (последние 500 записей), варианты.
- **Версии:** `SaveFormat.SAVE_VERSION = 1`. Изменился формат `session` — поднять версию, добавить шаг в `SaveFormat.MIGRATIONS` и фикстуру `test/fixtures/saves/save_v<N>.json`. Старые шаги и фикстуры не удалять. Сейв новее игры не грузится (`MSG_SAVE_TOO_NEW`).
- JSON возвращает числа как float; `GameSession.from_dict` приводит целые поля обратно.

## Профили и пути

Без флагов всё лежит в `%APPDATA%/Godot/app_userdata/Between the Rolls/`. С `--profile=<имя>` сейвы, настройки, `backend.cfg`, логи и снимки багов — в `profiles/<имя>/`. Живые сценарии запускаются только с `--profile=agent` и чистят его сейвы.

## Dev-инструменты

Включены в debug-сборке или с `--dev`.

| Клавиша / флаг | Что |
|---|---|
| `~` | консоль: `help`, `backend`, `reconnect`, `say <текст>`, `retry`, `cancel`, `save <слот>`, `load <слот>`, `seed`, `snapshot`, `clear` |
| F3 | оверлей: FPS, состояние связи, модель, ход в полёте, задержки, seed и счётчики |
| F12 | снимок бага в `<профиль>/bugs/<время>/`: сейв, скриншот, хвост журнала протокола, сообщения, лог Godot. Без токена |
| `--profile=<имя>` | отдельные сейвы и настройки |
| `--seed=<N>` | seed новой игры |
| `--backend-url=…`, `--backend-ca=…` | адрес мастера и корневой сертификат |
| `--dev` | dev-инструменты в release-сборке |

## Тесты и живая проверка

```bash
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path game --import        # после новых файлов и правок strings.csv
"$GODOT" --path game --headless -s -d --remote-debug tcp://127.0.0.1:0 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://test --ignoreHeadlessMode
python tools/godot_playtest.py                  # живой сценарий smoke против llm_server с заглушкой хода
python tools/godot_playtest.py --scenario offline   # без сервера: экран «Мастер недоступен»
```

Сценарии лежат в `game/tools/playtest/`, база — `playtest_base.gd`. Скриншоты и `report.txt` пишутся в `build/playtest/<сценарий>/`. В сценарии нельзя упоминать классы UI по имени: они ссылаются на autoload-ы, которых ещё нет, когда компилируется скрипт `--script`. Экраны сравниваются через `screen_is("GameScreen")`.

CI Godot не гоняет (решение v0.4.0): тесты и сценарии запускаются локально перед PR. Экспорт `.exe` — позже.
