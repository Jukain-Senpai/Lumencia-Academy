# Hiruko M4.3 — Burn and Laevatain Aura

## Scope

M4.3 adds Hiruko-specific Burn behavior to the battle sandbox without creating a universal status or elemental system. The existing M3 battle loop and M4.2 resistance, Seal, and Basic Attack rules remain authoritative.

## Scene-local Burn state

`battle_sandbox.gd` owns one narrow `Dictionary` keyed by each combatant's stable unit ID. An entry stores the unit's remaining Burn ticks. Applying or reapplying Burn always sets the entry to `2`; Burn never stacks and never extends beyond that value.

- Burn damage: `5` HP.
- Burn duration: `2` completed-turn ticks.
- Burn damage is HP-only and does not enter Hiruko's hostile-hit or Seal pipeline.
- Defeated units lose their Burn entry immediately.
- Restart clears all Burn entries and the Laevatain turn-aura guard.

## Completed-action order

Every real Basic Attack or Move finishes through one shared scene-local action-completion path:

1. Resolve the direct action completely.
2. Check Victory/Defeat and stop if the battle has ended.
3. Apply one Burn tick to the acting unit, if afflicted.
4. Check Burn-triggered Victory/Defeat.
5. Advance to the next living actor.

Target selection, movement selection, cancellation, UI rendering, and the regression-only raw `advance_turn()` helper do not count as completed actions and do not tick Burn.

## Hiruko sword attacks

Hiruko's Basic Attack keeps the M4.2 resolved damage and damage type. If the direct target survives a Flaming Sword or Laevatain Basic Attack, that target receives or refreshes Burn to `2`. A Sealed Basic Attack does not apply Burn, and a target defeated by the direct hit receives no Burn entry.

## Laevatain aura

When a hostile hit naturally breaks Wrapper, Hiruko enters Laevatain and immediately applies or refreshes Burn to `2` on every other living combatant. This occurs after the hit's M4.2 HP and Seal resolution but before the attacking unit's end-of-turn Burn tick. Hiruko is excluded from her own aura; both allies and enemies are otherwise affected.

Breaking Wrapper with the debug control changes state only. It does not trigger the activation aura. The first real Hiruko turn in Laevatain triggers the normal turn-start aura.

At the start of every real, living Hiruko turn in Laevatain, the same aura applies exactly once. A token derived from battle generation, round, and queue position guards that turn. UI refreshes, targeting, movement selection, and cancellation cannot retrigger it.

## Presentation

Burn is shown compactly on the existing fixed-height unit card as `[BURN 2]` or `[BURN 1]`. Laevatain's combat profile adds `Aura ACTIVE`. Aura application uses one grouped combat-log entry naming the affected units.

## Explicit exclusions

M4.3 does not add Kick, Gut Stab, a generic status framework, elemental mechanics, persistence, or any other M4.4 behavior.
