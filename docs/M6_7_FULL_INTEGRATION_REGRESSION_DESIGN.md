# M6.7 Full Integration Regression Design

## Purpose and Baseline

M6.7 is the final Milestone 6 completion audit. Its standard is **prove
composition, not re-implement features**. It adds no mechanics, dialogue,
save fields, or production framework. The audited baseline is commit
`7388639b5f0c754ce0247944ef914beef05030d3`
(`feat: persist post-battle reactions exactly once`), with M6.6 committed and
the tracked tree/index clean.

The automated result may establish:

```text
M6.7 AUTOMATED VALIDATION COMPLETE
MILESTONE 6 COMPLETE AFTER FINAL MANUAL ACCEPTANCE
```

It must not claim final Milestone 6 completion before the user-facing F6 pass.
Milestone 7 is not started.

## Integrated Ownership Chain

The dedicated suite drives the real runtime handoff:

```text
Training Hall VN entry
→ six approved dialogue lines
→ explicit start_battle action
→ integrated battle initialization
→ real Prescript route behavior
→ real Victory and five-field result
→ automatic VN return
→ contextual reaction
→ one persistent receipt and Bond consequence
→ pending result consumption
→ save/load at the exact VN node
→ receipt-only fresh VN re-entry without repeated consequence
```

The five top-level result fields remain `outcome`, `encounter_id`,
`prescript_id`, `prescript_route`, and `facts`. The suite audits the current
authoritative facts without redefining their schema.

## Scenario Architecture

One scenario-oriented `SceneTree` suite owns eight independent flows:

1. Full OBEY.
2. Full EXPLOIT.
3. Full normal DEFY/replacement.
4. Full terminal-death DEFY.
5. Unresolved death, simulated revival, then real OBEY precedence.
6. Integrated Defeat, Restart, then fresh valid Victory.
7. Standalone battle Victory and Restart.
8. Reusable M1/M2 VN choice, condition, flag, Bond, and save/load retention.

Every successful route begins from `m6_training_hall_entry.tscn`, not from a
fabricated result. Route-specific actions stay visible inside the scenario.
Shared helpers are mechanical only: scene loading/waiting, prebattle advance,
enemy cleanup after resolution, save/load, receipt cardinality, and cleanup.
Deterministic enemy cleanup is allowed only after the intended route has really
resolved.

Each scenario resets persistent and transient `GameState`, removes its isolated
save file, and begins with zero Training Hall receipts. Bounded scene waits name
the expected transition (`VN entry → battle` or `Victory → postbattle VN`) when
they fail. No production pause/debug hook is introduced.

## Mandatory Lifecycle Checkpoints

For every successful route:

- Before battle: context absent, zero receipts, no result.
- After VN launch: correct encounter context, zero receipts, no result.
- At real Victory before return: valid five-field result, zero receipts.
- After reaction commit: result absent, exactly one route receipt, correct Bond.
- After save/load: same sequence/node/receipt/Bond, result and routing state absent.
- After fresh postbattle re-entry: same branch/receipt/Bond and no new effect.

## Route Expectations

### OBEY

Jukain performs the real Locked direct attack on Hiruko. Hiruko loses exactly
the resolving one damage, the direct-hit fact latches, OBEY resolves, Blessing
becomes one only after the hit, Karma stays zero, and Jukain unlocks. A later
real Jukain attack proves the approved Blessing modifier before Victory. The
result reports OBEY, direct hit, Blessing one, and Karma zero. Story consequence:
OBEY dialogue, Hiruko Bond `-1`, OBEY receipt only.

### EXPLOIT

Jukain really moves Front → Mid and the controlled enemy actually damages
Hiruko. Jukain never directly attacks her, the enemy-hit fact latches, EXPLOIT
resolves, Blessing/Karma remain zero, and Jukain unlocks. Story consequence:
Exploit dialogue, Bond `-1`, Exploit receipt only.

### Normal DEFY

The original deadline expires without Hiruko damage, granting one Karma and
activating the replacement without an immediate unlock. A real enemy attack on
Jukain loses HP under the existing Karma modifier, completes replacement, and
unlocks while retaining Karma. The controlled case has no early-death fact.
Story consequence: normal Defy dialogue, Bond `+1`, replacement receipt only.

### Terminal-death DEFY

A real enemy attack transitions unresolved Jukain from living to defeated.
Death history latches while the live Prescript remains unresolved: no Karma,
replacement, or unlock is fabricated. Surviving allies win. The terminal result
classifies story-facing DEFY with death true and replacement false. Story
consequence: death-specific dialogue, Bond `0`, death receipt only.

## Additional Retention Scenarios

Death→revival uses the established test-only field restoration, then resolves a
real OBEY action. The real route must win while the historical death fact remains.
No revive feature is introduced.

Integrated Defeat publishes no Victory consequence or receipt. Restart clears
the abandoned result, facts, death history, Blessing, Karma, and terminal/return
guards while preserving encounter context. The retry produces one fresh OBEY
result, receipt, and Bond consequence.

Standalone Victory publishes no story result, receipt, Bond, or VN transition;
its terminal and Restart remain usable. The reusable VN independently proves
ordinary choice effects, condition routing, flags, Bonds, and exact-position
save/load without any M6 receipt requirement.

## Cross-Cutting Audits

- Result schema contains only the approved five top-level fields and six facts;
  it excludes HP, enemies, lines, status timers, queues, UI, receipts, and VN node.
- Exactly one of the four Training Hall receipt flags is true after each valid run.
- Bond values remain contextual data effects (`-1`, `-1`, `+1`, `0`), not a
  generic OBEY/EXPLOIT/DEFY morality map.
- Blessing/Karma remain battle-local and never enter the save payload.
- Save keys remain exactly `sequence`, `node`, `flags`, and `bonds`; battle
  result/context, VN handoff, HP, and combat state remain absent.
- Old saves without receipt keys and M2.4 malformed-save handling remain covered
  by retained suites.
- M4 Hiruko, M5 Jukain, M6.3.5 reach, and M6.6 invalid-state behavior remain
  owned by their retained regressions.

## Retained Matrix and Presentation

Run M6.7, every available M6.1–M6.6 suite, M5.1–M5.4, M4.1–M4.4,
M3.1–M3.4, and every available M1/M2 regression. Also run Godot import/parse/
global-class validation; main, reusable VN, standalone battle, and M6 entry
smokes; layouts at 1152×648 and 1440×810; Training Hall SHA-256 verification;
and Git/diff safety checks. No missing M1 suite is invented.

## Manual Acceptance

From a clean state, F6 `scenes/vn/m6_training_hall_entry.tscn` four times:

- OBEY: direct Jukain→Hiruko attack, Blessing one, Victory, OBEY dialogue,
  Bond `-1`, save/load exact position, no second decrement.
- EXPLOIT: arrange real enemy damage to Hiruko, no Blessing/Karma, Victory,
  Exploit dialogue, Bond `-1`, save/load without duplication.
- Normal DEFY: expire deadline, Karma one, complete enemy-damage replacement,
  Victory, normal Defy dialogue, Bond `+1`, save/load without duplication.
- Death-DEFY: Jukain dies unresolved, remaining party wins, death dialogue,
  Bond unchanged, save/load retains the reaction identity.

Also lose an integrated battle, Restart, and win to confirm one consequence;
then F6 `battle_sandbox.tscn`, win, and confirm standalone Victory stays in
battle. Check debugger/output throughout for errors and duplicate transitions,
results, Bonds, or receipts.

## Defect Policy and Completion Criteria

Zero production changes is preferred. A small reproduced integration defect may
receive only the minimal fix plus regression coverage. A structural or expanding
defect stops the work for review. The audit document records any defect and fix;
otherwise it records that none were found.

Automated completion requires the dedicated suite, all retained suites, four
successful full routes, Defeat/retry, standalone battle, reusable VN, save/load
apply-once, import/smoke/layout checks, clean diff safety, correct ignored
priority-only Source of Truth edit, and no staged/committed/pushed work.

## Decision Log

1. Use one scenario-oriented integration suite rather than a suite aggregator.
2. Start all four successful routes through the real M6 entry scene/action.
3. Use deterministic internal combat calls only after the real scene launches.
4. Inspect the real result before deferred VN return consumes it.
5. Save/load every route after its contextual consequence commits.
6. Keep all helpers and audit logic inside the M6.7 test file.
7. Treat retained suites as authoritative for local mechanics.
8. Make no production change unless a reproduced defect requires one.
9. Keep route-specific resolution actions explicit, not hidden by helpers.
10. Accelerate remaining combat only after the intended route resolves.
11. Reset persistent/transient state and isolate save data for every scenario.

## Audit Finding

The dedicated integration suite completed without exposing a production defect.
No production source, scene, dialogue, project setting, asset, or save-schema
change was required. The only corrections during implementation were internal to
the new test harness: awaiting its yielding layout assertion and applying the
existing deferred Control-size convention before 1440×810 measurement. M7 is
not started.

Automated audit result:

- M6.7 dedicated suite: 647 checks passed.
- Full retained matrix: 22 suites and 3,901 checks passed.
- Godot filesystem/import, script parse, and global-class scan: passed; only the
  known Windows safe-save warning occurred.
- Main, reusable VN, standalone battle, and M6 entry direct smokes: passed.
- Full-route presentation checks at 1152×648 and 1440×810: passed.
- Training Hall asset hash remained
  `EB942B4339A0FBE595E08A509AEEC1D39CF7EBD9E05D5AC18F1561B8AF2DCA60`.
- Final manual F6 acceptance remains pending.

Status: **M6.7 AUTOMATED VALIDATION COMPLETE — MILESTONE 6 COMPLETE AFTER
FINAL MANUAL ACCEPTANCE.**
