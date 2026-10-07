# Milestone 2.2 Minimal Game State Design

## Understanding

- Add one in-memory state owner for simple boolean flags and integer Bond values.
- Let the existing classroom choice modify that state exactly once.
- Preserve both immediate choice-response branches, then reconverge them onto one condition node.
- Have that condition node read `helped_hiruko` from state and select one of two later dialogue lines.
- Preserve the M2.1 runner, data format, scene, presentation, input lock, ending, and restart behavior.
- Exclude save/load, scene transitions, compound conditions, generalized commands, and permanent Bond rules.

## Assumptions

- This remains a tiny local single-player prototype with constant-time dictionary access and no networking or privacy concerns.
- An unset flag reads as `false`, a missing Bond reads as `0`, and reset clears both maps.
- Restart means a fresh prototype run and therefore resets state; future ordinary scene changes may retain Autoload state.
- Data mistakes should fail validation with useful Godot errors instead of partially running malformed dialogue.

## Approaches Considered

1. **Explicit condition node (selected).** Both branches target one node that reads stored state and routes to a true or false target. This directly proves state-driven dialogue with one small node type.
2. **Conditional line filtering.** Attaching conditions to ordinary lines would require skip/fallback traversal rules that the current prototype does not need.
3. **Direct branch targets.** Sending each option directly to its matching reaction line is simpler but does not prove that dialogue can read previously stored state.

## Final Design

`GameState` is one Autoload with two dictionaries and five operations: set/get flag, adjust/get Bond, and reset. It deliberately has no serialization, ranks, signals, or domain-specific relationship logic.

Each choice option may contain an `effects` array. M2.2 recognizes only `set_flag` with a boolean `value` and `adjust_bond` with an integer `amount`. The runner validates every effect before play and applies the selected option's effects only after closing the choice input lock. Repeated button signals are ignored because `awaiting_choice` is already false.

A `condition` node contains one `flag_equals` condition plus `true_target` and `false_target`. The runner compares `GameState.get_flag(flag)` to the required boolean and immediately follows the matching target. Unknown effect or condition types and invalid fields are rejected during dialogue validation.

## Decision Log

1. **One Autoload named `GameState`.** Local scene state would not survive later scene changes; multiple managers would be premature.
2. **Generic string-key maps with minimal accessors.** Hard-coded properties and Bond ranks were rejected because later state requirements remain unresolved.
3. **Effects live on choice options.** This keeps authored consequences beside the choice that causes them without introducing an event system.
4. **Exactly two effect types and one condition type.** This meets M2.2 while avoiding an arbitrary command or expression language.
5. **Restart explicitly resets state.** This provides the requested fresh-run behavior without resetting state whenever a VN scene loads.
