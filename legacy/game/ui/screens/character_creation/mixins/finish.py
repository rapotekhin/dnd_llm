"""Character creation: finalize build into Character."""


class CharacterCreationFinishMixin:
    def _finish_creation(self):
        """Finish character creation and return Character object"""
        print("=" * 50)
        print("Character Created!")
        print(f"Name: {self.build.name}")
        print(f"Alignment: {self.build.alignment}")
        print(f"Race: {self.build.race}")
        print(f"Subrace: {self.build.subrace}")
        print(f"Class: {self.build.class_type}")
        print(f"Background: {self.build.background}")
        print(f"Abilities: {self.build.abilities}")
        print(f"Cantrips: {self.build.cantrips}")
        print(f"Spells: {self.build.spells}")
        print(f"Proficiency choices: {self.build.proficiency_choices_selected}")
        print(f"Features: {self.build.features}")
        print(f"Feature choices: {self.build.feature_choices}")
        print("=" * 50)
        
        # Create Character from CharacterBuild
        player = self.build.create_character()
        print("=" * 50)
        print("Character Created!")
        print(f"Name: {player.name}")
        print(f"Alignment: {player.alignment}")
        print(f"Race: {player.race.name if player.race else 'None'}")
        print(f"Subrace: {player.subrace.name if player.subrace else 'None'}")
        print(f"Class: {player.class_type.name if player.class_type else 'None'}")
        print(f"Background: {player.background or 'None'}")
        print(f"Abilities: STR={player.abilities.str}, DEX={player.abilities.dex}, CON={player.abilities.con}, INT={player.abilities.int}, WIS={player.abilities.wis}, CHA={player.abilities.cha}")
        if player.sc:
            cantrips = [s.name for s in player.sc.cantrips]
            spells = [s.name for s in player.sc.leveled_spells]
            print(f"Cantrips ({len(cantrips)}): {', '.join(cantrips) if cantrips else 'None'}")
            print(f"Spells ({len(spells)}): {', '.join(spells) if spells else 'None'}")
            print(f"Prepared spells ({len(player.prepared_spells)}): {', '.join([s.name for s in player.prepared_spells]) if player.prepared_spells else 'None'}")
        else:
            print("Cantrips: None (not a spellcaster)")
            print("Spells: None (not a spellcaster)")
        print(f"Proficiencies ({len(player.proficiencies)}): {', '.join([p.name for p in player.proficiencies[:10]])}{'...' if len(player.proficiencies) > 10 else ''}")
        print(f"Features ({len(player.features)}): {', '.join(player.features)}")
        print(f"Inventory items: {len([item for item in player.inventory if item is not None])}")
        for item in player.inventory:
            if item:
                print(f"Item: {item.name}, category: {item.category}, cost: {item.cost}, weight: {item.weight}, equipped: {item.equipped}")
        print("=" * 50)
        return player
