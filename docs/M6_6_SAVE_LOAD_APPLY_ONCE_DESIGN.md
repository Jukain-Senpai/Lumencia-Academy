# M6.6 Save / Load + Apply Once Design

## Scope

M6.6 makes the four M6 Training Hall post-battle consequences durable and
apply-once across VN re-entry and save/load. It extends the existing
`battle_result_matches` condition/effect flow; it does not introduce a reaction
manager, ledger, fifth save field, result-consumed field, or M6.7 behavior.

**PENDING BATTLE RESULT IS TRANSIENT TRANSPORT. THE PERSISTENT STORY RECEIPT +
EXISTING STORY STATE ARE THE DURABLE RESULT.**

## Ownership

- Dialogue JSON owns the exact battle-result requirements, receipt flag, Hiruko
  Bond effect, and dialogue destination for each reaction.
- `vn_prototype.gd` validates results, interprets the four allowlisted Training
  Hall receipts, detects conflicts/cardinality errors, and executes commit order.
- `GameState` continues to own only primitive flags, Bonds, transient result
  transport, and the existing four-field save payload.

The receipt flags are:

- `m6_training_hall_obey_direct_hit_applied`
- `m6_training_hall_exploit_enemy_hit_applied`
- `m6_training_hall_defy_replacement_applied`
- `m6_training_hall_defy_death_applied`

They live inside the existing saved `flags` dictionary. Old saves omit them and
therefore read them as `false`; no migration is required.

## Condition Contract

`battle_result_matches` remains narrow. Its M6.6 metadata adds required
`receipt_flag` and optional `required_false_fact`. The latter is accepted only
for death-Defy and only as:

```text
jukain_died_before_prescript_resolution == true
replacement_requirement_completed == false
```

Normal Defy still requires replacement completion `true`, so the two meanings
cannot overlap.

## Runtime State Machine

With zero active receipts, a matching valid Victory result enters the fresh
commit path. Immediately before mutation, the controller re-reads all four
receipts and requires cardinality zero plus the node receipt still absent. It
then applies the existing Bond effect, sets exactly one receipt, clears
`pending_battle_result`, marks the instance-local node guard, and enters the
existing branch dialogue.

With exactly one active receipt, only the node naming that receipt may succeed.
No pending result means presentation-only success. An equivalent pending result
is redundant transport: it is cleared and the persisted branch displays with no
Bond effect. A conflicting pending result makes the condition fail without any
mutation, allowing the chain to reach its diagnostic fallback.

Two or more active receipts are invalid persistent state. Every contextual
condition fails; no Bond, receipt, or result is changed, and no branch is chosen
arbitrarily. Invalid/malformed results and Defeat results follow the same safe
fallback/preservation rule.

Death-Defy still commits its receipt even though its explicit Bond delta is zero.
The receipt—not a nonzero Bond change—is proof that the consequence was handled.

## Persistence and Lifecycle

The save schema remains exactly:

```text
sequence
node
flags
bonds
```

Saving on a post-battle line persists the receipt and resulting Bond. Loading
that line restores both and does not traverse the condition or reapply the
effect. Re-entering the sequence routes from the one receipt without requiring a
pending result. Full `GameState.reset_state()` clears flags and Bonds, restoring
a clean-run state. The raw combat result remains transient and is consumed only
by a successful fresh commit or a matching stale-result cleanup.

## Decision Log

1. Extend `battle_result_matches` instead of adding a second post-battle system.
2. Store four branch-specific booleans in existing save `flags`.
3. Keep Training Hall receipt meaning in the VN controller, not `GameState`.
4. Require zero/one receipt cardinality and diagnose multiple receipts.
5. Compare a pending result before receipt-first routing to expose conflicts.
6. Recheck cardinality at the mutation boundary.
7. Keep the instance-local executed-node guard as secondary protection.
8. Preserve invalid/conflicting evidence and reuse the existing fallback line.

## Validation Boundary

Regression coverage must prove all four fresh commits, same-instance redraw,
new-instance re-entry, save/load, old-save compatibility, equivalent stale
result cleanup, conflict preservation, multiple-receipt fallback, invalid and
Defeat preservation, reset behavior, exact four-field schema, and retained VN,
combat, layout, import, parse, and smoke validation. No commit or push is part of
M6.6 delivery.

The local ignored Source of Truth may change only in Current Priority to mark
M6.5 and M6.5.5 complete, M6.6 active, and M6.7 next. Its backup remains
untouched and the Source of Truth must not be staged or committed. M6.7 is not
started by this work.
