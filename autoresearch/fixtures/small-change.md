# Add "Recently Viewed" Section to Character Library

## Context

The character library (`CharacterLibraryPage.tsx`) shows all saved characters for a ruleset but has no concept of recency beyond the card timestamps. Players with many characters have to scroll or search to find the one they were just working on. Adding a "Recently Viewed" row at the top of the library would make this faster.

## Plan

### Step 1: Add recently viewed tracking to the catalog store

Modify `useCharacterCatalogStore` in `apps/web/src/stores/characterCatalogStore.ts` to track recently viewed character IDs.

- Add `recentlyViewed: string[]` to the store state (max 3 IDs)
- Add a `markViewed(characterId: string)` action that pushes the ID to the front of the array, deduplicates, and trims to 3
- Persist this in IndexedDB alongside the existing character data

### Step 2: Trigger markViewed when a character is opened

Call `markViewed()` when a character is loaded for editing or play mode.

- In the character creation store's load flow, call `markViewed` after `loadCharacter()` succeeds
- Same for when entering play mode via the Play button on `CharacterCard.tsx`

### Step 3: Build the Recently Viewed row component

Create a new component that renders up to 3 character cards in a horizontal row above the main library grid.

- Reuse the existing `CharacterCard` component
- Show a "Recently Viewed" heading with a subtle divider
- If no recently viewed characters exist, don't render the section at all
- Style it to match the existing library layout (Tailwind, slate/amber theme)

### Step 4: Integrate into CharacterLibraryPage

Add the recently viewed row above the existing character grid in `CharacterLibraryPage.tsx`.

- Pull `recentlyViewed` from the catalog store
- Filter out any IDs that no longer exist in the catalog (deleted characters)
- Pass the matching character objects to the new component

### Step 5: Test

- Verify recently viewed updates when opening a character
- Verify deleted characters don't appear in recently viewed
- Verify the section hides when empty
- Check that it looks right on mobile
