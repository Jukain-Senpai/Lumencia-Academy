# M7.8 — Save / Load Integration

## Understanding and boundaries

M7.8 gives the local prototype a single-slot, durable checkpoint for stable Exploration map and post-progression result states. It must preserve the exact existing standalone VN save output, read old M2/M6 saves, and never replay completed content or apply-once reaction receipts. The player reaches Load from the initial VN, the Exploration map, or the result scene. No autosave, multiple slots, cloud service, mid-dialogue/turn/handoff checkpoint, chapter loader, or M7.9 integration work is included.

Assumptions: the save is small and local; external save bytes are untrusted; a complete failed load leaves the current run and scene unchanged; a failed write retains the previous valid file; only known prototype contexts and destinations are resumable; schema changes are deliberately explicit rather than a general migration framework. GameState remains the owner of persistence, flags, Bonds, money, warning preference, and handoff guards. ExplorationState, InventoryState, and PartyRuntimeState remain the owners of their respective runtime values.

## Decision log

| Decision | Alternatives | Reason |
| --- | --- | --- |
| Extend GameState with narrow snapshot methods on existing state owners | Per-scene persistence; a new SaveManager | One authoritative save owner without duplicating gameplay state. |
| Use an explicit version-2 envelope and `kind` | Infer kind from fields or active scene | Unknown versions and destinations fail clearly. |
| Keep `save_game(sequence, node)` as exact four-field legacy output | Upgrade every VN save | M2/M6 compatibility, including receipt flags. |
| Reconstruct only allowlisted authored contexts | Serialize definitions or accept paths from JSON | Saved data cannot create scripts, resources, nodes, or content. |
| Validate candidate state and preinstantiate destination before commit | Reset then restore in place | Failure cannot erase the current run. |
| Use temporary write plus reversible replacement | Direct truncate/write | A failed write does not destroy the prior save. |
| Bound persisted integer values to exactly representable JSON integers | Stringify all counters or risk float rounding | Current prototype values remain numeric and lossless. |
| Stabilize M7.7 simulated click by testing viewport geometry | Extra fixed frames; weakened assertion | The observed failed click targeted an offscreen, not-yet-laid-out Button. |

## On-disk formats

The legacy VN file remains exactly `{ "sequence": String, "node": String, "flags": Object, "bonds": Object }` when produced by `GameState.save_game()`. A file with `schema_version` is never treated as legacy. The legacy reader retains its existing flag/Bond validation and additionally routes only to a known sequence and a stable line node. A successful legacy load replaces the whole session: unrelated Exploration state, inventory, party-runtime changes, money, pending handoffs, closure, and preference return to fresh defaults. Receipt flags in the loaded `flags` remain intact.

The versioned file is a single JSON object:

```json
{
  "schema_version": 2,
  "kind": "exploration",
  "flags": {},
  "bonds": {},
  "exploration": {
    "active_context_id": "m7_7_progression_prototype_forest",
    "current_node_id": "old_trail",
    "revealed_nodes": [],
    "completed_nodes": [],
    "roadblocked_nodes": [],
    "leftover_rewards": [],
    "time": { "mode": "MULTI_DAY", "day": 1, "daypart_index": 0, "actions_spent": 0, "total_actions": 0 },
    "hub_action_uses": [],
    "closed_context_ids": []
  },
  "inventory": [],
  "money": 12,
  "party_hp": [],
  "preferences": { "missable_content_warning_enabled": true }
}
```

The `result` kind has the same runtime fields plus `destination: "prototype_story_result"`. It has no active context, node, node sets, leftovers, or hub uses; its closed-context registry includes the Forest context. The concrete serializer writes all required fields, including empty collections. Missing or mistyped versioned fields are not defaulted. `time_feedback` is presentation-only and is not persisted. Pending handoffs and in-progress UI dialogs are never serialized.

Node-set and closed-context values are arrays of unique IDs. Leftovers are records of node ID, item ID, and positive quantity. Hub-use records contain node ID, authored action ID, and remaining uses. Each is validated against the reconstructed definition. Inventory is an array of unique `{item_id, quantity}` records for known items with quantities 0–10. Party HP is an array of unique `{member_id, current_hp, max_hp}` records containing exactly the six stable member IDs. Arrays permit explicit duplicate rejection before state mutation. Money and time counters are finite, nonnegative integer-valued JSON numbers within the exact IEEE-754 integer range; day starts at 1, daypart is 0–2, current part actions are 0–1, and total actions must match the stable day/part/action position in timed modes. `NO_TIME` retains its initial clock. A pending sixth-action transition is not a checkpoint.

## Save and load flow

Map saves require a valid active, open allowlisted context, stable clock, no pending VN/Battle/exploration handoff or result, and no warning or progression commit in the scene. The map may be either the M7.7 entry wrapper or the standalone map reached after VN/Battle return. Result saves require the known result scene and an inactive, closed Forest context. Saving costs no action. The candidate is validated and serialized before disk work. It is written and flushed to a sibling temporary file, then the old file is moved to a sibling backup before replacement. On Windows, a legacy test or other reader can hold the original file open, preventing rename; in that specific case the original is copied to backup before a guarded in-place fallback. Failed replacement attempts restore the prior save; if restoration itself fails, the backup remains recoverable and the operation reports failure. A pre-existing backup blocks further writes until recovered rather than silently overwriting it.

Loading reads and parses without mutation, discriminates by explicit version marker, validates the entire envelope, builds a candidate ExplorationState from the trusted prototype builder, validates/restores InventoryState and PartyRuntimeState candidates, validates money and preference, and resolves the fixed destination scene. A legacy candidate is likewise validated against the VN's known dialogue and stable line. The destination PackedScene is loaded and instantiated before committing any candidate. GameState swaps to candidate values only at the route boundary; the prior state and source scene remain available until the new scene is in the tree and initialized. On route failure, GameState restores the old state and leaves the source scene intact. The old scene is freed only after successful presentation.

Fresh M7.7 entry still explicitly resets and seeds money, Herbs, and party HP. Restored entry sees its already-active reconstructed context and skips that bootstrap. Result restoration leaves the context inactive and closed. No load invokes primary-content completion, item consumption, time spending, Camp Rest, Night Rest, battle resolution, choice effects, or story advancement.

## UI and validation

The map exposes small Save/Load controls and a feedback label without changing marker or hub ownership. The initial standalone VN Load control can route versioned saves from a cold start. Its established M2 focus mode remains unchanged; a discoverable Ctrl+L shortcut supplies keyboard loading without allowing ordinary Enter dialogue input to activate the utility button. The result scene has minimal focusable Save/Load controls. Expected save-point rejection appears as status text; invalid files expose a useful error without falling back to a fresh map.

Dedicated M7.8 tests cover exact legacy output and routing, full versioned roundtrips, safe writes and failed-load rollback, authored ID validation, inventory/money/HP/time/hub/node/leftover/preferences/closure, cold-start map and result routing, real controls, focus, and two viewport sizes. All M2–M7.7 suites, import, parse, and scene smokes remain gates. Manual F6 flows A–G remain the acceptance gate before any commit. M7.9's broader integration pass is deferred.
