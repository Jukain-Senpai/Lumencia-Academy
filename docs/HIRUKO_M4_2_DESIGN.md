# Hiruko M4.2 — Seal Damage and State-Dependent Sword Damage

## Understanding

- Hostile direct hits against Hiruko use her state at hit start for HP resistance.
- The same hit applies full raw damage to exactly one active Seal after HP damage is applied.
- Seal damage clamps at zero and never overflows into the next Seal.
- Hiruko's Basic Attack derives damage and Blunt/Slash presentation from her state without changing base ATK.
- Generic combatants retain the M3 `damage = ATK` rule.
- Burn, techniques, universal damage types, and generalized resistance/status systems remain deferred.

## Assumptions

- Incoming and outgoing percentage scaling use deterministic integer ceiling division.
- Only enemy Basic Attacks are hostile direct hits in M4.2.
- HP, defeat, battle results, logging, UI refresh, and turn flow remain controller responsibilities.
- The existing `HirukoCombatState` remains the sole authoritative Seal/state model.

## Decision log

1. Use a two-phase Hiruko hit result Dictionary: prepare the hit from captured state, apply HP in the controller, then apply raw Seal damage through the model. This makes state-at-hit-start ordering explicit.
2. Keep Seal selection, resistance profiles, sword profiles, clamping, and no-overflow invariants in `HirukoCombatState`.
3. Keep the shared attack commit path and add only narrow Hiruko branches. Duplicating the attack engine or introducing manager/framework abstractions would exceed M4.2.
4. Represent Blunt/Slash as Hiruko-specific presentation labels only. Targets gain no type resistance or weakness model.
5. Add the resistance and Basic Attack profile to the existing compact Hiruko panel without changing unit-card height.

## Final design

For a hostile direct hit, the model prepares a result containing raw damage, state at hit start, resistance, HP damage, active Seal, and Seal value before the hit. The controller applies the prepared HP damage and normal defeat rule. The model then applies raw damage to the captured active Seal, enriches the result with the post-hit Seal value and derived state, and reports whether a transition occurred.

Integer ceiling scaling is:

```text
(base_damage * percentage + 99) / 100
```

Incoming HP percentages are 30%, 65%, and 100%. Outgoing Basic Attack percentages are 100%, 120%, and 140%. Negative input is clamped to zero.

## Deferred

Burn, Laevatain aura, fire immunity, Kick, Gut Stab, multi-stage techniques, frontline preference mechanics, Jukain, story integration, and generalized combat-effect frameworks are outside M4.2.
