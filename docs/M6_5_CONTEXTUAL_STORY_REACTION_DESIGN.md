# M6.5 Contextual Story Reaction Design

## Purpose and boundary

M6.5 turns the M6.4 post-battle landing into a visible reaction to what actually
happened during the Training Hall prototype. It reads the unchanged M6.3 result,
selects one approved dialogue branch, applies that specific reaction's Hiruko Bond
consequence, and reconverges into one shared ending.

The reaction belongs to the combination of encounter, Prescript, route, and
authoritative event fact. It does not define universal social meanings for
`OBEY`, `EXPLOIT`, or `DEFY`. M6.5 does not consume or mutate the result, persist
reaction state, or implement M6.6 apply-once/save-load hardening.

## Result eligibility and branches

Every valid reaction requires all of:

- `outcome == VICTORY`;
- `encounter_id == m6_training_hall_prototype`;
- `prescript_id == prototype_hiruko_hp`;
- the expected `prescript_route`; and
- the route's required authoritative boolean fact.

The direct-hit branch requires `OBEY` plus `jukain_attacked_hiruko == true` and
applies Hiruko Bond `-1`. The manipulation branch requires `EXPLOIT` plus
`hiruko_damaged_by_enemy == true` and applies `-1`. The replacement branch
requires `DEFY` plus `replacement_requirement_completed == true` and applies
`+1`. `blessing_gained` and `karma_gained` never drive social selection or add
another Bond consequence. When multiple event facts coexist, route plus its own
required resolution fact keeps the established reaction authoritative.

Missing, malformed, unresolved, inconsistent, wrong-identity, or non-Victory
results reach a neutral prototype fallback. The fallback changes no Bond and
does not guess a route.

## Dialogue graph and condition extension

The existing `condition` node gains one narrow type: `battle_result_matches`.
Its condition object permits exactly `outcome`, `encounter_id`, `prescript_id`,
`prescript_route`, and `required_fact` in addition to `type`. It supports only
Victory, the three current route labels, and the three approved authoritative
reaction facts. It is not a path language, expression evaluator, reflection API,
or general result-query framework.

Three condition nodes form an ordered chain: direct hit, enemy hit, replacement,
then fallback. Each valid condition owns exactly one existing-style Hiruko
`adjust_bond` effect. This keeps each delta beside the complete prototype
reaction definition instead of putting values in generic route code. All valid
branches contain only approved dialogue lines and target the same three-line
shared ending. The M6.4 placeholder is removed.

## Effect timing and lifecycle

The postbattle sequence loads and validates first. Automatic condition traversal
then reads a deep copy of `pending_battle_result`. On the first successful
condition entry, the controller applies that node's effect before showing the
branch's first line. The battle result remains deeply unchanged and available.

`executed_reaction_effect_node_ids` is owned only by the active VN instance. It
prevents redraw, repeated traversal, or later line advancement from applying the
same reaction node twice. It is not stored in `GameState`, not serialized, and
not a consumed marker. A brand-new postbattle VN instance can still apply the
effect again; M6.6 deliberately owns persistent apply-once behavior and result
consumption.

## Existing-system compatibility

The existing `GameState.adjust_bond()` remains the only Bond owner. Existing M2
`flag_equals` conditions and choice effects retain their behavior. The normal save
payload remains `sequence`, `node`, `flags`, and `bonds`; battle result, routing
handoff, and the local executed-node set remain absent. M6.4 routing, combat,
main-scene configuration, Training Hall art, and character textures are unchanged.

## Assumptions and non-functional requirements

- Dialogue and result dictionaries are tiny local data with synchronous,
  constant-time evaluation.
- There is no networking, sensitive data, concurrency, or scale concern.
- Invalid data fails existing validation; invalid runtime results reach the safe
  visible fallback without mutating state.
- Maintenance stays with the current VN controller, dialogue JSON, and GameState;
  no new manager or reaction registry is introduced.

## Decision log

1. Extend the existing condition node rather than hardcode startup branching or
   introduce a separate reaction node system.
2. Require route and authoritative fact together; route alone is insufficient.
3. Store each Bond effect on its specific Training Hall condition node rather
   than define a universal route-to-Bond mapping.
4. Reuse existing effect validation/execution and add only instance-local node-ID
   protection.
5. Keep invalid-result behavior visible, neutral, and consequence-free.
6. Preserve the result untouched for M6.6 and explicitly defer cross-instance
   apply-once persistence.
