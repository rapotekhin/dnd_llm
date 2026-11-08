# Аудит по столпу 6

Генерируется: `python tools/concepts_audit.py`. Столп — [«Движок — конструктор, а не список»](../vision/pillars.md#6-движок--конструктор-а-не-список); реестр понятий — [concepts.md](../design/concepts.md); план — [роадмап v0.7.16](closed_roadmap.md#v0716--аудит-по-столпу-6-движок-конструктор). Ищет закрытые перечни случаев в коде вне правил 5e (они — столп 2) и в промптах мастера; решение по каждой находке — в `DECISIONS` инструмента.

Находок: 100 — понятие движка 13, **пробел до инструмента** 1, правило 5e 1, служебное 9, сделано 2, не разобрано 74.
Правила 5e вне аудита (столп 2): background_rules.gd, character_builder.gd, character_rules.gd, combat_rules.gd, condition_rules.gd, feature_rules.gd, hero_defense.gd, language_rules.gd, level_up.gd, monster_rules.gd, spell_effects.gd, spell_rules.gd, stock.gd.

| Где | Что | Решение | Почему |
|---|---|---|---|
| `game/core/acts/cast.gd:135` | match по summon, dispel, teleport, heal, sustained, mark, condition, curse | **не разобрано** |  |
| `game/core/acts/field.gd:6` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/acts/react.gd:53` | match по hit, damage, spell | **не разобрано** |  |
| `game/core/debug/cheats.gd:14` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/debug/cheats.gd:60` | match по item, monster, spell, feature, trait, room, class, damage… | **не разобрано** |  |
| `game/core/debug/checklist_probe.gd:487` | match по stealth_advantage, darkvision, light_source, no_crit, immune_disease, understand_all, warm, water_source… | **не разобрано** |  |
| `game/core/debug/checklist_probe.gd:987` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/debug/checklist_probe.gd:1064` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/debug/checklist_probe.gd:1170` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/debug/checklist_probe.gd:1910` | match по charmed, invisible, slowed_spell | **не разобрано** |  |
| `game/core/debug/checklist_probe.gd:1932` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/items/item_groups.gd:112` | match по weight, value, rarity, new, name | **не разобрано** |  |
| `game/core/rules/action_rules.gd:91` | match по summon, condition, dispel, curse, sustained, mark, teleport, bane… | **не разобрано** |  |
| `game/core/rules/ally_rules.gd:75` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/arena_rules.gd:361` | match по duel, tourney, bet | **не разобрано** |  |
| `game/core/rules/bank_rules.gd:486` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/bond_rules.gd:171` | match по liked, disliked | **не разобрано** |  |
| `game/core/rules/check_engine.gd:23` | match по perception, investigation, stealth, athletics | **не разобрано** |  |
| `game/core/rules/container_rules.gd:275` | match по pick, force | понятие движка | способы открыть замок — понятие движка (ключ, отмычки, сила); сложность — rules.containers |
| `game/core/rules/contest_rules.gd:149` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/contest_rules.gd:279` | match по coins, item, permit, secret | **не разобрано** |  |
| `game/core/rules/craft_rules.gd:151` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/craft_rules.gd:852` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/creature_rules.gd:174` | словарь id → русский текст в коде | служебное | слова состояний существа (перемирие, сдался, без сознания) для панели и мастера |
| `game/core/rules/creature_rules.gd:219` | match по talk, tame, free, attack, finish, search, bind, lead… | понятие движка | действия с пленником — понятие «Пленник» (concepts.md): связать, вести, отдать страже, добить…; числа — rules.creatures (v0.7.22.17) |
| `game/core/rules/creature_rules.gd:275` | match по bind, join, lead, free, hand_over, attack, finish, search… | понятие движка | применение действий понятия «Пленник»; продажа и подарок — эффект мастера `owner` (v0.7.22.17) |
| `game/core/rules/crime_rules.gd:367` | match по male, female | служебное | окончание по роду NPC (данные пакета) |
| `game/core/rules/crime_rules.gd:613` | match по bribe, pay, stocks, resist | понятие движка | ответ страже — три исхода понятия «задержание» (вергельд, колодки, сопротивление); сумма и сроки — rules.json |
| `game/core/rules/crime_rules.gd:687` | имя или описание вещи мира в коде | служебное | подпись тела убитого NPC на панели: «Тело: имя» |
| `game/core/rules/disease_rules.gd:170` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/effect_engine.gd:839` | match по damage, condition | понятие движка | эффекты на врага в бою — те же понятия |
| `game/core/rules/effect_engine.gd:989` | match по lock, unlock, break | понятие движка | три действия эффекта `door` (протокол) — отпереть, запереть, выбить; двери и их числа — rules.doors (v0.7.22.25) |
| `game/core/rules/effect_engine.gd:1004` | словарь id → русский текст в коде | служебное | слова итога эффекта `door` для ленты: заперта, отперта, выбита |
| `game/core/rules/effect_engine.gd:1381` | match по lock, unlock, break | **не разобрано** |  |
| `game/core/rules/encounter_rules.gd:356` | словарь id → русский текст в коде | служебное | окончание «связан / связана» по полу героя |
| `game/core/rules/faction_rules.gd:396` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/family_rules.gd:218` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/fight_field.gd:333` | match по door_close, door_bar, door_unbar, door_lock, door_force | **не разобрано** |  |
| `game/core/rules/fight_grid.gd:209` | match по block, pit, water, door | **не разобрано** |  |
| `game/core/rules/fight_grid.gd:708` | match по line, cone, wall, cube | **не разобрано** |  |
| `game/core/rules/heist_rules.gd:300` | match по fight, seized | **не разобрано** |  |
| `game/core/rules/heist_rules.gd:303` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:341` | match по closeness, arrest | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:364` | match по closeness, ally, arrest, recommendation | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:479` | match по ally, recommendation | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:496` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/liquid_rules.gd:215` | match по pour_out, splash | **не разобрано** |  |
| `game/core/rules/lookup.gd:10` | match по condition, rule, spell, feature, item, npc | служебное | справка движка по видам |
| `game/core/rules/make_rules.gd:220` | match по skill, ability, damage, condition | **не разобрано** |  |
| `game/core/rules/make_rules.gd:252` | match по attack, checks, no_move, skill_dis, save_dis, save_adv, skill_bonus, ac… | **не разобрано** |  |
| `game/core/rules/make_rules.gd:732` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/mount_rules.gd:81` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/org_rules.gd:107` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/prepare_rules.gd:156` | match по act, furnish, board, quest | **не разобрано** |  |
| `game/core/rules/prepare_rules.gd:218` | match по furnish, act | **не разобрано** |  |
| `game/core/rules/prepare_rules.gd:231` | match по furnish, board, quest, act | **не разобрано** |  |
| `game/core/rules/prop_rules.gd:76` | имя или описание вещи мира в коде | служебное | подпись контейнера товаров торговца: «Товары: имя» (v0.7.22.8) |
| `game/core/rules/property_rules.gd:287` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/property_rules.gd:810` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/property_rules.gd:1289` | match по rest, station, station_new, income_pct, staff_max, decay_mult, lesson_bonus, produce… | **не разобрано** |  |
| `game/core/rules/quest_rules.gd:193` | match по find, fight | **не разобрано** |  |
| `game/core/rules/roll_parts.gd:47` | match по skill, ability, save | **не разобрано** |  |
| `game/core/rules/rumor_rules.gd:408` | match по spread, tell, refute | **не разобрано** |  |
| `game/core/rules/rumor_rules.gd:451` | match по spread, tell, refute | **не разобрано** |  |
| `game/core/rules/service_rules.gd:51` | match по cure_disease, teach_recipe, status | понятие движка | почему у услуги нет цели — по операции движка (`op`), не по услуге |
| `game/core/rules/service_rules.gd:64` | match по identify, lift_curse, cure_disease, enchant, teach_recipe, rumor, meal, status | понятие движка | операции услуг движка (identify, lift_curse, enchant, status…): услуга — данные над ними, `ServiceRules` |
| `game/core/rules/service_rules.gd:137` | match по meal, rumor, identify, lift_curse, cure_disease, teach_recipe, enchant, status | сделано | v0.7.16, v0.8.4.35: услуга — понятие `ServiceRules`, операция движка из данных (`op`), у любого человека; мастер — `create:service` |
| `game/core/rules/service_rules.gd:190` | match по meal, identify, lift_curse, cure_disease, teach_recipe, enchant, status | сделано | v0.7.16: услуга — данные `item_rules.services` (операция движка + название), не код |
| `game/core/rules/shop_rules.gd:447` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/social_rules.gd:26` | match по insight, deception, wis_save | правило 5e | состязания 5e: против чего проверка (rules.social.contests) |
| `game/core/rules/study_rules.gd:131` | match по skill, tool, language, spell, recipe, dev | **не разобрано** |  |
| `game/core/rules/study_rules.gd:176` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/study_rules.gd:179` | match по skill, trait, tool, language, spell, ability, recipe | **не разобрано** |  |
| `game/core/rules/study_rules.gd:210` | match по skill, trait, tool, language, spell, recipe | **не разобрано** |  |
| `game/core/rules/study_rules.gd:519` | match по trait, skill, tool, language, spell, recipe, dev | **не разобрано** |  |
| `game/core/rules/study_rules.gd:562` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/study_rules.gd:624` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/study_rules.gd:753` | match по skill, tool, language, spell, ability, trait, recipe | **не разобрано** |  |
| `game/core/rules/study_rules.gd:852` | match по spell, skill, tool, language | **не разобрано** |  |
| `game/core/rules/teach_rules.gd:104` | match по spell, tool, skill, language, recipe | **не разобрано** |  |
| `game/core/rules/teach_rules.gd:176` | match по spell, tool, skill, language, recipe | **не разобрано** |  |
| `game/core/rules/theft_rules.gd:28` | имя или описание вещи мира в коде | служебное | монеты в карманах — понятие «кошель», не вещь мира |
| `game/core/rules/theft_rules.gd:133` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/theft_rules.gd:163` | match по fight, close_shop | **не разобрано** |  |
| `game/core/rules/theft_rules.gd:195` | match по fight | понятие движка | реакция пойманного вора — понятие с видами из шаблона (бой, лавка, стража); виды — rules.theft |
| `game/core/rules/thing_rules.gd:188` | match по burning | **не разобрано** |  |
| `game/core/rules/weather_rules.gd:182` | match по shelter, warm, fire, water, resist | **не разобрано** |  |
| `game/core/rules/wilds_rules.gd:280` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/wilds_rules.gd:286` | match по deplete, restore, add | **не разобрано** |  |
| `game/core/session/image_frame.gd:6` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/world/layout_gen.gd:881` | match по n, s, w | **не разобрано** |  |
| `game/core/world/quest_gen.gd:807` | match по talk, visit, find, fight | **не разобрано** |  |
| `game/core/world/quest_gen.gd:882` | match по all, choice | **не разобрано** |  |
| `game/core/world/world_pack.gd:98` | match по races, classes, backgrounds, items | служебное | разделы SRD в пакете мира |
| `llm_server/src/llm_server/prompts/_rules.md.j2:38` | «только из сцены» | понятие движка | новое место — `create:place` на открытом краю пакета (v0.7.20.1); без края — только выходы сцены |
| `llm_server/src/llm_server/prompts/_rules.md.j2:48` | «только из мира» | **пробел до инструмента** | людей мастер создаёт `create:npc` (v0.7.20); задания — до генерации v0.7.21 |
| `llm_server/src/llm_server/prompts/_rules.md.j2:49` | «только NPC из списка «NPC здесь»» | понятие движка | кто в сцене — список движка (расписание, спутники); отсутствующего мастер не озвучивает, недостающего создаёт `create:npc` (v0.7.22.13) |
| `llm_server/src/llm_server/prompts/_rules.md.j2:53` | «только с теми, кто есть в сцене» | понятие движка | встреча — понятие мира; создание встреч — с местами и заданиями (v0.7.20–v0.7.21) |
| `llm_server/src/llm_server/prompts/_rules.md.j2:57` | «только вещи из списка «Вокруг» в сцене (и NPC, выходы, зацепк» | понятие движка | вещи комнаты мастер создаёт сам (`furnish` при первом входе) |
| `llm_server/src/llm_server/prompts/enter.md.j2:13` | «только NPC из списка» | **не разобрано** |  |

## Исправлено

- `dict:social_rules.gd:tr_service` — v0.7.16: названия услуг — `name` в rules.json
- `text:theft_rules.gd:react` — v0.7.16: стражник — из закона локации (`law.guard_name`, `law.guard_desc` пакета)
