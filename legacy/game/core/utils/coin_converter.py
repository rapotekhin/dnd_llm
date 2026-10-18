class CoinConverter:

    def __init__(self) -> None:
        self.coin_map = {
            "cp": 1,
            "sp": 10,
            "ep": 50,
            "gp": 100,
            "pp": 1000,
        }

    def __call__(self, amount: int | str, unit: str | None = None) -> int:

        if isinstance(amount, str) and " " in amount:
            unit = amount.split(" ")[1]
            amount = int(amount.split(" ")[0])
        elif isinstance(amount, str):
            raise ValueError(f"Invalid amount: {amount}")

        if unit not in self.coin_map:
            raise ValueError(f"Invalid unit: {unit}")

        return int(amount) * self.coin_map[unit]

coin_converter = CoinConverter()