"""Shared server services handed to every Session: settings, model catalog, budget, item library."""

from dataclasses import dataclass

from .config import Settings
from .llm.budget import DailyBudget
from .llm.catalog import ModelCatalog, ModelFactory
from .llm.library import ItemLibrary
from .trace import TraceWriter


@dataclass
class Services:
    settings: Settings
    models: ModelCatalog
    budget: DailyBudget
    library: ItemLibrary
    model_factory: ModelFactory | None = None  # None with the stub turn handler
    trace: TraceWriter | None = None

    @classmethod
    def create(cls, settings: Settings, model_factory: ModelFactory | None = None) -> "Services":
        return cls(
            settings=settings,
            models=ModelCatalog(settings.models, settings.model),
            budget=DailyBudget(settings.data_dir / "budget.json", settings.daily_budget_usd, settings.data_dir / "budget_limit.json"),
            library=ItemLibrary(settings.data_dir / "items" / "library.jsonl"),
            model_factory=model_factory,
            trace=TraceWriter(settings.data_dir / "traces", settings.trace),
        )
