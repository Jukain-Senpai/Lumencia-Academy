# M6.4 Battle to VN Return Design

## Purpose and boundary

M6.4 completes one integrated runtime loop: the existing Training Hall VN starts
the existing battle, a real Victory publishes the M6.3 result, and the battle
automatically returns to the existing VN controller at the sequence named by the
M6.2 `return_sequence` context field.

**M6.4 ROUTES THE RESULT. IT DOES NOT INTERPRET THE RESULT.** It adds no route
reaction, fact-driven presentation, Bond change, result consumption, persistence,
or M6.5 behavior. M6.5 will interpret the result; M6.6 will own apply-once and
persistence hardening.

## Eligibility and authoritative ordering

Result eligibility and return eligibility are deliberately separate:

- A non-empty integrated `encounter_id` may publish an M6.3 terminal result.
- Only `VICTORY` with a non-empty, VN-resolvable `return_sequence` may leave battle.
- `DEFEAT` may publish a result but remains at the terminal for retry.
- A standalone battle has no encounter context, publishes no story result, and
  retains both existing terminal screens.

The terminal order is authoritative:

1. Combat recognizes real Victory.
2. Event-latched facts are snapshotted into `pending_battle_result`.
3. Victory state and battle-local terminal cleanup are committed.
4. Battle copies and resolves `return_sequence` through the existing VN resolver.
5. Battle prepares the transient VN routing handoff.
6. The exactly-once return guard commits and requests the reusable VN scene.
7. Once the scene-change request succeeds, active battle context is cleared.
8. The VN validates and initializes the destination, then clears only the routing
   handoff.

The pending combat result is never rebuilt, changed, or cleared by this route.

## Routing handoff and VN reuse

`GameState.pending_vn_sequence` is the smallest cross-scene handoff required by
Godot's file-based scene change. It contains only a sequence identifier, remains
transient, and is excluded from the four-field save payload. It is separate from:

- `pending_battle_context`: which encounter is currently active; and
- `pending_battle_result`: what actually happened in the completed attempt.

The reusable `vn_prototype.tscn` and `vn_prototype.gd` remain the only VN scene
and controller. Their narrow sequence-ID resolver maps
`m6_training_hall_postbattle` to the corresponding JSON resource. On startup the
VN prefers a pending sequence over its exported default, uses the existing full
dialogue validator, and clears the handoff only after successful initialization.
It does not touch `pending_battle_result`.

The neutral post-battle sequence uses the existing Training Hall background and
one non-branching prototype line: `[Prototype] Returned from battle.` It contains
no conditions, effects, route branches, or Bond changes.

## Success and failure lifecycle

`battle_return_committed` is independent of the M6.3 result guard. The first valid
return request locks Restart and input until scene replacement; duplicate requests
are rejected. On successful scene-change initiation, the consumed battle context
is cleared while the result and VN handoff survive into the next scene. Successful
VN initialization consumes only `pending_vn_sequence`.

If `return_sequence` is missing, empty, or unknown, battle stays on the usable
Victory terminal, reports a clear routing error, and preserves both battle context
and the complete result. It never guesses a fallback destination.

If the VN scene-change request fails, the newly prepared routing handoff is
cleared, the return guard is released, and battle context plus result remain
intact. If the VN scene opens but dialogue initialization fails, the VN reports
its existing stable dialogue error, preserves both routing instruction and result,
and does not silently load its default sequence.

## Defeat, retry, reset, and persistence

Integrated Defeat remains in battle. Restart clears the abandoned result and all
attempt-local facts and guards while retaining encounter context. A later Victory
publishes a fresh result before returning. Full `GameState.reset_state()` clears
context, result, and VN routing handoff.

No transient M6 field enters the normal save data. The project main scene remains
unchanged, and the dedicated M6 entry scene continues to own only the prebattle
launch configuration.
