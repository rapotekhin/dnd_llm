"""Shared server services handed to every Session: settings, model catalog, budget, item library."""

from dataclasses import dataclass

from .config import Settings
from .images import ImageCatalog, ImagePrices
from .llm.budget import DailyBudget
from .llm.catalog import ModelCatalog, ModelFactory
from .llm.library import ItemLibrary
from .llm.providers import PICKER
from .trace import TraceWriter


@dataclass
class Services:
    settings: Settings
    models: ModelCatalog
    budget: DailyBudget
    library: ItemLibrary
    model_factory: ModelFactory | None = None  # None with the stub turn handler
    trace: TraceWriter | None = None
    images: ImageCatalog | None = None  # filled in __post_init__ when not given

    def __post_init__(self) -> None:
        if self.images is None:
            self.images = ImageCatalog(self.settings.image_models, self.settings.image_model, ImagePrices(None))

    @classmethod
    def create(cls, settings: Settings, model_factory: ModelFactory | None = None) -> "Services":
        PICKER.bind(settings.data_dir / "provider_bills.json")
        return cls(
            settings=settings,
            models=ModelCatalog(settings.models, settings.model),
            budget=DailyBudget(settings.data_dir / "budget.json", settings.daily_budget_usd, settings.data_dir / "budget_limit.json"),
            library=ItemLibrary(settings.data_dir / "items" / "library.jsonl"),
            model_factory=model_factory,
            trace=TraceWriter(settings.data_dir / "traces", settings.trace),
            images=ImageCatalog(settings.image_models, settings.image_model, ImagePrices(settings.data_dir / "image_prices.json"),
                                settings.a1111_url),
        )
