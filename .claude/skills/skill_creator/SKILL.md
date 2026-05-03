---
name: skill_creator
description: Use this skill when the user asks to create, add, or scaffold a new skill in the Between the Rolls repository — phrases like "создай скилл", "добавь скилл", "сделай скилл для X", "нужен скилл который...", "create skill", "add a skill", "scaffold skill". This project-local skill OVERRIDES the global anthropic-skills:skill-creator and must be used instead, because skills here have a specific dual-format convention (both .claude/skills/ for Claude Code and .cursor/rules/ for Cursor). Do NOT call anthropic-skills:skill-creator in this repo — its output is incompatible with the local convention.
---

# skill_creator (project-local)

Создаёт новый скилл в этом репозитории. **Обязательно** делает **двойной формат**, чтобы скилл работал и в Claude Code, и в Cursor:

1. `.claude/skills/<name>/SKILL.md` — каноническая полная версия
2. `.cursor/rules/<name>.mdc` — тонкий указатель для Cursor с frontmatter

> ⚠️ Этот скилл **переопределяет** глобальный `anthropic-skills:skill-creator`. Не вызывай его в этом репо — он не знает про дубль для Cursor.

## Конвенции имён

- **snake_case** с подчёркиваниями: `docs_lookup`, `release_notes_updater`, `combat_designer`
- Имя скилла = имя папки = имя `.mdc` файла = значение `name:` во frontmatter
- Английский, lowercase, без пробелов и дефисов

## Алгоритм

1. **Уточни у пользователя (если непонятно):**
   - Имя скилла (snake_case)
   - Что он делает в одной фразе
   - Когда срабатывать (триггер-фразы, действия пользователя, или паттерны файлов)
   - Это «знание-извлекатель» (читает что-то и отвечает) или «изменятор» (правит файлы)?

2. **Сформулируй description** для frontmatter — это критично, по нему агент решает, когда вызывать скилл:
   - Начинай со «Use this skill when...»
   - Перечисли конкретные триггер-фразы (RU и EN, если уместно)
   - Перечисли паттерны кода/файлов, при которых срабатывает
   - Добавь «Do NOT use for...» если есть очевидные ложные срабатывания
   - Целевая длина: 2-4 предложения, информативно, без воды

3. **Создай `.claude/skills/<name>/SKILL.md`** по шаблону ниже.

4. **Создай `.cursor/rules/<name>.mdc`** по шаблону ниже.

5. **Покажи пользователю** оба файла + как и когда они будут срабатывать.

## Шаблон SKILL.md

```markdown
---
name: <skill_name>
description: <2-4 предложения про когда триггерить, с конкретными фразами и паттернами>
---

# <Skill Name>

<Одна строка: что делает скилл и зачем.>

## Когда срабатывать

- <Триггер 1>
- <Триггер 2>
- <Триггер 3>

**НЕ срабатывает на:**
- <Очевидное ложное срабатывание 1>
- <Очевидное ложное срабатывание 2>

## Алгоритм работы

1. <Шаг 1>
2. <Шаг 2>
3. <Шаг 3>

## <Дополнительные секции по необходимости>

- Шаблоны / форматы вывода
- Что НЕ делать (anti-patterns)
- Чеклист после работы
- Связанные документы

## Связанные

- Ссылки на `docs/`, другие скиллы, ADR
```

**Стиль:**
- Русский для человеческого текста, английский для кода/идентификаторов
- Markdown-заголовки и буллеты, не сплошной текст
- Конкретные примеры > абстрактные правила
- Anti-patterns обязательно — что не делать важно так же, как что делать
- Не пиши простыни — лучше короче и точнее (как существующие скиллы — `docs_lookup`, `docs_updater`, `release_notes_updater`)

## Шаблон .cursor/rules/<name>.mdc

```markdown
---
description: <тот же description, что и в SKILL.md>
globs:
  - "<glob паттерн 1, если применимо>"
  - "<glob паттерн 2>"
alwaysApply: false
---

# <skill_name>

<Одна строка: что делает.>

The full procedure is in [.claude/skills/<name>/SKILL.md](mdc:.claude/skills/<name>/SKILL.md).

Read that file when this rule triggers, then follow it.

**Quick reference:**

<2-3 ключевых факта или таблица — то, что Cursor-агент должен помнить, даже если не дочитал SKILL.md>
```

## Когда добавлять `globs:` в .mdc

| Тип скилла | Использовать globs? |
|---|---|
| Концептуальный / поисковый (lookup-style) | ❌ только `description` |
| Реагирует на правки конкретных файлов | ✅ `globs` для авто-attach |
| Реагирует на правки одного файла | ✅ `globs: ["имя_файла.md"]` |

Примеры:
- `docs_lookup` — без globs (триггер по вопросу пользователя)
- `docs_updater` — с globs на `game/core/gameplay/**`, `game/ui/screens/**` и т.п.
- `release_notes_updater` — с globs на `RELEASE_NOTES.md`

## Конвенции этого репозитория

При создании нового скилла учитывай:

- **Проект — Between the Rolls**, Russian-first D&D RPG с LLM-ГМ. Тон скилла должен быть совместим со столпами проекта (см. `docs/vision/pillars.md`).
- **Если скилл связан с документацией** — используй структуру `/docs` (vision/design/narrative/tech/production).
- **Если скилл связан с гейплеем** — учитывай главный принцип «LLM is GM, not engine» (ADR-0001).
- **Если скилл создаёт текст для игрока** — на русском, без жаргона.
- **Если скилл создаёт код** — английские идентификаторы, русские комментарии в стиле кодовой базы.

## Чеклист после создания скилла

- [ ] Имя — snake_case, согласовано с уже существующими (`docs_lookup`, `docs_updater`, `release_notes_updater`)
- [ ] `description` начинается с «Use this skill when...» и содержит конкретные триггеры
- [ ] Оба файла созданы: SKILL.md и .mdc
- [ ] `.mdc` ссылается на SKILL.md через `mdc:` синтаксис
- [ ] description в обоих файлах идентичен
- [ ] Если применимо — `globs` указаны в .mdc
- [ ] `alwaysApply: false` в .mdc (если не задумано иначе)
- [ ] Стиль и тон совместимы с другими скиллами в проекте
- [ ] Скилл реально нужен в каждой сессии, а не одноразовая задача (для одноразового — лучше просто инструкция в чате)

## Что НЕ делать

- ❌ Не использовать `anthropic-skills:skill-creator` в этом репо — он создаст только Claude-формат без Cursor-зеркала
- ❌ Не создавать скилл только в `.cursor/rules/` без `.claude/skills/` — теряется единый источник
- ❌ Не дублировать содержимое SKILL.md в .mdc — .mdc должен быть тонким указателем
- ❌ Не использовать дефисы или camelCase в именах
- ❌ Не делать скилл из задачи, которая встретится один раз — это засоряет контекст
- ❌ Не делать `alwaysApply: true` без веской причины — съедает токены каждой сессии Cursor
- ❌ Не описывать `description` абстрактно («helps with stuff») — нужны конкретные триггер-фразы

## Связанные

- Существующие скиллы как референс стиля:
  - [.claude/skills/docs_lookup/SKILL.md](../docs_lookup/SKILL.md)
  - [.claude/skills/docs_updater/SKILL.md](../docs_updater/SKILL.md)
  - [.claude/skills/release_notes_updater/SKILL.md](../release_notes_updater/SKILL.md)
- Зеркальные .mdc для Cursor:
  - [.cursor/rules/docs_lookup.mdc](../../../.cursor/rules/docs_lookup.mdc)
  - [.cursor/rules/docs_updater.mdc](../../../.cursor/rules/docs_updater.mdc)
  - [.cursor/rules/release_notes_updater.mdc](../../../.cursor/rules/release_notes_updater.mdc)
- Документация по форматам:
  - Claude Code: https://code.claude.com/docs/en/memory
  - Cursor rules: https://cursor.com/docs/context/rules
