# M6.3 Battle Result Contract Design

## Goal

M6.3 creates one compact, story-facing result when an integrated battle reaches
the existing Victory or Defeat boundary. Combat records facts while they happen;
the terminal boundary snapshots those facts for a later milestone to consume.

**M6.3 DOES NOT RETURN TO VN.** It does not consume `return_sequence`, change
Bond, persist a result, or begin M6.4/M6.5 behavior.

## Understanding and assumptions

- The existing M6.2 battle context identifies the encounter being played.
- Only a battle with valid transient context publishes a result. Standalone F6
  combat remains context-optional and publishes nothing.
- One nested `Dictionary` is sufficient for this prototype; no event bus,
  registry, telemetry system, or result hierarchy is needed.
- The result is small and local, has no private data, and is copied deeply at
  the scene boundary. Performance and scale are therefore negligible.
- The battle controller owns factual observation. `GameState` only transports
  context and result dictionaries across scenes.

## Contract

```gdscript
{
    "outcome": "VICTORY", # or "DEFEAT"
    "encounter_id": "m6_training_hall_prototype",
    "prescript_id": "prototype_hiruko_hp",
    "prescript_route": "OBEY", # OBEY, EXPLOIT, DEFY, or UNRESOLVED
    "facts": {
        "jukain_attacked_hiruko": true,
        "hiruko_damaged_by_enemy": false,
        "replacement_requirement_completed": false,
        "blessing_gained": 1,
        "karma_gained": 0,
    },
}
```

`return_sequence` remains in battle context because it is routing data, not a
combat result. Active Blessing and Karma state are battle-local mechanics; only
the amounts actually gained during this attempt are reported.

## Authoritative fact triggers

- `jukain_attacked_hiruko` becomes true only after a confirmed direct
  Jukain-to-Hiruko attack reduces Hiruko's HP.
- `hiruko_damaged_by_enemy` becomes true only after an enemy direct attack
  reduces Hiruko's HP. Burn and debug mutations do not count.
- `replacement_requirement_completed` becomes true only when the active
  replacement requirement accepts real enemy damage to Jukain and resolves.
- `blessing_gained` increments at the actual Obey Blessing grant.
- `karma_gained` increments when the missed deadline actually grants Karma.

These observations may coexist. They are never reconstructed from the final
route. Route and outcome remain independent; a resolved route survives later
Defeat, while an early Defeat reports `UNRESOLVED`.

## Ownership and lifecycle

`battle_sandbox.gd` owns a controller-local `result_facts` dictionary and the
`battle_result_committed` guard. A fresh attempt initializes defaults. Restart,
before or after terminal, clears pending result and local result tracking while
preserving M6.2 battle context.

`JukainPrescriptState.PRESCRIPT_ID` supplies the stable narrow identity
`prototype_hiruko_hp`. No Prescript registry is introduced.

At the first real terminal boundary the battle controller:

1. confirms the battle is integrated through valid context;
2. converts the semantic outcome and current Prescript route;
3. snapshots the already-latched facts;
4. stores one result in `GameState`; and
5. marks the per-attempt guard committed.

This happens before active Blessing cleanup, but correctness does not depend on
the cleanup order because `blessing_gained` and the other facts were recorded at
their gameplay events. Later rendering cannot mutate the stored result.

`GameState` owns transient `pending_battle_result` operations. Store and retrieve
both use deep copies. Preparing a valid new integrated encounter clears any old
result before assigning the new context. Full `reset_state()` clears both
transient structures.

## Persistence and milestone boundaries

The M2 save payload remains exactly `sequence`, `node`, `flags`, and `bonds`.
Neither battle context nor pending result is serialized. M6.4 will own returning
to VN and consuming routing context. M6.5 will own any encounter-specific Bond
consequence. This milestone adds neither behavior.

## Decision log

- Chosen: controller-local event latches and a terminal snapshot. This preserves
  factual provenance with the smallest implementation.
- Rejected: derive facts from OBEY/EXPLOIT/DEFY at terminal. Route does not prove
  which later or earlier combat events actually occurred.
- Deferred: a reusable result/event abstraction. One prototype contract does not
  justify that maintenance surface.
- Chosen: deep-copy transient dictionaries in the existing `GameState` autoload.
  This matches M6.2 ownership and prevents caller mutation without new classes.
