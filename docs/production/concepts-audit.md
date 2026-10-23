# Аудит по столпу 6

Генерируется: `python tools/concepts_audit.py`. Столп — [«Движок — конструктор, а не список»](../vision/pillars.md#6-движок--конструктор-а-не-список); реестр понятий — [concepts.md](../design/concepts.md); план — [роадмап v0.7.16](roadmap.md#v0716--аудит-по-столпу-6-движок-конструктор). Ищет закрытые перечни случаев в коде вне правил 5e (они — столп 2) и в промптах мастера; решение по каждой находке — в `DECISIONS` инструмента.

Находок: 28 — понятие движка 15, **пробел до инструмента** 1, правило 5e 2, служебное 8, сделано 2.
Правила 5e вне аудита (столп 2): background_rules.gd, character_builder.gd, character_rules.gd, combat_rules.gd, condition_rules.gd, feature_rules.gd, feature_uses.gd, hero_defense.gd, language_rules.gd, level_up.gd, monster_rules.gd, spell_effects.gd, spell_rules.gd.

| Где | Что | Решение | Почему |
|---|---|---|---|
| `game/core/rules/container_rules.gd:211` | match по pick, force | понятие движка | способы открыть замок — понятие движка (ключ, отмычки, сила); сложность — rules.containers |
| `game/core/rules/creature_rules.gd:59` | словарь id → русский текст в коде | служебное | слова состояний существа (перемирие, сдался, без сознания) для панели и мастера |
| `game/core/rules/creature_rules.gd:95` | match по attack, finish, search, bind, lead, hand_over | понятие движка | действия с пленником — понятие «Пленник» (concepts.md): связать, вести, отдать страже, добить…; числа — rules.creatures (v0.7.22.17) |
| `game/core/rules/creature_rules.gd:122` | match по bind, lead, free, hand_over, attack, finish, search | понятие движка | применение действий понятия «Пленник»; продажа и подарок — эффект мастера `owner` (v0.7.22.17) |
| `game/core/rules/crime_rules.gd:223` | match по male, female | служебное | окончание по роду NPC (данные пакета) |
| `game/core/rules/crime_rules.gd:466` | match по bribe, pay, stocks, resist | понятие движка | ответ страже — три исхода понятия «задержание» (вергельд, колодки, сопротивление); сумма и сроки — rules.json |
| `game/core/rules/crime_rules.gd:537` | имя или описание вещи мира в коде | служебное | подпись тела убитого NPC на панели: «Тело: имя» |
| `game/core/rules/effect_engine.gd:162` | match по move, damage, heal, coins, give_item, take_item, npc_attitude, cast… | понятие движка | виды эффектов — словарь понятий движка, который знает мастер (протокол); новый вид — новое понятие |
| `game/core/rules/effect_engine.gd:477` | match по damage, condition | понятие движка | эффекты на врага в бою — те же понятия |
| `game/core/rules/effect_engine.gd:729` | match по move, damage, heal, coins, give_item, take_item, npc_attitude, start_combat… | понятие движка | применение видов эффектов |
| `game/core/rules/encounter_rules.gd:146` | словарь id → русский текст в коде | служебное | окончание «связан / связана» по полу героя |
| `game/core/rules/lookup.gd:10` | match по condition, rule, spell, feature, item, npc | служебное | справка движка по видам |
| `game/core/rules/prop_rules.gd:55` | имя или описание вещи мира в коде | служебное | подпись контейнера товаров торговца: «Товары: имя» (v0.7.22.8) |
| `game/core/rules/social_rules.gd:32` | match по insight, deception, wis_save | правило 5e | состязания 5e: против чего проверка (rules.social.contests) |
| `game/core/rules/social_rules.gd:132` | match по identify, lift_curse, enchant | сделано | v0.7.16: услуга — данные `rules.items.services` (операция движка + название), не код |
| `game/core/rules/theft_rules.gd:29` | имя или описание вещи мира в коде | служебное | монеты в карманах — понятие «кошель», не вещь мира |
| `game/core/rules/theft_rules.gd:131` | имя или описание вещи мира в коде | правило 5e | безоружный удар 5e, когда у NPC украли оружие |
| `game/core/rules/theft_rules.gd:168` | match по fight, close_shop | понятие движка | реакция пойманного вора — понятие с видами из шаблона (бой, лавка, стража); виды — rules.theft |
| `game/core/rules/trade_rules.gd:453` | match по identify, lift_curse, enchant | понятие движка | операции услуг движка (identify, lift_curse, enchant): услуга — данные над ними |
| `game/core/rules/trade_rules.gd:489` | match по identify, lift_curse, enchant | сделано | v0.7.16: услуга — операция движка из данных (`op`: identify, lift_curse, enchant) |
| `game/core/world/quest_gen.gd:295` | match по talk, visit, find, fight | понятие движка | виды шагов задания — понятие «Шаг задания» (talk, visit, find, fight); новый вид — новое понятие |
| `game/core/world/quest_gen.gd:342` | match по talk, visit, fight, find | понятие движка | те же виды шагов для людей, места и вещи, которые задание приносит (v0.7.21.1) |
| `game/core/world/world_pack.gd:98` | match по races, classes, backgrounds, items | служебное | разделы SRD в пакете мира |
| `llm_server/src/llm_server/prompts/_rules.md.j2:28` | «только из сцены» | понятие движка | новое место — `create_place` на открытом краю пакета (v0.7.20.1); без края — только выходы сцены |
| `llm_server/src/llm_server/prompts/_rules.md.j2:37` | «только из мира» | **пробел до инструмента** | людей мастер создаёт `create_npc` (v0.7.20); задания — до генерации v0.7.21 |
| `llm_server/src/llm_server/prompts/_rules.md.j2:38` | «только NPC из списка «NPC здесь»» | понятие движка | кто в сцене — список движка (расписание, спутники); отсутствующего мастер не озвучивает, недостающего создаёт `create_npc` (v0.7.22.13) |
| `llm_server/src/llm_server/prompts/_rules.md.j2:42` | «только с теми, кто есть в сцене» | понятие движка | встреча — понятие мира; создание встреч — с местами и заданиями (v0.7.20–v0.7.21) |
| `llm_server/src/llm_server/prompts/_rules.md.j2:46` | «только вещи из списка «Вокруг» в сцене (и NPC, выходы, зацепк» | понятие движка | вещи комнаты мастер создаёт сам (`furnish` при первом входе) |

## Исправлено

- `dict:social_rules.gd:tr_service` — v0.7.16: названия услуг — `name` в rules.json
- `text:theft_rules.gd:react` — v0.7.16: стражник — из закона локации (`law.guard_name`, `law.guard_desc` пакета)
