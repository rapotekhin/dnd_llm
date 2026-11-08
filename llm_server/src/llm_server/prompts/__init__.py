"""Prompt templates (Jinja2, *.md.j2 next to this file). StrictUndefined: a missing variable is an error."""

import re
from collections.abc import Callable
from pathlib import Path
from typing import NamedTuple

from jinja2 import Environment, FileSystemLoader, StrictUndefined

from ..protocol import CharacterSheet, Gender, SceneNpc, Snapshot, class_tag, effect_classes, effect_line

DEFAULT_TONE = "тёмное фэнтези с надеждой: мир суров, но в нём есть место смелости и доброте"

_ATTITUDE = {-3: "враждебно", -2: "неприязненно", -1: "настороженно", 0: "нейтрально", 1: "приветливо", 2: "дружески", 3: "как к близкому другу"}
_ROLES = {"player": "Игрок", "dm": "Мастер", "npc": "NPC"}


def attitude_word(value: int) -> str:
    return _ATTITUDE[max(-3, min(3, value))]


_ABILITIES = {"str": "Сил", "dex": "Лов", "con": "Тел", "int": "Инт", "wis": "Мдр", "cha": "Хар"}


def ability_name(key: str) -> str:
    return _ABILITIES.get(key, key)


STYLE_RULES = {
    "classic": "Классический: ровный серьёзный рассказчик. Сцена — 2–4 предложения, ответ на действие — 1–3, без лишних метафор.",
    "literary": "Литературный: образно и атмосферно — запахи, звуки, свет, точные метафоры. До 4 предложений, ритм неспешный, но без воды.",
    "dry": "Сухой: коротко и по делу — не больше 3 коротких предложений (строже общего лимита): что есть, кто есть, куда можно пойти. Без эпитетов и атмосферы.",
    "ironic": "Ироничный: лёгкая усмешка над штампами и ситуацией, но мир остаётся опасным, а NPC — живыми людьми. Не глумись над игроком.",
}
VIOLENCE_RULES = {
    "mild": "мягко: насилие и раны — без натурализма, одной фразой; смерть — за кадром",
    "medium": "умеренно: бой и раны описываются честно, но без смакования крови и увечий",
    "graphic": "жёстко — игрок выбрал это сам: раны, кровь, увечья, боль и смерть описывай прямо и натуралистично, конкретными телесными деталями; жестокость, которую игрок совершает или видит, показывай в кадре, не смягчай, не уводи за кадр и не морализируй (кроме того, что в линиях и вуалях)",
}


def summary_title(key: str) -> str:
    if key == "location":
        return "В этой локации"
    if key.startswith("dialogue:"):
        return f"Разговор с [{key.split(':', 1)[1]}]"
    return key


def gender_rule(gender: Gender) -> str:
    return {
        "female": "Персонаж игрока — женщина: обращайся в женском роде («ты вошла», «готова»).",
        "male": "Персонаж игрока — мужчина: обращайся в мужском роде («ты вошёл», «готов»).",
    }.get(gender, "Пол персонажа не указан: избегай родовых форм при обращении к игроку.")


def hero_gender(gender: Gender) -> str:
    """The hero's sex in a word for the scene (v0.7.22.20, #22): the NPCs see it in every talk."""
    return {"female": "женщина", "male": "мужчина"}.get(gender, "пол не указан")


def npc_gender_rule(gender: Gender) -> str:
    return {
        "female": "О себе NPC говорит в женском роде.",
        "male": "О себе NPC говорит в мужском роде.",
    }.get(gender, "")


def coins(cp: int) -> str:
    gp, rest = divmod(cp, 100)
    sp, cp_left = divmod(rest, 10)
    parts = [f"{gp} зм" if gp else "", f"{sp} см" if sp else "", f"{cp_left} мм" if cp_left else ""]
    return " ".join(p for p in parts if p) or "0 зм"


_env = Environment(
    loader=FileSystemLoader(Path(__file__).parent),
    undefined=StrictUndefined,
    trim_blocks=True,
    lstrip_blocks=True,
    keep_trailing_newline=False,
)
_env.globals["topic_fields"] = lambda key: topic_fields(key)
def intimacy_rule(world: object) -> str:
    """18+ of the game (0.76.0) and the engine's children and teens of the scene, who are never intimate."""
    if getattr(world, "adult", False):
        rule = ("Близость взрослых — по желанию игрока: её можно описывать прямо, без ухода за кадр, "
                "если оба взрослые и согласны.")
    else:
        rule = ("Близость и интимные сцены уходят за кадр: игрок вправе к ним прийти, но ты пропускаешь саму сцену "
                "и одной-двумя фразами говоришь итог, без подробностей тела. Это сильнее желаний игрока.")
    return rule


_env.globals.update(intimacy_rule=intimacy_rule, attitude_word=attitude_word, hero_gender=hero_gender, money=coins, summary_title=summary_title, ability_name=ability_name,
                    style_rule=lambda s: STYLE_RULES.get(s, STYLE_RULES["classic"]),
                    violence_rule=lambda v: VIOLENCE_RULES.get(v, VIOLENCE_RULES["medium"]), role_name=lambda r: _ROLES.get(r, r))


def render(name: str, **context: object) -> str:
    text = _env.get_template(name).render(**context)
    # Collapse the blank-line runs that conditional blocks leave behind.
    lines: list[str] = []
    for line in text.splitlines():
        if line.strip() or (lines and lines[-1].strip()):
            lines.append(line.rstrip())
    return "\n".join(lines).strip() + "\n"


# Topics of a scene, not of a conversation: out of the index while the hero talks (still readable by `rules`).
SCENE_TOPICS = {"places", "containers", "doors", "equip", "tools", "invisible"}
WATER_WORDS = re.compile(r"вод[аыуе]|набра|набер|наполн|зачерп|бурдюк|фляг|кувшин|ведр|нацед|налить|налью|вылить|вылью|выливаю|облить|оболью|обливаю|плесн|плещу|"
                         r"масл[оау]|вина|вино", re.IGNORECASE)  # v0.8.4.28.3: any liquid
BOARD = re.compile(r"доск|объявлен|листк|столб с", re.IGNORECASE)
EQUIP_WORDS = re.compile(r"наден|надева|надет|сним|сня[лт]|сбрось|разде[нв]|переоде|отстав|щит|доспех|кольчуг|латы|кольц|плащ|шлем|сапог|перчат|амулет",
                         re.IGNORECASE)  # v0.8.4.40: the hero's and a person's gear by words, in a conversation too
MOUNT_WORDS = re.compile(r"конь|коня|кобыл|лошад|мул|осл|верблюд|вьюк|навьюч|телег|фургон|повозк|запряч|упряж|верхом|скакун|аренд|напрокат",
                         re.IGNORECASE)  # v0.7.42
WEATHER_WORDS = re.compile(r"погод|дожд|ливн|ливен|туман|снег|метел|вьюг|мороз|холод|зно[йя]|жар[аы]|небо|тучи|ветер|гроз",
                           re.IGNORECASE)
RUMOR_WORDS = re.compile(r"слух|слыха|слышн|прислуш|подслуш|о ч[её]м говор|болтовн|говорят|что нового|новост|сплет|болтают|судачат|толкуют|пустить|распуст|наводк",
                         re.IGNORECASE)  # v0.7.47; a notice is the board's (v0.8.4.29.7)
FAITH_WORDS = re.compile(r"бог[аиу ]|богин|бож|молит|молюсь|помол|обет|клян|присяг|храм|алтар|святил|святын|жриц|жрец|вер[уыа] |вера$|обращ|"
                         r"искуп|скверн|заповед|идол|капищ|чонти|сильванус|тир[ау ]|вокин|маск[еуи]|келемвор", re.IGNORECASE)  # v0.7.49; a blessing is `make`, «маскировка» is no Mask (v0.8.4.29.7)
FESTIVAL_WORDS = re.compile(r"праздн|ярмар|дожин|гулянь|торговый день|свадьб|пир[ау ]|поминк|календар|какое число|какой день|месяц",
                            re.IGNORECASE)  # v0.7.44
WAY_WORDS = re.compile(r"лаз|пролом|подкоп|тайн\w* ход|потайн|щел[ьи]|дыр[аую]|прокопа", re.IGNORECASE)  # v0.7.66
BOUT_WORDS = re.compile(r"поедин|дуэл|вызыва|вызов|сразимся|сразиться|помахаться|на кулак|до первой крови|до сдачи|арен|бойцов|кровав[аую]+ ям|турнир|ставк",
                        re.IGNORECASE)  # v0.7.45
WILDS_WORDS = re.compile(r"охот|рыб|удочк|удить|сеть|сети|дич|зверь|звер[яюи]|олен|выслеж|капкан|силк|кабан|заяц|зайц|улов|клюёт|клюет|браконь",
                         re.IGNORECASE)  # v0.7.41


MAKE_WORDS = re.compile(r"проклят|проклин|порч|сглаз|морок|благослов|заговор[её]н|зачарован|научи|обучи|выучи|наставник|"
                        r"свит[оке]|трактат|манускрипт|фолиант|гримуар|неведом|хочу уметь|перенять|придума|сочин|изобрет|вывед|выводу|разработа|"
                        r"яд|отрав|виски|самогон|настойк|наливк|эликсир|ликёр|ликер|бренди|медовух",
                        re.IGNORECASE)  # v0.7.63: what the data has not, built of parts; v0.8.4.28.5: a liquid
SERVICE_WORDS = re.compile(r"посереб|услуг|закал|заточ|освят|оберег|благослов|зачаруй|зачаровать|наложи|наточ", re.IGNORECASE)  # v0.8.4.35
BANK_WORDS = re.compile(r"ссуд|заём|заем|займ|в долг|залог|ростовщ|кредит|вклад|одолж", re.IGNORECASE)  # v0.7.70.1
UNDERWORLD_WORDS = re.compile(r"взлом|обчист|ограб|обнес|контрабанд|скупщик|краден|вынести|вынесу|кассу", re.IGNORECASE)  # v0.7.70.1
CRAFT_WORDS = re.compile(r"выков|скую|скова|кую |смастер|сработаю|выточ|сошью|рецепт", re.IGNORECASE)  # v0.7.70.2
# v0.8.4.28.7: a search where something is hidden — what is found is given as a new thing (wear, summon, use)
TEACH_WORDS = re.compile(r"научи|обучи|выучи|хочу уметь|хочу так же|хочу научиться|научиться|перенять|возьми в ученики|в ученики",
                         re.IGNORECASE)  # v0.8.4.41.1: a request to be taught, checked at the end of the turn
FIND_WORDS = re.compile(r"обыск|обшар|ищу|искать|поиск|пошар|роюсь|рыться|перерыва|разгреб|вороша|что тут|что здесь|что внутри|"
                        r"натаскал|положили|спрятан|клад|сокровищ", re.IGNORECASE)
JOB_WORDS = re.compile(r"работ|наймусь|нанять|найми|вышибал|устроиться", re.IGNORECASE)  # v0.7.70.1


# Containers and new places come whole only when the player's words touch them (v0.7.34.3): a chest stood in 23 of 31
# full turns of the author's trace, an open edge in 11. Otherwise the index has them, and the gate hands their rules.
CONTAINER_WORDS = re.compile(r"сунду|ящик|шкаф|бочк|бочон|корзин|мешок|мешк|сумк|рюкзак|кошел|ларец|ларц|шкатул|тайник|"
                             r"достать|достаю|достан|вынуть|выну|полож|кладу|убра|убер|спрят(?!ан)|отпер|отопр|вскр|ключ|оставл|остав|"
                             r"брос|товар|продаж|запас|внутр|содерж", re.IGNORECASE)
PLACE_WORDS = re.compile(r"постро|строит|стройк|основ|заложи|новое место|найти мест|ищу мест|разведа|за город|за околиц|"
                         r"лавк|мастерск|дом|избу|хижин|баню|пекарн|кузниц|таверн|трактир|харчевн|лагер|стоянк|тропу|дорогу|сверн|свора|вглубь|чащ|что там|"
                         r"исследу", re.IGNORECASE)


def mentions(said: str, words: re.Pattern[str], scene: object = None) -> bool:
    """The player's words name the topic: its words or (for containers) a container of the scene by name."""
    if words.search(said):
        return True
    props = getattr(scene, "props", None) or []
    return any(w[:5].lower() in said.lower() for p in props if p.container for w in p.name.split() if len(w) >= 4)


def names_a_faction(said: str, scene: object) -> bool:
    """The player's words name a faction of the frame: «Ночные крысы (night_rats, org): нейтрально»."""
    low = said.lower()
    return any(w[:5].lower() in low for line in getattr(scene, "factions", None) or [] for w in line.partition("(")[0].split() if len(w) >= 4)


class Topic(NamedTuple):
    """A rules topic: the line of the index (when to read it), the effect kinds the engine accepts only after it is read
    or shown, and when it goes into the system prompt by itself (v0.8.4.29.7: one row instead of a branch in auto_topics):
    `alone` — the scene alone needs it; `words` — the player's words name it while `gate` holds (by default: there is a
    scene), `props` — a container of the scene named counts too; `full` — those words want the full prompt (the router)."""

    index: str
    kinds: tuple[str, ...]
    words: re.Pattern[str] | None = None
    gate: Callable[[Snapshot], bool] | None = None
    alone: Callable[[str, Snapshot, str], bool] | None = None
    props: bool = False
    full: Callable[[Snapshot], bool] | None = None


def _named(t: Topic, snap: Snapshot, said: str) -> bool:
    return t.words is not None and (t.gate(snap) if t.gate else snap.scene is not None) and mentions(said, t.words, snap.scene if t.props else None)


def auto_topics(mode: str, snap: Snapshot, said: str = "") -> list[str]:
    """Topics the scene needs now: they go into the system prompt whole. Conditions come often and by words in a scene
    (v0.7.20.4 goldens); a conversation keeps only its own topic — the NPC's prompt grew to 28k characters with conditions,
    payment and quests in it (the author's trace, v0.7.21.3)."""
    return [k for k, t in TOPICS.items() if (t.alone is not None and t.alone(mode, snap, said)) or _named(t, snap, said)]


def wants_full(snap: Snapshot, said: str) -> bool:
    """The player's words name a topic that goes with an effect (a rumour told goes into the journal, v0.7.47): the full prompt."""
    return any(t.full is not None and t.full(snap) and _named(t, snap, said) for t in TOPICS.values())


# Rules of a topic (prompts/topics/<key>.md.j2, v0.7.20.4): out of the system prompt, read by the master with the tool
# `rules` when it needs them; the scene puts a topic in by itself when it is there (an open edge, a crime, a stranger).
# key -> Topic (v0.8.4.29.7: when it comes by itself and by which words, in one row).
TOPICS: dict[str, Topic] = {
    "conditions": Topic("состояния героя: яд, страх, сон, паралич, путы, истощение, болезни; проверки зрения и слуха (`condition`, `disease`)", ("condition",),
                   alone=lambda mode, snap, said: mode in ("exploration", "combat") or bool(snap.character and snap.character.conditions)),
    "spells": Topic("что заклинание сделало в мире: иллюзии, разговор со зверьми и мёртвыми, гадание; заклинание на себя", ()),
    "pay": Topic("покупка у не-торговца, плата за услугу или сведения, платный вариант (`option_costs`), ночлег", ()),
    "theft": Topic("кража из карманов: как её отыграть", ()),
    "items": Topic("новый предмет (`move_item.item`): жезлы, свитки, зелья, вещи с текстом; магические вещи, неопознанные и проклятые; вещь, что даёт полёт, плавание, лазание или призывает существ (`wear`, `use.summon`)", (),
                   words=FIND_WORDS, gate=lambda snap: bool(snap.scene and snap.scene.hooks)),
    "places": Topic("новое место: на открытом краю мира или объект внутри локации — лавка за городом, баня у площади (`create:place`)", ("create:place",),
                   words=PLACE_WORDS, gate=lambda snap: bool(snap.scene and snap.scene.open_edges)),
    "crime": Topic("преступления героя: убитые, розыск, стража, признание (`crime:known`)", ("crime:known", "crime:release"),
                   alone=lambda mode, snap, said: bool(snap.crimes)),
    "social": Topic("что NPC даёт словами: скидка, услуга даром, тайна, идёт с героем, пускает к себе, слава в поселении "
               "(`grant:discount`, `grant:favor`, `grant:secret`, `grant:follow`, `grant:permit`, `grant:cure`, `shift:reputation`)",
               ("grant:discount", "grant:favor", "grant:secret", "grant:follow", "grant:permit", "grant:cure", "shift:reputation"),
                   alone=lambda mode, snap, said: mode in ("social", "trade")),
    "goals": Topic("замысел игрока, которого нет готовым; высокая цель; `missing_concept`", ()),
    "equip": Topic("надеть, снять, раздеться (`equip`), герою или человеку сцены", ("equip",), words=EQUIP_WORDS),
    "water": Topic("набрать воды в бурдюк, флягу, кувшин, ведро из колодца, ручья, реки; нацедить вина, масла; вылить, облить водой или маслом (`fill`)", ("fill",),
                   words=WATER_WORDS, gate=lambda snap: True),
    "invisible": Topic("невидимый герой", (),
                   alone=lambda mode, snap, said: bool(snap.character and "invisible" in snap.character.conditions)),
    "people": Topic("новый человек (`create:npc`)", ("create:npc",)),
    "quests": Topic("новое задание: NPC просит о помощи, игрок ищет работу (`create:quest`)", ("create:quest",),
                   alone=lambda mode, snap, said: bool(snap.scene and any(BOARD.search(p.name) for p in snap.scene.props))),
    "languages": Topic("NPC не понимает героя; языки", (),
                   alone=lambda mode, snap, said: bool(snap.scene and any(not n.understands_hero for n in snap.scene.npcs))),
    "tools": Topic("действие инструментом: замок, травы, подделка, грим (`request_check` с `tool`)", ()),
    "craft": Topic("ремесло и готовка: герой куёт, шьёт, мастерит, варит зелье, жарит мясо, варит похлёбку; новый рецепт из слов игрока (`create:recipe`)", ("create:recipe",),
                   words=CRAFT_WORDS),
    "property": Topic("имущество: купить дом, землю, мельницу, лавку; купчая; место, которого нет в продаже (`create:property`); свои места, работники, животные; свой вид места — школа, причал (`new_kind`); улучшение своего места по просьбе — станок, лодка, библиотека (`create:upgrade`); конь, мул, вьюк, телега, аренда у барышника; новый зверь у барышника (`create:stock` с `animal`)", ("create:property", "create:upgrade"),
                   words=MOUNT_WORDS, gate=lambda snap: bool(snap.scene and any(n.animals for n in snap.scene.npcs))),
    "bank": Topic("деньги в долг и на хранение: вклад, кредит под залог, ячейка; ростовщик, которого нет (`create:bank`)", ("create:bank",),
                   words=BANK_WORDS),
    "services": Topic("услуги людей за плату: серебрение, закалка, оберег, отвар в дорогу; услуга, которой у человека сцены нет (`create:service`)", ("create:service",),
                   words=SERVICE_WORDS),
    "study": Topic("учёба: училище, курсы, экзамен, книги; «у кого научиться» — `find_teachers`, курс у учителя (`create:course`)", ("create:course",)),
    "bonds": Topic("дружба, романтика, соперничество, наставник: близость, подарки, признание; сцена, что сблизила (`shift:bond`)", ("shift:bond",)),
    "family": Topic("семья: предложение, свадьба, супруг, дети, содержание дома, наследник", ()),
    "underworld": Topic("преступный мир: кража со взломом, грабёж, контрабанда, скупщик краденого, воровское братство, своя банда (`create:fence`, `create:heist`, `create:org`)", ("create:fence", "create:heist", "create:org"),
                   words=UNDERWORLD_WORDS),
    "shop": Topic("своя торговля: прилавок, лавка, грамота, опт; поставщик, которого нет (`create:supplier`)", ("create:supplier",)),
    "jobs": Topic("работа за плату: игрок просит работу, которой нет у нанимателя сцены (`create:job`)", ("create:job",),
                   words=JOB_WORDS),
    "background": Topic("предыстория героя и связь NPC с его прошлым", (),
                   alone=lambda mode, snap, said: bool(snap.scene and any(n.tie for n in snap.scene.npcs))),
    "wilds": Topic("охота и рыбалка, угодья, браконьерство; зверь ушёл или вернулся, рыба пропала, новые угодья (`create:wilds`)", ("create:wilds",),
                   words=WILDS_WORDS, gate=lambda snap: bool(snap.scene and snap.scene.wilds)),
    "calendar": Topic("дата и праздники: когда ярмарка, праздник идёт, срок к празднику; свой праздник по причине (`create:festival`)", ("create:festival",),
                   words=FESTIVAL_WORDS),
    "weather": Topic("погода: ливень, туман, снег, зной, мороз и что они значат; чары или чудо меняют погоду на часы (`weather`)", ("weather",),
                   words=WEATHER_WORDS),
    "faith": Topic("вера: боги, святилища, молитва, обет, заповедь, осквернение; обет по словам героя (`vow`), новое святилище (`create:god`)", ("vow", "create:god"),
                   words=FAITH_WORDS),
    "guise": Topic("чужой облик: маскировка, кем выглядит герой, за кого его принимают", ("guise",),
                   alone=lambda mode, snap, said: bool(snap.character and snap.character.guise)),
    "make": Topic("нового нет в данных и в 5e: мастер собирает из частей (`make`) статус, навык, черту, заклинание, способность с зарядами, свойство вещи, жидкость (питьё, яд на клинок, бросок): проклятие, благословение места, редкое умение наставника, неведомое заклинание, свиток или трактат о нём", ("make",),
                   words=MAKE_WORDS),
    "factions": Topic("фракции: новая фракция, чьи это люди и стража, отношение за поступок (`create:faction`)", ("create:faction", "shift:standing"),
                   alone=lambda mode, snap, said: names_a_faction(said, snap.scene)),
    "rumors": Topic("слухи: что говорят в округе, пересказ слуха NPC, слух о герое или пущенный героем, ложь и её опровержение (`rumor`)", ("rumor",),
                   words=RUMOR_WORDS, full=lambda snap: bool(snap.scene and any("герой уже слышал" not in r for r in snap.scene.rumors))),
    "pets": Topic("питомец героя и приручение: дикий зверь в сцене, имя, близость (`shift:bond` с creature_id), помощь, разведка; бездомный зверь по причине (`create:beast`)", ("create:beast",),
                   alone=lambda mode, snap, said: bool(snap.scene and any("приручить" in c or "питомец героя" in c for c in snap.scene.creatures))),
    "games": Topic("игра на ставку с NPC: кости, карты, армрестлинг, кто кого перепьёт, загадки; поединок по вызову; арена и ставки на бои; своя игра (`create:contest`)", ("create:contest",),
                   words=BOUT_WORDS),
    "world_edits": Topic("правка готового места: у человека или в сундуке появилась или пропала вещь по причине в мире (`move_item:world>npc`, `move_item:npc>world`, `move_item:world>container`, `move_item:container>world`); новая вещь в обставленной комнате (`furnish` с `cause`)", ("move_item:world>npc", "move_item:npc>world", "move_item:world>container", "move_item:container>world",)),
    "containers": Topic("сундуки, ящики, сумки героя, товары торговца в лавке: достать, положить, отпереть, оставить (`move_item:container>hero`, `move_item:hero>container`, `open:container`, `move_item:hero>room`)",
                   ("move_item:container>hero", "move_item:hero>container", "open:container", "move_item:hero>room"),
                   words=CONTAINER_WORDS, props=True,
                   gate=lambda snap: bool(snap.scene and (any(p.container for p in snap.scene.props) or snap.character and snap.character.bags))),
    "doors": Topic("двери у выходов: заперто, часы объекта, взлом, выбить, отпереть или запереть хозяином (`open:door`)", ("open:door", "create:way"),
                   words=WAY_WORDS, alone=lambda mode, snap, said: bool(snap.scene and any(e.door for e in snap.scene.exits))),
    "captives": Topic("пленные и существа после боя, перемирие, продажа пленника, чужие вещи героя, герой в плену (`owner`)", ("owner",),
                   alone=lambda mode, snap, said: bool(snap.scene and snap.scene.creatures)),
}


def topic_for(kind: str) -> str:
    """The topic whose rules an effect kind needs ("" — none)."""
    return next((k for k, t in TOPICS.items() if kind in t.kinds), "")


def topic_fields(key: str) -> str:
    """The fields of a topic's effects: they come with its rules, not in every turn's tool description (v0.7.69)."""
    tags = TOPICS[key].kinds
    lines = [effect_line(cls) for cls in effect_classes() if class_tag(cls) in tags]
    return "Поля (? — необязательное): " + "; ".join(lines) if lines else ""


def topic_text(key: str) -> str:
    fields = topic_fields(key)
    return render(f"topics/{key}.md.j2") + (f"\n{fields}" if fields else "")


def system_prompt(mode: str, snap: Snapshot, npc: SceneNpc | None, tone: str = DEFAULT_TONE, said: str = "") -> str:
    character: CharacterSheet | None = snap.character
    if snap.world is not None and snap.world.tone:
        tone = snap.world.tone
    context: dict[str, object] = {
        "mode": mode,
        "trade": snap.trade,
        "quests": snap.quests,
        "combat": snap.combat,
        "crimes": snap.crimes,
        "world": snap.world,
        "character": character,
        "coins": coins(character.gold_cp) if character else "",
        "reward_left": coins(character.reward_left_cp) if character and character.reward_left_cp is not None else "",
        "scene": snap.scene,
        "summaries": snap.summaries,
        "limits": snap.limits,
        "tone": tone,
        "gender_rule": gender_rule(character.gender if character else "other"),
        "entry": False,
    }
    shown = auto_topics(mode, snap, said)
    context["auto_topics"] = shown
    scene_only = SCENE_TOPICS if mode in ("social", "trade") else set()  # a conversation does not search or carry
    context["topic_index"] = [(k, v.index) for k, v in TOPICS.items() if k not in shown and k not in scene_only]
    if mode == "exploration":
        return render("exploration.md.j2", **context)
    if mode == "combat":
        return render("combat.md.j2", **context)
    if npc is None:
        raise ValueError(f"mode {mode} needs an NPC")
    return render(f"{mode}.md.j2", npc=npc, npc_gender_rule=npc_gender_rule(npc.gender), **context)


def entry_prompt(snap: Snapshot, tone: str = DEFAULT_TONE) -> str:
    """The entry turn's own prompt (v0.7.34.3): the player only came in — the room furnished and told, nothing else.
    No hero sheet, no rules of play: half the full turns of the author's trace were these, at ~30k characters each."""
    if snap.world is not None and snap.world.tone:
        tone = snap.world.tone
    character = snap.character
    return render("enter.md.j2", mode="exploration", entry=True, scene=snap.scene, world=snap.world, character=None,
                  quests=snap.quests, crimes=snap.crimes, summaries=snap.summaries, limits=snap.limits, tone=tone,
                  reward_left=coins(character.reward_left_cp) if character and character.reward_left_cp is not None else "",
                  gender_rule=gender_rule(character.gender if character else "other"))


def quest_act_prompt(snap: Snapshot) -> str:
    """The designer's prompt (v0.7.39.6): builds the act of a taken quest that opened; the engine's frame is the input."""
    return render("quest_act.md.j2", world=snap.world)


def prepare_prompt(snap: Snapshot, subject: str, room_left: int = 3, goal: bool = False) -> str:
    """The second line's prompt (0.106.0): the master readies ahead what the hero will meet — a room's furnishing, a
    board's orders, a quest of a person around; the engine's frame is the input, the hero is not in it."""
    character = snap.character
    return render("prepare.md.j2", subject=subject, room_left=room_left, world=snap.world, goal=goal,
                  quests_rules=topic_text("quests") if subject != "furnish" else "",
                  tone=snap.world.tone if snap.world is not None and snap.world.tone else DEFAULT_TONE,
                  gender_rule=gender_rule(character.gender if character else "other"))


def short_prompt(mode: str, snap: Snapshot, npc: SceneNpc | None, tone: str = DEFAULT_TONE) -> str:
    """The short system prompt of the router (v0.7.20.4): only words, the scene in brief."""
    if snap.world is not None and snap.world.tone:
        tone = snap.world.tone
    character = snap.character
    return render("short.md.j2", mode=mode, npc=npc if mode != "exploration" else None, scene=snap.scene, world=snap.world,
                  character=character, tone=tone, gender_rule=gender_rule(character.gender if character else "other"),
                  npc_gender_rule=npc_gender_rule(npc.gender) if npc else "")


def turn_prompt(mode: str, kind: str, player_input: str, snap: Snapshot, npc: SceneNpc | None) -> str:
    return render("turn.md.j2", mode=mode, kind=kind, input=player_input, history=snap.history,
                  room_name=snap.scene.room_name if snap.scene else "",
                  npc_name=npc.name if npc else "", world=snap.world)


def made_check_prompt(what: str, said: str, history: list[str], hooks: list[str], effect: str, topics: list[str],
                      made: list[str] | None = None) -> str:
    """The checker of a made thing (v0.8.4.41.1): what was promised against what its fields do, with the topics' vocabulary."""
    rules = "\n\n".join(topic_text(k) for k in topics)
    return render("made_check.md.j2", what=what, said=said, history=history, hooks=hooks, effect=effect, rules=rules, made=made or [])


def summary_prompt(kind: str, subject_id: str, previous: str, events: list[str]) -> str:
    return render("summary.md.j2", kind=kind, subject_id=subject_id, previous=previous, events=events)


DEFAULT_IMAGE_STYLE = "book illustration, ink and watercolor, muted earthy palette, dark fantasy"


def image_instructions(template: str, max_chars: int, adult: bool = False) -> str:
    """How the image family `template` wants its prompt written (prompts/images/<template>.md.j2, v0.7.35)."""
    return _block(f"images/{template}.md.j2", "instructions", max_chars=max_chars, adult=adult)


def image_frame(event: str, place: str, time: str, hero: str, people: list[str]) -> str:
    return render("images/_frame.md.j2", event=event, place=place, time=time, hero=hero, people=people,
                  cast=image_cast(hero, people))


_SEX = {"женщина": "woman → girl", "мужчина": "man → boy"}


def image_cast(hero: str, people: list[str]) -> list[str]:
    """Who is a woman and who a man, by the words the client puts in the lines (v0.7.38.7): the agent guessed the sex
    of a half-elf from Russian endings and drew a heroine as `1boy`."""
    out = []
    for line, name, who in [(hero, hero.split(",")[0], "герой (в рассказе — «ты»)")] + [
            (p, p.split(" — ")[0], "") for p in people]:
        words = {w.strip() for w in line.replace(";", ",").split(",")}
        sex = next((v for k, v in _SEX.items() if k in words), "")
        if sex and name.strip():
            out.append(f"{name.strip()}{' — ' + who if who else ''}: {sex}")
    return out


def image_prompt(template: str, scene: str, style: str) -> str:
    """The prompt the image model gets: the agent's scene and the world's style, in the family's order."""
    return _block(f"images/{template}.md.j2", "prompt", scene=scene.strip().rstrip("."), style=(style or DEFAULT_IMAGE_STYLE).strip().rstrip(".")).strip()


def _block(name: str, block: str, **context: object) -> str:
    t = _env.get_template(name)
    return "".join(t.blocks[block](t.new_context(context))).strip() + "\n"
