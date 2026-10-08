# M5.3 — Prescript Unlock Integration + Base Replica Form Chain

## Understanding summary

- Natural Prescript resolution is the sole production unlock trigger: Obey, Exploit, or completed Defy replacement.
- Obey resolves its Locked effective-ATK-1 hit before Jukain unlocks; stored real ATK remains 9.
- Unlocked Jukain gains Form Chain alongside Basic Attack and Move.
- Form Chain owns exactly four independently selected slots; M5.3 exposes only repeatable Scythe.
- One valid nearest-line enemy is selected for the complete chain, which resolves four ordered hit events as one action.
- Early target defeat stops the chain without retargeting; terminal Victory also suppresses post-action Burn and turn advancement.
- Restart and terminal battle state clear or reject every chain-selection path. Sword, Whip, Scythe finisher behavior, and all other M5.4 mechanics remain out of scope.

## Assumptions and non-functional requirements

- The deterministic local sandbox remains the only runtime scale; no networking, persistence, or privacy boundary changes.
- Chain selection is synchronous and controller-local, so no generic ability manager, event bus, or callback queue is required.
- Reliability means unlock happens only inside a successful Prescript transition, exactly once, and rendering remains read-only.
- Reliability also means an incomplete/canceled chain changes no combat state and a complete chain calls the existing completed-action boundary once.
- The current nearest-occupied-enemy-line targeting rule is authoritative for the one whole-chain target.
- Temporary Scythe damage is the current effective ATK with presentation type Slash; all four M5.3 hits are equal.
- Existing battle-generation invalidation remains the stale deferred-enemy safeguard; Restart synchronously clears all chain state.
- Maintenance ownership remains narrow: Jukain state derives ATK, Prescript state owns route/Karma, and the sandbox controller owns selection and resolution.

## Considered approaches

1. **Controller-local chain state and event-driven unlock (selected).** Add a small form enum, target ID, four-slot array, and builder flags to the existing battle controller. Resolve Prescript and unlock in the same gameplay event. This matches current ownership and is the least risky M5.4 extension point.
2. **Dedicated FormChain model.** This could isolate slot validation, but with one form and one target it adds lifecycle synchronization without a real second consumer.
3. **Generic ability/combo framework.** This could model future weapons, but it would prematurely define M5.4 behavior and conflicts with the milestone boundary.

## Final design

### Unlock integration

The controller wraps successful Prescript observations in one `_resolve_jukain_prescript_transition` boundary. When the Prescript model reports that Obey, Exploit, or Defy replacement just resolved, the controller logs the route, calls the existing Jukain state unlock exactly once, and logs effective-ATK/Form-Chain availability. The attack damage was already calculated before this boundary, preserving the Locked Obey hit. Deadline Defy only activates replacement and Karma; it never calls unlock.

Debug Unlock and Reset continue to mutate only `JukainCombatState`. UI rendering reads the resulting state but never reconciles it against Prescript state, allowing deliberate debug-only combinations.

### Chain state and UI

The sandbox owns `selecting_jukain_chain_target`, `jukain_chain_target_id`, and `jukain_chain_slots`. The sole enum value is `SCYTHE`. Form Chain starts only for a living, current, Unlocked Jukain in an active battle. Target selection reuses the existing nearest-line target computation. After a target is chosen, a builder displays four slot labels, Scythe, Undo, Execute, and Cancel controls. One Scythe click appends one slot; repetition is allowed; Execute requires exactly four entries.

Cancel clears target and slots and returns to root actions. Undo pops only the newest slot. All root, target, builder, and terminal UI branches are mutually exclusive.

### Resolution and edge cases

Execution validates the actor, battle, target, and four-slot chain once, then validates target life again before each hit. Every Scythe hit reads Jukain's current effective ATK, applies damage independently, and writes its own hit and HP-transition logs. A defeated target stops later hits and never retargets.

If the last enemy dies, the existing battle-result path ends the battle immediately and skips Burn/queue progression. Otherwise the controller clears chain state and calls `_finish_completed_action(Jukain)` once, producing at most one Burn tick and one queue advancement.

Restart, Victory, and Defeat use the shared action-clear path, which also clears the chain target and all slots. No asynchronous chain callback exists, so a rebuilt fixture cannot receive stale chain execution.

## Testing strategy

- Add a dedicated M5.3 suite covering all unlock routes, debug controls, locked guards, slot independence, Undo/Cancel, targeting, sequential damage, early stop, Victory, Burn-once behavior, one-action integration, Restart stages, inspector updates, layouts, and retained combat behavior.
- Update only M5.2 assertions superseded by the new unlock contract; retain route, Karma, replacement, inspector, Hiruko, and generic combat checks.
- Run all retained M5.2 through M2.4 suites, Godot import/parse, battle/main smokes, layout checks, and `git diff --check`.

## Decision log

- Natural Prescript completion is authoritative for production unlock; renderer polling was rejected because it could duplicate side effects.
- Unlock occurs after the resolving damage event, preserving Obey's effective-ATK-1 hit.
- Controller-local chain state was selected over a manager/model because M5.3 has one actor, one target, and one form.
- Four explicit array entries were selected over a count so slot order and future distinct forms remain representable.
- One target per chain and no retarget were selected as the narrow M5.3 prototype rule.
- Four separate damage/log events were selected over combined damage to prove sequential architecture.
- One call to the existing completed-action boundary was selected to preserve Burn and queue semantics.
- Debug Reset is allowed to re-lock a resolved Prescript without automatic correction; debug controls remain non-production tools.
- M5.4 exclusively owns Sword, Whip, final Scythe balance/reach, and the fourth-hit bonus.
