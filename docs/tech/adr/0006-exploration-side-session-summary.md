# ADR-0006: Возврат из side-сессии в exploration через явную суммаризацию

**Дата:** 2026-05-03
**Статус:** Accepted

## Контекст

В игре есть основной режим `exploration` (главный экран, ЛЛМ-«ГМ» предлагает игроку действия) и side-режимы: `social` (диалог с НПС), `trade` (торговля), `combat` (пока не реализован). Поток управления: игрок может из exploration уйти в social, из social — в trade, из trade — обратно в social, из social — обратно в exploration. Каждый side-режим запускается в собственном фоновом потоке (`run_social`, отдельный UI у `trade`); общение с UI идёт через очереди сообщений.

Текущая реализация ([`game/core/gameplay/exploration.py`](../../../game/core/gameplay/exploration.py), [`game/core/gameplay/social_interaction.py`](../../../game/core/gameplay/social_interaction.py), [`game/ui/screens/main_screen.py`](../../../game/ui/screens/main_screen.py), [`game/ui/screens/social_screen.py`](../../../game/ui/screens/social_screen.py), [`game/core/game.py`](../../../game/core/game.py)) устроена так:

- Поток exploration **не завершается** при переходе в social/trade. Он шлёт `transition` и блокируется на `_wait_for_input(input_queue)` в ожидании сигнала `resume`. По комментарию в коде это сделано «чтобы избежать медленного `describe_scene` на возврате».
- Поток social, наоборот, **завершается** при выходе в exploration: синхронно генерирует `_generate_social_summary` и пишет его в `location.location_history_summary`. Если игрок ушёл из social кнопкой «Уйти» (а не действием LLM), summary запускается **асинхронно** через `generate_social_summary_async` уже из UI-слоя.
- Возврат в exploration инициируется `Game._handle_screen_result("exploration"/"main") → _enter_main() → MainScreen.start_exploration()`. Если поток жив — посылается `{"type": "resume"}`. Поток exploration пробуждается и сразу идёт к `generate_actions` с прежним `state["scene"]` и пустым `state["history"]`.
- Trade-экран не имеет своего LLM-агента и не пишет никаких summary.

Эта схема приводит к багам в цепочках `exploration → social → exploration` и `exploration → social → trade → social → exploration`:

1. `state["scene"]` в exploration loop не обновляется на возврате — LLM получает в промпте описание мира **до** диалога/торговли.
2. `state["history"]` обнуляется, но в него не добавляется отчёт о side-сессии — у LLM нет контекста, что произошло.
3. Единственный канал передачи — `location_history_summary` через системный промпт пересобранных агентов — подвержен race condition: при выходе из social кнопкой «Уйти» summary пишется в фоне и обычно **не успевает** обновиться к моменту пересборки.
4. Trade не пишет собственного отчёта; результат торговли не доходит ни до social-loop, ни до exploration-loop явно.
5. Из-за «pause + resume» exploration-loop при возврате не выполняется ни один контекстно-инициализирующий шаг (новый scene или эквивалент), и пользователь видит, как LLM «продолжает диалог» в окне exploration или предлагает действия так, словно диалога не было.

Подробное описание симптомов и сценариев — в [production/backlog.md](../../production/backlog.md), раздел «Сломанная механика перехода exploration → social → exploration».

## Решение

Сделать возврат в exploration **явным контрактом** между side-сессией и основным потоком, основанным на синхронной суммаризации:

1. **Side-сессия (social/trade/combat) обязана сформировать `side_session_summary` синхронно** — в **последнем** шаге своего loop, до того как поток отправит `transition` в exploration. Никаких `*_async`, никаких фоновых записей в `location_history_summary` уже после ухода игрока с экрана.

2. **`transition`-сообщение от side-сессии расширяется полем `summary: str`** — короткий (2-4 предложения) текст «что произошло» от лица ГМ-нарратора. Этот summary создаётся:
   - в `social` — на основе `state["history"]` диалога;
   - в `trade` — на основе фактов сделки (что куплено/продано, какие монеты сменили хозяина); генерация может быть детерминированной (без LLM) либо через лёгкий LLM-вызов;
   - в `combat` — по аналогии (на этапе реализации режима).

3. **Цепочки side → side (например, social → trade → social)** агрегируют summary внутри родительского side-loop: при возврате из trade в social, social-loop добавляет summary trade в свою историю как ход событий, чтобы при последующем выходе в exploration итоговый summary охватил всю side-сессию целиком.

4. **Exploration-loop при возврате (по сигналу `resume`) обязан:**
   - получить `summary` из side-сессии (через поле в transition-сообщении или через временное поле в `MainGameState`, например `pending_side_summary: Optional[str]`);
   - добавить его в `state["history"]` как первую запись (`f"DM: {summary}"`);
   - **пересобрать `state["scene"]` через `describe_scene`** — это даёт LLM свежую сцену, которая отражает изменившийся мир (NPC ушёл/остался, инвентарь обновился, location_history_summary в системном промпте свежий).
   - Только после этого идти к `generate_actions`.

5. **`location.location_history_summary` обновляется одним и тем же синхронным путём** — внутри side-loop **до** отправки transition. Async-путь (`generate_social_summary_async`) удаляется как небезопасный.

Контракт между потоками становится таким:

| Канал | Отправитель | Содержимое |
|---|---|---|
| `transition` (ui_queue) | side-loop | `action`, `npc_id`, `room_id`, **`summary`** |
| `resume` (input_queue) | UI / Game | сигнал, `summary` уже в state или сообщении |
| `location_history_summary` | side-loop, синхронно до transition | накопительный фон для системного промпта |

## Альтернативы

1. **Оставить «pause + resume» exploration-thread без summary, но обновлять `state["scene"]` через describe_scene на каждом resume.** Решает вопрос устаревшей сцены, но не передаёт явный отчёт о side-сессии и сохраняет race condition с async-summary. Промежуточный вариант, не закрывающий всех причин бага.

2. **Завершать exploration-thread на каждом transition в side-режим и перезапускать заново на возврате** (вариант B из обсуждения). Чистая модель: каждый возврат — новый поток, новый describe_scene, новый системный промпт. Минусы: каждый возврат добавляет один полный LLM-вызов на describe_scene (несколько секунд), причём это «удвоение» относительно текущей задержки от summary. Архитектурно проще, но дороже по UX-латентности.

3. **Передавать историю side-сессии целиком (а не summary) в exploration.** Отвергнуто: контекст быстро раздуется, особенно после нескольких циклов social ↔ trade; LLM начнёт путаться, стоимость выше.

4. **Выделить общий менеджер режимов вместо паттерна «pause + resume на очереди».** Долгосрочно правильнее, но это более масштабная переработка координации потоков; на момент решения не оправдано — текущий контракт можно починить точечно.

## Последствия

**Плюсы:**

- Контекст side-сессии гарантированно доезжает до exploration-агента и не теряется из-за race conditions.
- `location_history_summary` пишется одним синхронным путём — поведение становится предсказуемым.
- Trade перестаёт быть «слепым пятном»: его результат передаётся в social и далее в exploration как часть общей суммаризации.
- Подход расширяется на combat и любые будущие side-режимы без переделки exploration-loop.
- Симптомы «LLM продолжает диалог в окне exploration» и «не помнит торговлю» уходят как класс.

**Минусы:**

- При выходе из social/trade игрок дополнительно ждёт синхронной генерации summary (если делается через LLM). Для trade можно ограничиться детерминированным шаблоном; для social — это уже происходит, просто становится обязательным и для пути «Уйти».
- На возврате в exploration придётся пересобрать `state["scene"]` (по сути — короткий describe_scene или скромная переформулировка). Это +1 LLM-вызов в худшем случае, но он оправдан корректностью.
- Удаление `generate_social_summary_async` слегка увеличивает время отклика UI на «Уйти».
- Контракт `transition`-сообщения расширяется новым обязательным (или почти обязательным) полем — нужно обновить и UI-слой (`MainScreen._drain_exploration_queue`, `SocialScreen._drain_social_queue`) и тесты.

## Связанные

- [production/backlog.md](../../production/backlog.md) — раздел «Сломанная механика перехода exploration → social → exploration»
- [ADR-0001](0001-llm-as-gm-not-engine.md) — общая модель «ЛЛМ как ГМ, состояние мира — в коде»; данный ADR уточняет контракт между side-режимами и основным циклом
- [design/systems/social.md](../../design/systems/social.md) — спецификация социального режима (потребует уточнения секции о выходе)
- [design/systems/trade.md](../../design/systems/trade.md) — спецификация торговли (потребует пункта про summary)
- [tech/llm-integration.md](../llm-integration.md) — общая интеграция с ЛЛМ
