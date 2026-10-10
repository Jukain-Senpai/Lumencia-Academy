# M6.2 — VN to Battle Integration

## Goal and boundaries

M6.2 proves one runtime direction: a data-driven Training Hall VN sequence explicitly launches the existing battle sandbox. It does not create a second VN or battle implementation, replace the project main scene, export battle results, persist a Prescript route, change Bonds, or save active encounter context.

**M6.2 DOES NOT IMPLEMENT BATTLE → VN.** M6.3 owns the future result contract. M6.4 owns the future automatic return using the prepared return-sequence identifier.

## Approved pre-battle sequence

The sequence identifier and file are `m6_training_hall_prebattle` and `res://data/dialogue/m6_training_hall_prebattle.json`. It uses `res://assets/art/backgrounds/academy_training_hall.png` through the existing sequence-level background mechanism.

The sequence contains exactly these six lines:

1. Hiruko (`neutral`): “We're supposed to clear the targets before the exercise ends.”
2. Jukain (`tired`): “Straightforward. That's suspicious.”
3. Hiruko (`neutral`): “It's training, Jukain.”
4. Jukain (`smirk`): “That's usually when something decides to become complicated.”
5. Hiruko (`annoyed`): “Just stay focused.”
6. Jukain (`smirk`): “I'll treasure those words when this inevitably goes wrong.”

These keys reuse the existing character texture map and assets. No choice, additional line, new character art, or battle presentation asset is added.

## Architecture

The dedicated `m6_training_hall_entry.tscn` inherits the reusable VN scene and changes only its exported initial dialogue path. The project main scene remains the M1/M2 prototype.

The dialogue graph gains one explicit terminal action node:

```json
{
  "type": "start_battle",
  "battle_scene": "res://scenes/battle/battle_sandbox.tscn",
  "encounter_id": "m6_training_hall_prototype",
  "return_sequence": "m6_training_hall_postbattle"
}
```

Validation requires all four fields and the exact existing battle scene. Runtime never infers launch from line order or text.

`GameState` owns `pending_battle_context`, containing only `encounter_id` and `return_sequence`. It is runtime-only and deliberately absent from the explicit save payload of sequence, node, flags, and Bonds. A new-run reset clears it; battle Restart does not touch it.

The battle controller copies the pending context when it enters the tree. An empty dictionary is the valid standalone fallback. Restart rebuilds combat state but retains the copied context and the Autoload context, so an integrated retry preserves encounter identity.

## Transition and safety

The final line remains visible until normal player advance. That advance reaches the explicit action node, commits a one-way launch guard, disables further dialogue advance, prepares context, and requests `battle_sandbox.tscn`. The guard rejects rapid repeated activation. If context preparation or scene change fails, the controller reports the existing visible dialogue error and clears any partially prepared context.

The new battle initializes the unchanged six-member fixture: Jukain is Locked with real ATK 9, effective ATK 1, Blessing 0, Karma 0, a fresh Prescript, and unavailable Form Chain; Hiruko retains the M4 initial state. Victory and Defeat keep their existing terminal behavior and do not return to VN.

## Assumptions and non-functional requirements

- Sequences and scenes are small local resources loaded synchronously; no scale or network requirement exists.
- No private data or new security boundary is introduced.
- Reliability requires one transition request, no stale VN callbacks after replacement, context-optional standalone battle, and deterministic Restart behavior.
- Ownership remains maintainable and narrow: the VN runner validates/executes the action, `GameState` owns transient cross-scene data, and the battle controller reads it.

## Considered approaches

1. **Inherited entry scene plus explicit graph action (selected).** Reuses all VN presentation and keeps authoring data-driven with minimal code.
2. **Hard-coded launcher scene.** Rejected because it would duplicate dialogue/controller behavior.
3. **Replace the main scene or add a flow manager.** Rejected because it risks M1/M2 startup regressions and adds an unnecessary global owner.

## Decision log

- Keep `vn_prototype.tscn` as the reusable implementation and expose only an initial-sequence property.
- Add a dedicated `start_battle` node rather than overloading sequence transition or end nodes.
- Keep context in existing `GameState` rather than adding a manager.
- Keep context out of save data and copy it into the battle once on entry.
- Preserve context across Restart by leaving both battle identity and Autoload context untouched during combat reset.
- Keep `battle_sandbox.tscn` context-optional and retain its exact combat fixture.
- Preserve project startup and stop at existing Victory/Defeat behavior.
