"""
D&D rules database lookup tool. OOP pattern for reuse in exploration agents.
"""


class RuleDbLookupTool:
    """
    Lookup D&D rules in database.
    Reusable by exploration agents.
    """

    def run(self, rule_name: str, rule_section: str) -> str:
        """Lookup D&D rules in database."""
        # TODO: integrate with actual rules DB
        return "res"

    def __call__(self, rule_name: str, rule_section: str) -> str:
        return self.run(rule_name, rule_section)


# Singleton for reuse
_rule_db_lookup_tool = RuleDbLookupTool()


def rule_db_lookup(rule_name: str, rule_section: str) -> str:
    """Standalone function for direct calls."""
    return _rule_db_lookup_tool.run(rule_name, rule_section)
