# Сравнение моделей: GLM-5.3-Flash и DeepSeek (2026-10-26, v0.7.34)

Повод — живая игра автора на `z-ai/glm-5.3-flash`: при входе на рыночную площадь мастер сам выдал герою два выдуманных предмета (`give_item` в ходе `enter` без действия игрока). Разбор трейса — ход `t-10` сессии `2026-10-26_14-48-14`.

## Как мерили

- Все 160 golden-сценариев × 3 (`--repeat 3`), промпты v0.7.34, полный промпт (без `--route`), судья `google/gemini-3.8-flash`.
- DeepSeek — `deepseek/deepseek-v4.1-flash-1017` через Relace (`config.DEFAULT_PROVIDER`); GLM — без закреплённого провайдера.
- Прогон DeepSeek прервался на 421-м ходе (во время прогона менялись шаблоны промптов); 59 недостающих ходов догнаны отдельным запуском на тех же промптах (`build/evals/20261026-140413-…`). Итоги GLM — `build/evals/20261026-133935-z-ai_glm-5.3-flash.json`, по сценариям — `build/evals/compare_2026-10-26.json`.

## Итог

| Модель | Прошло | Упало | Ошибки связи | Цена 480 ходов ¹ | Ход, среднее / медиана | Вход на сценарий ² |
|---|---|---|---|---|---|---|
| `deepseek/deepseek-v4.1-flash-1017` | **430/480 (89.6%)** | 49 | 1 | **$0.64** | 10.7 / 8.9 с | ~73 тыс. ток. |
| `z-ai/glm-5.3-flash` | 391/480 (81.5%) | 88 | 1 | $2.98 | 7.3 / 6.6 с | ~123 тыс. ток. |

¹ Цена хода мастера, без судьи. ² Сумма входа всех вызовов модели за сценарий, на одних и тех же 59 сценариях.

- **GLM падает вдвое чаще** и всегда проваливает 11 сценариев (DeepSeek — 3): `bag_take_out`, `condition_ghost_fear`, `disease_sewer_rat_bite`, `item_dedupe`, `item_letter_with_text`, `item_wand_with_charges`, `missing_concept_dragons`, `narration_matches_effects`, `office_bribe_in_court`, `quest_existing_not_made_again`, `trap_damage_severity`.
- **Чем падает GLM:** рубрика судьи — 40 (рассказ расходится с правилами), нет нужного эффекта — 17, лишние или запрещённые эффекты — 14 (`create_place` без открытого края, эффекты сверх лимита), не искала перед созданием (`find_quests`, `find_items`) — 6, состояние без спасброска — 3, пустой `missing_concept` — 3.
- **Где GLM заметно хуже** (на 2+ прохода из 3): `bag_take_out`, `container_locked_pick`, `crime_threat_let_go`, `disease_sewer_rat_bite`, `goal_hint_after_the_threshold`, `goal_no_hint_in_the_wrong_place`, `goal_quest_after_hints`, `hidden_hook_no_leak`, `item_letter_with_text`, `item_wand_with_charges`, `missing_concept_dragons`, `no_edge_no_place`, `office_bribe_in_court`, `parley_wavering_line`, `quest_existing_not_made_again`, `reward_budget_spent`, `trade_deal_narration`, `trap_damage_severity`.
- **GLM быстрее** на ход (7.3 с против 10.7 с), но **в 4.7 раза дороже** и тратит больше входа на сценарий: делает больше вызовов инструментов.
- **DeepSeek всегда падает** на `item_dedupe`, `narration_matches_effects` (давние, в бэклоге) и `quest_npc_gives_work` (новое: 0/3 — к разбору).

## Решение

Рекомендация — убрать `z-ai/glm-5.3-flash` из списка моделей (`config.DEFAULT_MODELS`): хуже по правилам, дороже, а главная её ошибка — эффекты, о которых игрок не просил, — ломает мир. Модель по умолчанию остаётся DeepSeek ([ADR-0011](adr/0011-default-master-model.md)). Автор согласился: модель убрана из списка в v0.7.34.2 (2026-10-27).

Падения DeepSeek из этого прогона и худшие сценарии GLM вошли в подмножество для оптимизации промпта ([golden-scenarios.md → «Подмножество для опытов с промптом»](golden-scenarios.md)).
