# M7.5 Reusable Hub and Minimal Economy Design

## Status and purpose

Approved for implementation after M7.4 commit
`db6af16d14c04f0201d691343f0af27fe69fdd22` and manual F6 acceptance.
This milestone proves that a reusable location can offer a buy-only Shop while
its one-time VN content, roadblock, reveal effect, and map navigation remain
independent. The traveling supply merchant at Riverside Camp is a prototype
fixture, not canonical Forest Exam lore.

## Assumptions and scale

The current prototype has one active Exploration context, one shop, one offer,
and six party members. Money is an integer local to the running game session.
There is no network or account data. Synchronous transactions and small
Dictionary lookups are sufficient. GameState and ExplorationState retain their
current ownership; the controller only requests actions and displays results.

## Runtime ownership and authored data

`GameState` owns one nonnegative money balance, with narrow query, gain, and
spend methods. `GameState.reset_state()` clears it; map/VN/Battle transitions
do not. Money is absent from the M2 save payload, whose four keys remain
`sequence`, `node`, `flags`, and `bonds`. M7.8 owns persistence.

Riverside Camp adds optional `hub_actions` to its authored node Dictionary:

```gdscript
"hub_actions": [{
    "id": "prototype_supply_shop",
    "type": "shop",
    "display_name": "Shop",
    "catalog": [{"item_id": "healing_herb", "price": 4}],
}]
```

The `4` money price is **PROTOTYPE / TUNABLE — NOT CANON BALANCE**. The only
offer is one Healing Herb per purchase. `hub_actions` is independent of
`primary_content`, completion, reveal, roadblock, and leftover rewards. Its
array shape leaves room for a later finite-use action without introducing
usage counters now. ExplorationState validates the optional shape, unique
action and offer IDs, positive integer prices, and reusable-node ownership.
Existing deep-copy read APIs protect the authored nested catalog.

## Purchase contract

The map supplies the expected current node, action ID, and selected item to a
single GameState purchase method. It re-reads authored hub data and validates
the active/current node, shop action, exact offer, item definition, stack
capacity, price, and funds before mutation. It returns a success/status result
for presentation. A successful transaction spends the authored price once and
gains exactly one item. If the gain unexpectedly fails, the money is restored.
Unknown items, malformed metadata, invalid prices, stale locations, full
stacks, and insufficient funds leave both balances unchanged. Failed shop
purchases never create Exploration leftovers.

The M7.5 bootstrap starts a fresh prototype session with **12 money** and
**Healing Herb ×9**. These are test fixtures, not canonical starting values.
At Riverside, one purchase produces 8 money and Herb ×10. Another purchase
at cap is rejected. After using a Herb, the shop may sell another if the
player still has enough money. Shops can be reopened on revisits; opening
never consumes or replays the primary VN event.

## Presentation and interaction

The existing header shows current money, and the current-node action panel
gains a separate Shop button beside the primary Interact flow. A small
violet/gold Shop panel shows the offer, authored price, current money, owned
count, Buy, status, and Back. Its footprint
uses the Inventory panel's right-side region; opening one closes the other.
Travel closes the Shop. Buy refreshes only presentation and uses a brief
in-flight guard to reject repeated activation within the same frame. Buttons
remain keyboard focusable. Geometry is checked at 1152×648 and 1440×810.

## Decision log

- Chose a GameState integer over a new CurrencyState: one quantity needs no
  additional lifecycle or owner.
- Chose optional node `hub_actions` over a separate hub resource or manager:
  the current context already owns authored location metadata and deep-copy
  reads.
- Chose a GameState purchase boundary over UI-owned money and inventory
  mutations: the transaction can validate current location and prevent partial
  updates.
- Chose an additive Shop button and compact panel over a general action menu:
  one shop coexists with the existing primary-content button.
- Deferred selling, drops, discounts, rest, time Actions, and limited-use
  counters to later milestones. M7.6 owns rest/time; M7.8 owns save/load.

## Verification

The dedicated M7.5 regression covers the real prototype scene and Buttons,
economic boundaries, stale and invalid data, independent Riverside VN state,
travel/VN/Battle retention, responsive geometry, keyboard focus, and M7.4
resource overflow compatibility. All retained M2–M7.4 suites and Godot
import/parse checks run before handoff. Manual F6 acceptance follows the
automated handoff.
