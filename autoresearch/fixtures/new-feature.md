# Add "Level Up" Feature to Character Creator

## Context

Players currently have no way to level up a character after creation. To go from level 3 to level 4, they'd have to manually edit the character draft and know the SRD 5.1 rules for what changes at each level. We want a guided "Level Up" button that walks the player through the process, including multi-classing when eligible.

The existing data model already supports multi-classing (`classLevels: ClassLevelDraft[]` in the draft type), and the core package has `meetsMulticlassPrerequisites()` for checking eligibility. The character sheet builder (`buildCharacterSheet()`) already computes derived stats from the draft, so if we update the draft correctly, everything downstream should just work.

## Plan

### Step 1: Add a "Level Up" button to the character card and play mode

Add a Level Up button in two places:
- On `CharacterCard.tsx` in the library, next to Edit/Play/Delete
- In the play mode header area

The button should be disabled if the character is already level 20.

### Step 2: Build the Level Up flow as a modal/wizard

Create a multi-step modal that guides the player through leveling up. The steps depend on what happens at their new level.

**Step 2a: Class selection**
- If the character has only one class, default to leveling that class
- Show available multiclass options with prerequisite checks using `meetsMulticlassPrerequisites()`
- Display what each class would gain at its next level

**Step 2b: Hit points**
- Roll or take average for the new hit die
- Apply Constitution modifier

**Step 2c: New features**
- Display class features gained at the new level
- If a subclass choice is available (e.g., level 3 for most classes), show subclass picker

**Step 2d: Ability Score Improvement / Feat**
- If the new level grants an ASI (levels 4, 8, 12, 16, 19), show the choice:
  - Increase two ability scores by 1, or one by 2
  - Or pick a feat
- Enforce the 20 cap on ability scores

**Step 2e: Spells**
- If the class has spellcasting, show new spell slots and let them pick new spells known
- Handle cantrip additions if applicable

### Step 3: Apply the level up to the character draft

When the player confirms, update the `CharacterDraft`:
- Increment `characterLevel`
- Update the relevant entry in `classLevels` (or add a new one for multiclass)
- Add ASI choices, subclass selection, new spells, etc.
- Save back to the catalog store

### Step 4: Handle multi-class edge cases

- Proficiency bonus changes based on total character level, not class level — verify `proficiency.ts` handles this
- Spell slot calculation uses the multiclass table — verify `calculateSpellSlots()` handles mixed caster levels
- Some features are based on class level vs character level — make sure the UI shows the right one

### Step 5: Add level up history

Track what was gained at each level so players can review their progression. Store this as metadata on the draft or as a separate field.

### Step 6: Test

- Level up a single-class character from 1 to 5
- Multiclass a Fighter 5 into Wizard and verify prerequisites
- Verify ASI at level 4, subclass at level 3
- Check spell slot calculations for multiclass casters
- Verify level 20 cap
