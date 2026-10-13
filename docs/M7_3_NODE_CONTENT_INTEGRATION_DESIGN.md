# M7.3 Node Content Integration Design

## Status

Approved and locked for implementation. M7.2 passed manual acceptance before this
work began. Its small reusable marker and roadblock badge are accepted as-is for
M7.3 and remain deferred presentation polish.

## Boundary

M7.3 proves exactly three explicit current-node interaction loops:

1. Exploration -> VN -> Exploration.
2. Exploration -> Battle -> Exploration.
3. Exploration -> Resource -> Exploration.

Travel only changes `current_node_id`. It never consumes content. A single map
action is available only when the current node has unresolved primary content.
The action requests content; the content owner completes the node at its valid
terminal event and returns to the reusable Exploration Map scene.

No inventory, rewards, time, economy, content-manager framework, save-schema
change, or M7.4 work is part of this milestone.

## Authored data

The only new node field is:

```gdscript
"primary_content": {
    "type": "vn_event" | "battle" | "resource",
    "id": "non_empty_identifier",
}
```

The prototype assigns Riverside Camp to a short VN event, Stone Crossing to the
existing battle sandbox, and Ruins Approach to a lifecycle-only resource action.
Old Trail and Deep Grove have no primary content.

## Ownership and handoff

`ExplorationState` remains authoritative for context, current location, reveal,
completion, roadblock, and authored reusable facts. The map reads that state,
renders one action, and requests a transition. It does not complete VN or battle
content.

`GameState` owns one transient `pending_exploration_content` dictionary:

```gdscript
{
    "context_id": String,
    "node_id": String,
    "content_type": String,
    "content_id": String,
}
```

Preparation validates the active context, current node, authored content, and
absence of another handoff. Readers receive a deep copy. Resolution revalidates
the handoff against current authoritative state, completes only that node, and is
idempotent so a scene-change retry cannot replay reveal effects. Reset clears the
handoff. It is deliberately absent from save data.

## Loop contracts

### VN

The map prepares the exploration handoff and existing pending VN sequence, then
loads the existing VN scene. A small JSON sequence ends in an explicit
`return_to_exploration` node. Only that node resolves completion. Successful
return clears the handoff and loads `exploration_map.tscn` directly, preserving
the active runtime context.

### Battle

The map prepares only the exploration handoff and loads the existing battle
sandbox. A real Victory resolves completion and returns to the map. Defeat keeps
the node incomplete and retains the handoff. Restart rebuilds combat without
clearing it; a later real Victory completes once. With no exploration handoff,
standalone battle behavior is unchanged. The existing M6 battle context, result,
and VN-return path remain separate and retain priority within their own flow.

### Resource

The map validates the known prototype resource identifier, completes the current
node immediately, refreshes the same controls, and shows `Resource collected.`
No item or inventory state is created.

## UI and failure behavior

The action panel is a lightweight overlay on the reusable map scene. Its Button
uses the same input path for mouse and keyboard. A committed transition blocks
rapid duplicate activation. Ordinary travel clears local feedback and preserves
marker controls.

Malformed or unsupported content shows a concise local diagnostic and leaves
location and completion unchanged. A stale or mismatched handoff cannot complete
another node. Expected navigation rejection remains a normal disabled-marker
state, not a configuration error.

## Regression boundary

The M7.3 suite exercises real scene changes and real controls for all three loops,
including progressive reveal after VN return, battle Defeat -> Restart -> Victory,
standalone battle, revisit/no replay, rapid activation, invalid content and
handoff data, transient reset/save boundaries, and retention of the reusable map
scene. All earlier suites remain required.
