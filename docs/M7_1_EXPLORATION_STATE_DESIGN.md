# M7.1 Exploration State Foundation Design

## Goal and Source-of-Truth Alignment

M7.1 implements the reusable state/data foundation required by **Lumencia
Academy — Source of Truth v0.2 (2026-10-12)**. It proves deterministic node
travel, progressive reveal, persistent primary completion, independent
roadblocks, and authored reusable metadata without beginning M7.2 or any later
M7 system.

## Ownership and Structure

`GameState` remains the central game-state owner. It owns one lightweight,
transient `ExplorationState` instance and clears that instance's runtime facts
from `GameState.reset_state()`. Exploration is deliberately not serialized in
M7.1, so the existing four-field M2 save format remains unchanged.

`ExplorationState` owns exploration-specific validation and mutations. Static
context definitions are registered separately from the active runtime state.
Activating a registered context creates fresh runtime facts from that context;
activating another context discards the earlier context's runtime facts.

No `ExplorationManager`, map controller, quest engine, event bus, or Resource
hierarchy is introduced.

## Static Context Definition

Contexts use the following minimal Dictionary shape:

```gdscript
{
    "id": "context_id",
    "starting_node": "A",
    "nodes": [
        {
            "id": "A",
            "connections": ["B"],
            "initially_revealed": true,
            "reveal_on_complete": [],
            "reusable": false,
            "initial_roadblock": false,
        },
    ],
}
```

Definitions are validated before registration. IDs must be non-empty and
unique, the start and every connection/reveal target must exist, all required
fields must have the expected type, and the starting node must be initially
revealed. A validated deep copy prevents callers from silently changing a
registered definition.

Connections are authored outgoing edges. A reciprocal edge must be authored
when two-way travel is intended; the state layer does not invent universal
one-way or bidirectional semantics.

## Runtime State and Independent Facts

The transient runtime shape is:

```text
active_context_id
current_node_id
revealed_nodes
completed_nodes
roadblocked_nodes
```

`reusable` is not duplicated into mutable runtime state. It is queried from the
active node definition. There is no exclusive node-state enum: a node can be
current, completed, roadblocked, and authored reusable simultaneously.

## Travel and Primary Interaction

Travel succeeds only when a context is active, the destination exists in that
context, the destination is revealed, and the current node's authored outgoing
connections contain the destination. Failed travel changes nothing. A
roadblock does not universally prevent travel because it may describe a local
interaction rather than the entire location.

`move_to_node()` changes only `current_node_id`. It never completes content.
`complete_primary_content()` independently records primary completion and
applies the node's authored `reveal_on_complete` effects. Completed nodes remain
ordinary travel destinations, and duplicate completion is idempotent.

## Reveal, Completion, Roadblock, and Reusable Lifecycles

- Reveal begins from authored `initially_revealed` values and only grows during
  an active context. Revealing an already revealed node is idempotent.
- Completion persists until runtime context reset. Leaving or revisiting a node
  neither clears nor replays completion.
- Roadblocks begin from authored `initial_roadblock` values and change only
  through the narrow set/clear API. Completion never clears a roadblock.
- Reusable behavior is immutable authored metadata. Names such as `shop` have
  no special meaning.

## Invalid-State Behavior

Unknown/malformed contexts are rejected without changing runtime state. With no
active context, node queries return false and mutations fail. Unknown, hidden,
or disconnected travel fails without moving the player. Unknown completion,
reveal, and roadblock mutations fail. Valid duplicate completion, reveal, and
roadblock operations are safe and idempotent.

## Deferred Systems

M7.1 adds no map scene or art usage, inventory, time/rest, economy, VN or battle
node launch, resource reward, context-final progression, or save-schema field.
These remain owned by their specified later submilestones. The state shape
leaves independent room for later location contents and leftovers without
speculating about their implementation.

## Regression Strategy

The dedicated regression uses local deterministic contexts. Its primary A/B/C
flow proves travel does not complete B, completing B reveals C, returning to A
does not erase either fact, and completed B remains traversable. It separately
proves invalid travel safety; the simultaneous current/completed/roadblocked/
reusable state; roadblock persistence and explicit clearing; reveal
idempotence; name-independent reusable metadata; malformed-definition rejection;
fresh context activation; and transient `GameState` ownership.

## M7.2 Handoff

M7.2 may present the active context and call the narrow query/mutation APIs. It
must not infer state from visuals or merge selection/travel with primary-content
completion. M7.1 deliberately supplies no map UI and does not consume the
reserved exploration-map asset.

## Decision Log

1. Use one transient `ExplorationState` owned by `GameState`; embedding all
   rules directly in `GameState` would blur ownership, while a manager framework
   would be premature.
2. Use validated Dictionaries because they match current project data
   conventions and avoid premature Resources/classes.
3. Treat connections as exact authored outgoing edges so context data, not a
   global assumption, controls direction.
4. Keep reusable solely as authored metadata and current/reveal/completion/
   roadblock as runtime facts.
5. Separate travel from completion so completed locations remain traversable
   without replaying primary content.
6. Keep exploration transient and out of the save payload until M7.8.
