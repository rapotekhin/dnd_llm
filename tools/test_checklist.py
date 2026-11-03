"""The author's test checklist (tools/checklist.py): every kind on its sheet, a command per row, the marks kept on a rebuild."""

import sys
from pathlib import Path

import pytest

openpyxl = pytest.importorskip("openpyxl")
sys.path.insert(0, str(Path(__file__).resolve().parent))
import checklist  # noqa: E402

SHEETS = ["Обычные предметы", "Магические предметы", "Монстры", "Способности", "Заклинания", "Состояния", "Сопротивления и иммунитеты", "Типы урона"]


@pytest.fixture(scope="module")
def data() -> "checklist.Data":
    return checklist.Data("frontier")


def _rows(path: Path, sheet: str) -> list[dict]:
    ws = openpyxl.load_workbook(path)[sheet]
    head = [c.value for c in ws[1]]
    return [dict(zip(head, r)) for r in ws.iter_rows(min_row=2, values_only=True)]


def test_every_kind_has_its_sheet_with_a_command_per_row(tmp_path: Path, data: "checklist.Data") -> None:
    out = tmp_path / "c.xlsx"
    counts = checklist.build(data, out)
    assert list(counts) == SHEETS
    assert counts["Монстры"] == len(data.monsters)
    assert counts["Заклинания"] == len(data.spells)
    assert counts["Обычные предметы"] + counts["Магические предметы"] == len(data.items)
    assert counts["Способности"] == len(data.features) + len(data.traits)
    goblin = next(r for r in _rows(out, "Монстры") if r["id"] == "goblin")
    assert goblin["Команда"] == "spawn goblin" and "Ятаган" in goblin["Способности"]
    assert next(r for r in _rows(out, "Заклинания") if r["id"] == "fireball")["Команда"] == "spell fireball"
    assert any(r["Герою"] == "immune fire" for r in _rows(out, "Сопротивления и иммунитеты"))
    conds = {r["id"]: r for r in _rows(out, "Состояния")}
    assert conds["frightened"]["Герою"] == "cond frightened" and conds["frightened"]["Юниту"] == "@<цель> cond frightened"
    assert "outlined" in conds and "burning" not in conds and "exhaustion_3" not in conds
    assert "Борода" in conds["poisoned"]["Накладывают монстры"]
    dmg = {r["id"]: r for r in _rows(out, "Типы урона")}
    assert set(dmg) == set(data.damage) and dmg["fire"]["Герою без боя"].startswith("dmg 2d6 fire")
    assert "Огненный шар" in dmg["fire"]["Заклинания"] and "Длинный меч" in dmg["slashing"]["Оружие"]
    assert "silver → 8" in dmg["slashing"]["Немагическое"] and not dmg["fire"]["Немагическое"]
    magic = {r["id"]: r for r in _rows(out, "Магические предметы")}
    brooch = magic["brooch_of_shielding"]["Как проверить"]
    assert "Настроиться" in brooch and "dmg 4d1 force crit → 4" in brooch
    plain = {r["id"]: r for r in _rows(out, "Обычные предметы")}
    assert "хиты +2к4+2" in plain["healing_potion"]["Как проверить"] and "КД 16" in plain["chain_mail"]["Как проверить"]
    assert all(r["Проверено"] is False and r["Есть баг"] is False for r in _rows(out, "Монстры"))
    assert plain["chain_mail"]["Автотест"] in checklist.AUTO_FILL and "КД 16" in plain["chain_mail"]["Автотест: что проверено"]
    assert {r["Автотест"] for r in _rows(out, "Состояния")} == {"работает"}


def test_a_mark_typed_as_a_formula_is_read_as_the_author_meant() -> None:
    assert checklist.flag("=FALSE()") is False and checklist.flag("=TRUE()") is True
    assert checklist.flag(True) is True and checklist.flag(None) is False


def test_the_marks_stay_with_their_rows_on_a_rebuild(tmp_path: Path, data: "checklist.Data") -> None:
    out = tmp_path / "c.xlsx"
    checklist.build(data, out)
    wb = openpyxl.load_workbook(out)
    ws = wb["Заклинания"]
    head = [c.value for c in ws[1]]
    for row in ws.iter_rows(min_row=2):
        if row[head.index("id")].value == "fireball":
            row[head.index("Есть баг")].value = True
            row[head.index("Комментарий")].value = "урон не делится"
    wb.save(out)
    checklist.build(data, out)
    fireball = next(r for r in _rows(out, "Заклинания") if r["id"] == "fireball")
    assert fireball["Есть баг"] is True and fireball["Комментарий"] == "урон не делится" and fireball["Проверено"] is False
