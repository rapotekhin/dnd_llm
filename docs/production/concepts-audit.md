# Аудит по столпу 6

Генерируется: `python tools/concepts_audit.py`. Столп — [«Движок — конструктор, а не список»](../vision/pillars.md#6-движок--конструктор-а-не-список); реестр понятий — [concepts.md](../design/concepts.md); план — [роадмап v0.7.16](closed_roadmap.md#v0716--аудит-по-столпу-6-движок-конструктор). Ищет закрытые перечни случаев в коде вне правил 5e (они — столп 2) и в промптах мастера; решение по каждой находке — в `DECISIONS` инструмента.

Находок: 72 — понятие движка 14, **пробел до инструмента** 1, правило 5e 2, служебное 9, сделано 2, не разобрано 44.
Правила 5e вне аудита (столп 2): background_rules.gd, character_builder.gd, character_rules.gd, combat_rules.gd, condition_rules.gd, feature_rules.gd, hero_defense.gd, language_rules.gd, level_up.gd, monster_rules.gd, spell_effects.gd, spell_rules.gd, stock.gd.

| Где | Что | Решение | Почему |
|---|---|---|---|
| `game/core/rules/arena_rules.gd:306` | match по duel, tourney | **не разобрано** |  |
| `game/core/rules/bank_rules.gd:496` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/bond_rules.gd:176` | match по liked, disliked | **не разобрано** |  |
| `game/core/rules/container_rules.gd:221` | match по pick, force | понятие движка | способы открыть замок — понятие движка (ключ, отмычки, сила); сложность — rules.containers |
| `game/core/rules/contest_rules.gd:126` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/contest_rules.gd:157` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/contest_rules.gd:283` | match по coins, item, permit, secret | **не разобрано** |  |
| `game/core/rules/creature_rules.gd:88` | словарь id → русский текст в коде | служебное | слова состояний существа (перемирие, сдался, без сознания) для панели и мастера |
| `game/core/rules/creature_rules.gd:136` | match по attack, finish, search, bind, lead, join, hand_over | понятие движка | действия с пленником — понятие «Пленник» (concepts.md): связать, вести, отдать страже, добить…; числа — rules.creatures (v0.7.22.17) |
| `game/core/rules/creature_rules.gd:168` | match по bind, join, lead, free, hand_over, attack, finish, search | понятие движка | применение действий понятия «Пленник»; продажа и подарок — эффект мастера `owner` (v0.7.22.17) |
| `game/core/rules/crime_rules.gd:318` | match по male, female | служебное | окончание по роду NPC (данные пакета) |
| `game/core/rules/crime_rules.gd:573` | match по bribe, pay, stocks, resist | понятие движка | ответ страже — три исхода понятия «задержание» (вергельд, колодки, сопротивление); сумма и сроки — rules.json |
| `game/core/rules/crime_rules.gd:652` | имя или описание вещи мира в коде | служебное | подпись тела убитого NPC на панели: «Тело: имя» |
| `game/core/rules/disease_rules.gd:143` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/effect_engine.gd:177` | match по move, damage, heal, coins, give_item, take_item, npc_attitude, cast… | понятие движка | виды эффектов — словарь понятий движка, который знает мастер (протокол); новый вид — новое понятие |
| `game/core/rules/effect_engine.gd:670` | match по damage, condition | понятие движка | эффекты на врага в бою — те же понятия |
| `game/core/rules/effect_engine.gd:796` | match по lock, unlock, break | понятие движка | три действия эффекта `door` (протокол) — отпереть, запереть, выбить; двери и их числа — rules.doors (v0.7.22.25) |
| `game/core/rules/effect_engine.gd:811` | словарь id → русский текст в коде | служебное | слова итога эффекта `door` для ленты: заперта, отперта, выбита |
| `game/core/rules/effect_engine.gd:978` | match по move, damage, heal, coins, give_item, take_item, npc_attitude, start_combat… | понятие движка | применение видов эффектов |
| `game/core/rules/encounter_rules.gd:261` | словарь id → русский текст в коде | служебное | окончание «связан / связана» по полу героя |
| `game/core/rules/faction_rules.gd:398` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/family_rules.gd:224` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/heist_rules.gd:312` | match по fight, seized | **не разобрано** |  |
| `game/core/rules/heist_rules.gd:315` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:299` | match по closeness, arrest | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:322` | match по closeness, ally, arrest, recommendation | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:437` | match по ally, recommendation | **не разобрано** |  |
| `game/core/rules/letter_rules.gd:446` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/lookup.gd:10` | match по condition, rule, spell, feature, item, npc | служебное | справка движка по видам |
| `game/core/rules/make_rules.gd:106` | match по skill, ability, damage | **не разобрано** |  |
| `game/core/rules/make_rules.gd:134` | match по attack, checks, no_move, skill_dis, save_dis, save_adv, skill_bonus, ac… | **не разобрано** |  |
| `game/core/rules/make_rules.gd:277` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/mount_rules.gd:79` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/org_rules.gd:109` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/prop_rules.gd:57` | имя или описание вещи мира в коде | служебное | подпись контейнера товаров торговца: «Товары: имя» (v0.7.22.8) |
| `game/core/rules/property_rules.gd:261` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/property_rules.gd:796` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/property_rules.gd:1274` | match по rest, station, station_new, income_pct, staff_max, decay_mult, lesson_bonus, produce… | **не разобрано** |  |
| `game/core/rules/roll_parts.gd:47` | match по skill, ability, save | **не разобрано** |  |
| `game/core/rules/rumor_rules.gd:411` | match по spread, tell, refute | **не разобрано** |  |
| `game/core/rules/rumor_rules.gd:454` | match по spread, tell, refute | **не разобрано** |  |
| `game/core/rules/shop_rules.gd:452` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/social_rules.gd:32` | match по insight, deception, wis_save | правило 5e | состязания 5e: против чего проверка (rules.social.contests) |
| `game/core/rules/social_rules.gd:132` | match по meal, identify, lift_curse, cure_disease, teach_recipe, enchant | сделано | v0.7.16: услуга — данные `rules.items.services` (операция движка + название), не код |
| `game/core/rules/study_rules.gd:138` | match по skill, tool, language, spell, recipe, dev | **не разобрано** |  |
| `game/core/rules/study_rules.gd:194` | match по skill, trait, tool, language, spell, recipe | **не разобрано** |  |
| `game/core/rules/study_rules.gd:223` | match по skill, trait, tool, language, spell, recipe | **не разобрано** |  |
| `game/core/rules/study_rules.gd:504` | match по trait, skill, tool, language, spell, recipe, dev | **не разобрано** |  |
| `game/core/rules/study_rules.gd:550` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/study_rules.gd:612` | имя или описание вещи мира в коде | **не разобрано** |  |
| `game/core/rules/study_rules.gd:735` | match по skill, tool, language, spell, trait, recipe | **не разобрано** |  |
| `game/core/rules/study_rules.gd:833` | match по spell, skill, tool, language | **не разобрано** |  |
| `game/core/rules/teach_rules.gd:104` | match по spell, tool, skill, language, recipe | **не разобрано** |  |
| `game/core/rules/teach_rules.gd:176` | match по spell, tool, skill, language, recipe | **не разобрано** |  |
| `game/core/rules/theft_rules.gd:29` | имя или описание вещи мира в коде | служебное | монеты в карманах — понятие «кошель», не вещь мира |
| `game/core/rules/theft_rules.gd:136` | имя или описание вещи мира в коде | правило 5e | безоружный удар 5e, когда у NPC украли оружие |
| `game/core/rules/theft_rules.gd:177` | match по fight, close_shop | понятие движка | реакция пойманного вора — понятие с видами из шаблона (бой, лавка, стража); виды — rules.theft |
| `game/core/rules/trade_rules.gd:561` | match по identify, lift_curse, cure_disease, enchant, teach_recipe, rumor, meal | понятие движка | операции услуг движка (identify, lift_curse, enchant): услуга — данные над ними |
| `game/core/rules/trade_rules.gd:606` | match по meal, rumor, identify, lift_curse, cure_disease, teach_recipe, enchant | сделано | v0.7.16: услуга — операция движка из данных (`op`: identify, lift_curse, enchant) |
| `game/core/rules/weather_rules.gd:192` | match по shelter, warm, fire, water, resist | **не разобрано** |  |
| `game/core/rules/wilds_rules.gd:280` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/rules/wilds_rules.gd:286` | match по deplete, restore, add | **не разобрано** |  |
| `game/core/session/image_frame.gd:6` | словарь id → русский текст в коде | **не разобрано** |  |
| `game/core/world/quest_gen.gd:766` | match по talk, visit, find, fight | **не разобрано** |  |
| `game/core/world/quest_gen.gd:845` | match по all, choice | **не разобрано** |  |
| `game/core/world/world_pack.gd:98` | match по races, classes, backgrounds, items | служебное | разделы SRD в пакете мира |
| `llm_server/src/llm_server/prompts/_rules.md.j2:38` | «только из сцены» | понятие движка | новое место — `create_place` на открытом краю пакета (v0.7.20.1); без края — только выходы сцены |
| `llm_server/src/llm_server/prompts/_rules.md.j2:46` | «только из мира» | **пробел до инструмента** | людей мастер создаёт `create_npc` (v0.7.20); задания — до генерации v0.7.21 |
| `llm_server/src/llm_server/prompts/_rules.md.j2:47` | «только NPC из списка «NPC здесь»» | понятие движка | кто в сцене — список движка (расписание, спутники); отсутствующего мастер не озвучивает, недостающего создаёт `create_npc` (v0.7.22.13) |
| `llm_server/src/llm_server/prompts/_rules.md.j2:51` | «только с теми, кто есть в сцене» | понятие движка | встреча — понятие мира; создание встреч — с местами и заданиями (v0.7.20–v0.7.21) |
| `llm_server/src/llm_server/prompts/_rules.md.j2:55` | «только вещи из списка «Вокруг» в сцене (и NPC, выходы, зацепк» | понятие движка | вещи комнаты мастер создаёт сам (`furnish` при первом входе) |
| `llm_server/src/llm_server/prompts/enter.md.j2:13` | «только NPC из списка» | **не разобрано** |  |

## Исправлено

- `dict:social_rules.gd:tr_service` — v0.7.16: названия услуг — `name` в rules.json
- `text:theft_rules.gd:react` — v0.7.16: стражник — из закона локации (`law.guard_name`, `law.guard_desc` пакета)
