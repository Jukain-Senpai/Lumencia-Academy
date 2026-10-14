# M7.7 — Final Progression and Missable-Content Warning

## Understanding and scope

This milestone proves an explicit story exit from a timed Exploration context. A
player may reach the prototype Forest Boundary directly from Old Trail, leave
optional content unfinished, and still advance. The exit is not the Forest Exam
ending. M7.8 owns persistence; the M2 payload remains exactly `sequence`, `node`,
`flags`, and `bonds`.

Assumptions: one local player and one active Exploration context at a time;
small authored node lists; no network or sensitive user data; deterministic
session-state behavior matters more than generalized routing. Existing
Exploration, VN, Battle, Shop, Inventory, HP, and time owners remain authoritative.

## Decision log

| Decision | Alternatives considered | Reason |
| --- | --- | --- |
| Keep final-node and optional flags in authored Dictionaries | Generic event/quest framework; UI-only tags | Smallest extension of existing definitions and validation. |
| Keep detection and closed-context registry in `ExplorationState` | UI scan; separate world-state manager | The state already owns authored nodes, completion, leftovers, and context activation. |
| Let `GameState` coordinate exit and the one supported route | Button-local closure; generic scene router | Cross-mode pending handoffs and global state already live there. |
| Prepare and attach the result scene before closing, then swap the current scene | Close then call `change_scene_to_file` with rollback; route without closure | A failed destination load or attach cannot strand the player in a closed context. The result remains hidden until closure commits. |
| Use a spoiler-free count summary | List all node names; infer from every non-final node | Hidden optional content must count without revealing its identity. |
| Use a compact modal-style map overlay with Go Back initially focused | Separate Settings scene; automatic confirmation | Keeps the prototype map and keyboard loop intact. |

## Authored data and validation

The dedicated M7.7 context derives the existing timed prototype map, retaining
the five existing nodes, positions, connections, primary interactions, Shop,
Camp Rest, Wait, reveal, roadblock, and time mode. It adds `forest_boundary` as
the sole final node, connected in both directions with `old_trail`, with
`final_progression: {"destination": "prototype_story_result"}`. The
destination is an ID resolved by the single M7.7 route; arbitrary paths are
not executable metadata. The final node cannot also be primary content or a
hub, and duplicate final definitions are invalid. Malformed final metadata,
unknown destination IDs, and malformed optional flags are rejected.

`primary_content.optional: true` marks the Riverside VN, Stone Crossing Battle,
and Ruins Approach Resource as optional. Absent means non-optional. This flag
does not alter interaction or completion. `optional_missable_roadblock: true`
may explicitly mark a roadblock for future authored content; ordinary
roadblocks do not count. The empty Deep Grove is not an event.

## Detection and warning policy

`ExplorationState.get_missable_content_summary()` returns fresh deterministic
category counts: unfinished optional primary events (including hidden ones),
uncollected leftover reward nodes, and explicitly optional active roadblocks.
The returned Dictionary is independent of state. Completed events with no
leftovers, Shops, Rest uses, Wait, empty nodes, and the final node are excluded.
The UI only displays counts and generic wording, never hidden identities.

`GameState` owns one boolean warning preference with a narrow getter/setter.
It starts ON, survives travel and ordinary context/scene transitions, and
resets to ON only with a deliberate fresh `reset_state()`. The header toggle
is accessible when a final node exists. Warning ON with missables opens the
dialog; OFF or an empty summary proceeds without it. Toggling has no gameplay
side effects. Persistence of this preference is deferred to M7.8.

## Progression flow and lifecycle

Travel to Forest Boundary is ordinary free travel. Its explicit Advance Story
button is separate from primary-content completion. Opening the warning and
Go Back cost nothing and mutate no session state. The warning overlay blocks
underlying mouse and keyboard controls, initially focuses Go Back, supports
mouse and keyboard activation and Cancel/Back, and restores focus to Advance
Story on cancellation. Repeated activation is guarded.

On Continue, `GameState` checks expected context/node, current final metadata,
roadblock/reachability availability, no conflicting pending VN/Battle/
Exploration handoff, supported destination, and a current M7.7 entry or
ExplorationMap scene. It
loads and instantiates the destination before mutating Exploration state. It
adds the destination hidden to the scene tree; if that fails, the context
stays active. It then calls the authoritative close operation exactly once,
shows the result, swaps `current_scene`, and frees the old map scene. No time
action or item/money/HP/story reward is applied by this operation.

`ExplorationState` retains a transient closed-context ID registry across
`clear_runtime()` and ordinary scene/context changes. `activate_context()`
rejects a closed ID, including from an old map bootstrap; pending old
interactions cannot replay without an active context. Only `GameState.reset_state()`
clears the registry for a fresh session. Closing does not clear unrelated
money, inventory, party HP, flags, or Bonds. M7.8 must decide how to persist
closed IDs and the warning preference; M7.7 adds neither to save data.

## Verification and risks

Dedicated M7.7 tests cover metadata validation, optional/hidden/leftover
detection, warning policy and keyboard/mouse UI, cancellation preservation,
atomic handoff, re-entry protection, routing failure, responsive layout, and
compatibility. All retained suites and scene smokes remain gates before
manual F6 review. The primary risk is scene-routing atomicity; preloading and
attaching a hidden destination before closure confines failures to the still
active source map. The second risk is inadvertent UI input under the warning;
the overlay disables underlying buttons and restores them on Go Back.
