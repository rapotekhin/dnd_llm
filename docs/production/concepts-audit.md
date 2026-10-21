# Аудит по столпу 6

Генерируется: `python tools/concepts_audit.py`. Столп — [«Движок — конструктор, а не список»](../vision/pillars.md#6-движок--конструктор-а-не-список); реестр понятий — [concepts.md](../design/concepts.md); план — [роадмап v0.7.16](roadmap.md#v0716--аудит-по-столпу-6-движок-конструктор). Ищет закрытые перечни случаев в коде вне правил 5e (они — столп 2) и в промптах мастера; решение по каждой находке — в `DECISIONS` инструмента.

Находок: 20 — понятие движка 9, **пробел до инструмента** 2, правило 5e 2, служебное 5, сделано 2.
Правила 5e вне аудита (столп 2): background_rules.gd, character_builder.gd, character_rules.gd, combat_rules.gd, condition_rules.gd, feature_rules.gd, feature_uses.gd, hero_defense.gd, language_rules.gd, level_up.gd, monster_rules.gd, spell_effects.gd, spell_rules.gd.

| Где | Что | Решение | Почему |
|---|---|---|---|
| `game/core/rules/crime_rules.gd:110` | match по male, female | служебное | окончание по роду NPC (данные пакета) |
| `game/core/rules/crime_rules.gd:196` | match по pay, stocks, resist | понятие движка | ответ страже — три исхода понятия «задержание» (вергельд, колодки, сопротивление); сумма и сроки — rules.json |
| `game/core/rules/crime_rules.gd:245` | имя или описание вещи мира в коде | служебное | подпись тела убитого NPC на панели: «Тело: имя» |
| `game/core/rules/effect_engine.gd:138` | match по move, damage, heal, coins, give_item, take_item, npc_attitude, cast… | понятие движка | виды эффектов — словарь понятий движка, который знает мастер (протокол); новый вид — новое понятие |
| `game/core/rules/effect_engine.gd:384` | match по damage, condition | понятие движка | эффекты на врага в бою — те же понятия |
| `game/core/rules/effect_engine.gd:598` | match по move, damage, heal, coins, give_item, take_item, npc_attitude, start_combat… | понятие движка | применение видов эффектов |
| `game/core/rules/lookup.gd:10` | match по condition, rule, spell, feature, item, npc | служебное | справка движка по видам |
| `game/core/rules/social_rules.gd:32` | match по insight, deception, wis_save | правило 5e | состязания 5e: против чего проверка (rules.social.contests) |
| `game/core/rules/social_rules.gd:130` | match по identify, lift_curse, enchant | сделано | v0.7.16: услуга — данные `rules.items.services` (операция движка + название), не код |
| `game/core/rules/theft_rules.gd:29` | имя или описание вещи мира в коде | служебное | монеты в карманах — понятие «кошель», не вещь мира |
| `game/core/rules/theft_rules.gd:139` | match по fight, close_shop | понятие движка | реакция пойманного вора — понятие с видами из шаблона (бой, лавка, стража); виды — rules.theft |
| `game/core/rules/trade_rules.gd:299` | match по identify, lift_curse, enchant | понятие движка | операции услуг движка (identify, lift_curse, enchant): услуга — данные над ними |
| `game/core/rules/trade_rules.gd:335` | match по identify, lift_curse, enchant | сделано | v0.7.16: услуга — операция движка из данных (`op`: identify, lift_curse, enchant) |
| `game/core/world/world_pack.gd:98` | match по races, classes, backgrounds, items | служебное | разделы SRD в пакете мира |
| `llm_server/src/llm_server/prompts/_rules.md.j2:13` | «только на время из списка: движок сам промотает его» | правило 5e | длительности состояний 5e |
| `llm_server/src/llm_server/prompts/_rules.md.j2:31` | «только если ничего похожего нет; механика только из списка свойств» | понятие движка | новый предмет мастер создаёт сам (`give_item.item`) из словаря свойств — генерация полностью в v0.7.18 |
| `llm_server/src/llm_server/prompts/_rules.md.j2:33` | «только из сцены» | **пробел до инструмента** | мастер не может создать место — до генерации мест v0.7.19; тогда — «нужно место по замыслу игрока → создай» |
| `llm_server/src/llm_server/prompts/_rules.md.j2:41` | «только из мира» | **пробел до инструмента** | людей и задания мастер не создаёт — до генерации v0.7.19–v0.7.20 |
| `llm_server/src/llm_server/prompts/_rules.md.j2:48` | «только с теми, кто есть в сцене» | понятие движка | встреча — понятие мира; создание встреч — с местами и заданиями (v0.7.19–v0.7.20) |
| `llm_server/src/llm_server/prompts/_rules.md.j2:51` | «только вещи из списка «Вокруг» в сцене (и NPC, выходы, зацепк» | понятие движка | вещи комнаты мастер создаёт сам (`furnish` при первом входе) |

## Исправлено

- `dict:social_rules.gd:tr_service` — v0.7.16: названия услуг — `name` в rules.json
- `text:theft_rules.gd:react` — v0.7.16: стражник — из закона локации (`law.guard_name`, `law.guard_desc` пакета)
