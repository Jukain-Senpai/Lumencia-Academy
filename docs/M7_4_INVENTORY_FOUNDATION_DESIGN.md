# M7.4 Inventory Foundation Design

## Status and scope

Approved for implementation after M7.3 commit `3892f317598812c91df873b3644c74dd9b269a90`
and manual F6 acceptance. M7.4 adds one shared runtime inventory, one authored
Healing Herb, cross-mode party HP, Battle and Exploration use, resource overflow,
and node-owned leftovers. It does not add saving, money, shops, time, rest,
equipment, progression, or M7.5 work.

The accepted M7.2 marker-polish issue remains deferred. The new leftover badge is
functional and readable but does not redesign the reusable or roadblock badges.

## Runtime ownership

`GameState` owns exactly three relevant transient models:

```text
GameState
├─ ExplorationState
│  └─ leftover_rewards by active node
├─ InventoryState
│  └─ owned quantities only
└─ PartyRuntimeState
   └─ stable party identity + current/max HP
```

`PartyRuntimeState` is the sole cross-mode HP authority. Existing `BattleUnit`
objects remain battle-local working representations with combat stats, position,
and battle status. Exploration never creates BattleUnits.

On battle entry, the sandbox validates its party fixtures against PartyRuntimeState,
captures an encounter-entry HP snapshot, builds its existing BattleUnits, and
hydrates their HP from that snapshot. Victory synchronizes final party HP back
exactly once. Defeat does not publish defeated HP. Restart rebuilds existing
combat-local state and reapplies the encounter-entry snapshot; it does not invent
full health when runtime HP exists.

Global item consumption is immediate and permanent. Restart never refunds an
item. This is intentionally independent from the HP snapshot reset.

## Items and inventory

Item definitions are immutable authored dictionaries returned as deep copies.
Runtime inventory stores only quantities. Supported semantic contexts are
`BATTLE_ONLY`, `EXPLORATION_ONLY`, and `BOTH`.

The only production item is:

```gdscript
{
    "id": "healing_herb",
    "display_name": "Healing Herb",
    "use_context": "BOTH",
    "effect": {"type": "heal", "amount": 18},
}
```

The heal value **18 is PROTOTYPE / TUNABLE — NOT CANON BALANCE**. All consumers
read it from the definition. Healing clamps at Max HP. Any living current-party
member is valid, including a full-HP member; using it at full HP consumes the Herb
and heals zero. A defeated member is rejected without consumption or revival.

Every item stack is capped at 10. `gain_item()` reports requested, accepted, and
remaining quantities. Invalid/unknown/non-positive gain and consume requests do
not mutate state. Quantity zero is represented by absence from the quantity map.

## Exploration flow

The compact Items panel lists `Healing Herb ×N`, then living and defeated party
members with current/max HP. Selecting a living target applies PartyRuntimeState
healing and consumes one item through the shared InventoryState. Back closes or
steps out of the small panel without mutation.

Ruins Approach authors an item reward inside its resource content:

```gdscript
"reward": {
    "type": "item",
    "item_id": "healing_herb",
    "quantity": 2,
}
```

The primary resource completes once even when only part of the reward fits.
Overflow is stored in `ExplorationState.leftover_rewards[node_id]` as item ID and
quantity. Thus current, completed, roadblocked, reusable, and leftover remain
independent facts. A completed node with leftovers presents `Collect Leftover`.
Only the accepted quantity is removed; a full inventory leaves the source intact.
A readable `ITEM ×N` marker badge composes with existing marker facts.

## Battle flow

`Item` is an additive root action for every player-controlled unit. It opens the
single-item list, then living-party target selection through existing unit cards.
Successful use heals the BattleUnit, consumes one shared Herb, and delegates to
the existing `_finish_completed_action()` path, preserving one Burn/status tick
and one turn advance. Item-list Back and target-list Back consume neither item nor
turn. Defeated allies, enemies, stale targets, and zero quantity are rejected.

## Reliability and scale assumptions

The prototype has one item, six stable party members, and one leftover per node;
linear scans are intentionally sufficient. All state is local and transient, so
there are no network, privacy, or availability concerns. Defensive copies and
stable IDs protect ownership boundaries. GameState reset clears inventory,
leftovers through Exploration runtime reset, and party HP back to prototype
defaults. Ordinary scene transitions never reset them.

## UI direction

The UI preserves Lumencia's restrained enchanted-field-map language: dark violet
translucent panels, gold hierarchy, compact readable controls, and explicit state
copy. The visual anchor is the map marker's gold `ITEM ×N` remnant badge. Battle
Item controls reuse the established cool-blue combat button system. No new fonts,
assets, animation system, or large menu framework are introduced.

## Decision log

- Chose one `PartyRuntimeState` over storing permanent BattleUnits or UI-local HP;
  this preserves combat isolation and enables legitimate Exploration healing.
- Chose encounter-entry HP snapshots for Restart; arbitrary full-health fixture
  resets would violate cross-mode authority.
- Chose permanent inventory consumption across Restart; global resources are not
  transactionally rolled back with combat-local state.
- Chose authored definitions plus quantity-only InventoryState instead of a large
  item database or manager stack.
- Chose node-owned leftover runtime state instead of replaying resource content or
  storing remnants in the UI.
- Chose additive compact UI and existing action lifecycle over a general inventory
  screen or parallel battle turn processor.
- Deferred persistence to M7.8 and all money/time/rest/progression work to later
  milestones.
