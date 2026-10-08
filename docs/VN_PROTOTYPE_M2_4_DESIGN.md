# Milestone 2.4 One-Slot Save/Load Design

## Understanding

- Add one plain JSON save slot containing runtime story state and the current stable VN position.
- Extend the existing `GameState` rather than adding another Autoload or persistence manager.
- Restore a saved normal dialogue node directly after validating the complete save, sequence, and node.
- Reconstruct background, active expression, speaker emphasis, and text from dialogue data instead of serializing UI nodes.
- Provide small Save, Load, and New Run controls in the existing prototype scene.
- Preserve current dialogue, choice, transition, ending, and Restart behavior while excluding production save-system features.

## Assumptions

- There is one local player and one synchronous, inspectable save file at `user://lumencia_save.json`.
- Current node IDs are the stable VN position identifiers; no separate numeric index is needed.
- Save is available only on normal dialogue lines, not choices, automatic condition/transition nodes, errors, or Scene End.
- Invalid saves remain untouched and must not mutate the current runtime state or presentation.
- There are no encryption, privacy, networking, performance, concurrency, or migration requirements for this prototype.

## Approaches Considered

1. **GameState serialization plus runner-owned progress restoration (selected).** GameState reads/writes flags and Bonds together with sequence/node identifiers; the runner validates and restores its own dialogue presentation.
2. **A SaveManager Autoload.** This would add a second global owner and indirection for one small slot.
3. **Serialize the VN scene or visual state.** Node/resource serialization would be fragile and would duplicate presentation already described by dialogue data.

## Final Design

`GameState` writes `sequence`, `node`, `flags`, and `bonds` to one JSON object. Reading validates every required field and normalizes integer Bond values without changing live state. The runner then validates the sequence into a temporary package and confirms that the saved node exists and is a normal `line`. Only after all checks pass does it apply the saved state and sequence, reset presentation to deterministic defaults, and render that line directly.

Save is disabled while the choice UI is visible and whenever the current state is not a normal line. Load remains available when a slot exists and can replace a visible choice with the previously saved stable line. New Run and Scene End Restart both clear runtime state and reload the starting classroom, but never delete the save file. Button clicks use unhandled input so they cannot also advance dialogue.

## Decision Log

1. **One JSON slot in `user://`.** It is inspectable and uses Godot's intended writable storage without adding slot infrastructure.
2. **Node ID instead of numeric index.** IDs match the existing graph architecture and allow direct validation without positional assumptions.
3. **Staged validation before mutation.** Invalid files, sequences, or nodes leave the playable state untouched.
4. **Normal-line saves only.** This prevents ambiguous choice, condition, transition, and effect restoration.
5. **Direct line rendering on Load.** Traversal was rejected because it could replay effects or transitions.
6. **Reconstruct presentation defaults.** Only story state and progress are persisted; runtime nodes and redundant visual fields are excluded.
