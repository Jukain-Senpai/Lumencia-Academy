# Hiruko M4.1 — Combat-State Foundation

## Understanding

- Replace the Party 1 fixture with Hiruko while retaining HP 44, ATK 10, SPD 14, and Front.
- Give Hiruko two temporary 100-point Seal values and derive one of three combat states from them.
- Provide explicit prototype controls that can reach every valid state without consuming a turn.
- Keep the generic Milestone 3 battle loop and `BattleUnit` model unchanged.
- Preserve the fixed-height battlefield and five-card-per-line presentation.
- Defer every mechanical consequence of Hiruko's states to later Milestone 4 work.

## Assumptions

- The 100-point Seal capacities are M4 prototype fixtures, not canonical balance.
- Hiruko remains a normal M3 combatant for HP, Attack, Move, targeting, defeat, and queue behavior.
- The sandbox owns Hiruko state; it is not persisted and does not require a manager or autoload.
- Debug controls remain available as testing scaffolding and never enter the action-command flow.

## Decision log

1. Use a small `HirukoCombatState` `RefCounted` model owned by the battle sandbox. Extending every `BattleUnit` or adding loose Seal variables to the controller would either contaminate generic combatants or weaken validation.
2. Keep Party 1's stable ID and change its display identity to Hiruko. This preserves deterministic M3 queue identity while explicitly replacing that roster slot.
3. Derive state from Seal values on demand. There is no independently mutable state field that can disagree with the Seal values.
4. Reject `Chains > 0` plus `Wrapper == 0`. A Wrapper-first request neither changes either Seal nor advances combat state.
5. Show compact state text on Hiruko's normal fixed-height card and full Seal bars/state/debug controls in the existing lower sandbox panel. This avoids increasing formation height.

## State derivation

| Chains | Wrapper | State |
| --- | --- | --- |
| `> 0` | `> 0` | `SEALED` |
| `== 0` | `> 0` | `FLAMING_SWORD` |
| `== 0` | `== 0` | `LAEVATAIN` |

`Chains > 0` with `Wrapper == 0` is invalid and rejected.

## Deferred

Resistance, outgoing damage modifiers, damage types, Burn, hostile-hit Seal depletion, Kick, Gut Stab, frontline preference mechanics, Jukain, and story integration are outside M4.1.
