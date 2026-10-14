# M7.9 — Full Exploration Regression & Closure Preparation

## Scope and design lock

M7.9 is a stabilization and evidence milestone for the accepted M7.1–M7.8 foundation. It adds one deterministic, isolated regression that follows the existing M7.7 prototype through real Exploration, VN, Battle, hub, inventory, time, save/load, warning, and result scenes. Existing focused suites remain authoritative for detailed rule variants. Production behavior changes only for a reproduced P0/P1 or blocking P2 defect. M7 is not declared complete until manual F6 acceptance and director review.

Assumptions: a single local prototype context and save slot; small bounded runtime state; no player save may be touched by automated tests; scene readiness and valid viewport geometry, rather than elapsed wall-clock delays, control test input; the new suite and this report are the maintenance handoff. No M8 content, new routing framework, aesthetic redesign, or save-schema change is in scope.

### Decision log

| Decision | Alternatives considered | Reason |
| --- | --- | --- |
| One real-scene journey plus a fresh early-progression branch | Many independent M7.9 micro-tests; a state-only snapshot mega-test | Exposes cross-mode ownership and routing without duplicating the focused suites. |
| Exercise existing UI signals and scene transitions, with direct API calls only for deliberate rejection probes | Rebuild gameplay in test fixtures | Keeps normal play paths representative and failures attributable. |
| Use a unique custom `user://` directory per run | Share or backup the player's save | Prevents player-save alteration and inter-suite ordering dependence. |
| Record existing focused-suite evidence for rule variants | Repeat every M7.1–M7.8 assertion in M7.9 | Integration coverage, not raw assertion count, is the goal. |
| Report unsupported authoring and checkpoint boundaries explicitly | Claim general data-driven M8 readiness | Current routers contain explicit content IDs and M7.8 saves only stable map/result states. |

## Baseline

- Expected accepted HEAD: `a0d5a6ab439ec420d8ffd685f919dc21fe2244cf` (`feat: integrate exploration save and load`). Verified at the start; `main` matched `origin/main`, tracked worktree and index were clean.
- Existing inventory: 30 retained M2–M7.8 regression suites. Baseline M7.8 dedicated suite passed, 240 checks.
- `tests/m2_4_save_load_regression.gd.uid` is unrelated and remains untracked. Both Source-of-Truth files are ignored and untracked. Backup SHA-256 baseline: `D8E7B60F8525748AF04262C1415A00A23C53E43292CB61ED2BDA6E77EAC5D79E`.

## Existing-suite audit and integration gap

The 30 retained suites cover M2 save/load; M3–M5 standalone Battle, Hiruko, Jukain, Burn and Prescript behavior; M6 VN/Battle routing, contextual reactions, apply-once receipts and story integration; and M7.1–M7.8 state, real map Buttons, VN/Battle/Resource handoffs, overflow, Shop, HP, time, Rest, warning, closure and persistence. M7.7 exercises physical mouse/keyboard warning controls and condition-based viewport geometry. M7.8 exercises cold loading, malformed data, route rollback and the Riverside VN-load P1 fix. Several suites intentionally inspect internal state or emit Button signals to keep combat and transaction setup deterministic. None previously walked one fresh M7.7 session through all of those systems, then continued after a cold mid-journey load. That is the new suite's narrow gap.

| Retained M7 suite | Main evidence | Scene/input depth and overlap |
| --- | --- | --- |
| M7.1 | Definition/travel/reveal/independent facts/rejection | State-only; M7.2 covers its map projection. |
| M7.2 | Real map, Button identity, marker reachability, layout | Real scene/Button activation; overlaps travel, not content resolution. |
| M7.3 | VN return, Battle Victory/Restart/Defeat, resource return | Real scene transitions with deterministic result fixtures; each content type starts separately. |
| M7.4 | Global inventory, overflow, party HP and battle item behavior | UI and state owners; overflow/HP also exercised in M7.6/M7.8. |
| M7.5 | Shop transaction atomicity, UI, VN/Battle returns | Real map panels and Buttons; separate prototype sessions. |
| M7.6 | Three time modes, Camp/Night Rest, event action costs | Mix of real scenes and state/API probes; Rest and overflow overlap M7.4/M7.5. |
| M7.7 | Warning variations, early exit, closure, geometry | Real mouse and keyboard dispatch; earlier offscreen-click flake has a geometry-based wait and is repeated here. |
| M7.8 | Versioned/legacy saves, cold restoration, rollback, P1 VN load | Real map/result/VN routing plus snapshot validation; does not follow all content after one cold load. |

No unresolved flake was observed in the final five-run focused audit. M7.9 adds the missing continuity across those boundaries, not another copy of each unit-level rule test.

`tests/m7_9_full_exploration_regression.gd` runs in a unique custom `user://` directory and removes only its own save. It uses the real M7.7 entry, reusable map, Riverside VN, Battle sandbox and result scenes. Button signals activate the real map/Shop/Inventory/Rest/Save/Warning controls. The VN's established advance method and Battle's result recognizer use deterministic combat fixtures; M7.7's retained suite separately covers actual mouse/keyboard dispatch. Scene waits are bounded by readiness and the map's deferred marker creation, not wall-clock sleep.

The complete path verifies: initial state → free travel → Shop purchase → Riverside VN completion/reveal/time → Stone Victory/HP synchronization → Ruins reward overflow/ITEM badge → Rest, Wait, sixth-action Rest and Night Rest → version-2 save with leftover, money, HP, flags/Bond, clock and exhausted Rest → explicit reset and cold VN Load to map → no replay or reseed → UI Herb use, leftover pickup and Shop revisit → optional-complete progression → result save/cold load/closure. A separate fresh early-exit path verifies warning summary, blocked underlay, Go Back's full-session equality, Continue and optional-content independence. Rejected full-inventory retry, exhausted Rest, duplicate content, closed-context activation and stale handoffs are checked in the journey; the focused suites remain the evidence for the larger failure-safety matrix.

| Rejected operation | Executed regression evidence | State-preservation boundary |
| --- | --- | --- |
| Disconnected or hidden travel | M7.1, M7.2 | Current node/reveals remain unchanged. |
| Duplicate VN/Battle/resource completion | M7.3, M7.4, M7.9 | No repeated action, reward or reveal. |
| Invalid item use | M7.4 | Inventory and HP remain unchanged. |
| Insufficient Shop funds / full stack | M7.5, M7.9 | No money deduction or granted item. |
| Exhausted Camp Rest | M7.6, M7.9 | No use, HP or clock mutation. |
| Stale VN/Battle handoff | M7.3, M7.8 | No completion; valid pending session survives rejected load. |
| Duplicate leftover collection | M7.4, M7.8, M7.9 | No duplicate item or time charge. |
| Invalid progression | M7.7, M7.9 | Context remains open; no result transition. |
| Malformed/unsupported save and failed routing | M7.8 | Source scene and live state owners preserved. |

## Acceptance matrix

`PASS` means the named automated evidence ran successfully. Manual F6 visual acceptance is deliberately separate.

| Category | Status | Evidence | Outstanding blocker or constraint |
| --- | --- | --- | --- |
| Node travel, reveal, roadblocks | PASS | M7.9 journey; M7.1–M7.3 retained suites | None automated |
| VN integration | PASS | M7.9 real Riverside scene/return; M7.3 and M7.8 P1 lifecycle | New VN IDs still require registration |
| Battle integration | PASS | M7.9 real Battle Victory/return; M3–M6 and M7.3/M7.6 | New Exploration encounters still require routing |
| Inventory and overflow | PASS | M7.9 cap, leftover, ITEM badge, post-load pickup; M7.4 | Only authored Herb item exists |
| Economy | PASS | M7.9 UI purchase/revisit/no time; M7.5 | One prototype Shop/item/currency |
| Party HP | PASS | M7.9 hydration, Victory sync, save/load; M7.4/M7.6 | Fixed six-member runtime roster |
| Contextual time | PASS | M7.9 action and free-travel counts; M7.6 NO_TIME/TIME_SLOTS/MULTI_DAY | Other schedules are unsupported |
| Camp and Night Rest | PASS | M7.9 sixth-action Rest→Night recovery/day 2; M7.6 | Two prototype Camp uses |
| Final progression | PASS | M7.9 all-optional and early exits; M7.7 | Result is prototype, not Forest Exam ending |
| Missable warning | PASS | M7.9 early warning/Go Back; M7.7 ON/OFF, all complete, leftover and hidden-name checks | Manual visual review pending |
| Closed contexts | PASS | M7.9 result cold load and blocked activation; M7.7/M7.8 entry guard | Fresh reset intentionally clears closure |
| Save/load | PASS | M7.9 mid-journey and result cold loads; M7.8 invalid/rollback coverage | Stable map/result checkpoints only |
| Legacy M2/M6 compatibility | PASS | Retained M2.4 and all M6 suites; M7.8 legacy and receipts | Exploration-dependent four-field VN checkpoints intentionally rejected |
| Keyboard and mouse input | PASS | M7.2 marker controls; M7.7 real mouse/keyboard and focus; M7.8 Ctrl+L | Manual F6 physical/visual check pending |
| Scene routing | PASS | M7.9 VN/Battle/map/result/cold loads; M6/M7.3/M7.8 | Explicit destination allowlists remain |
| Regression repeatability | PASS | Final five consecutive M7.7/M7.8/M7.9 runs and full inventory | No observed intermittent failure after harness correction |
| M8 readiness assessment | PASS | Code-authoring audit below | Foundation reusable, routing not arbitrary-data-driven |
| Manual F6 acceptance | NOT TESTED | Requires Game Director/player run | M7 remains active until this gate passes |

## Validation and defect record

- M7.9 dedicated suite: **84 checks, pass** in the final test version. It creates no additional gameplay scene or production framework.
- Final repeated focused runs: **M7.7 5/5 (220 checks each), M7.8 5/5 (240 each), M7.9 5/5 (84 each)**. Earlier five-run M7.9 passes at 85 checks preceded a harness-only simplification; they are not counted as the final version's repeatability evidence.
- Final retained inventory: **31 suites, 5,416 checks, pass** (historical M7.8 baseline: 30 suites/5,332 checks). M1 has no separate regression; the main/VN scene smoke covers startup.
- Godot 4.7.2 headless editor import and global-class registration completed with exit 0. No new GDScript parse error. The known Windows editor `Safe save failed` warning still appears during import and is not treated as a gameplay pass/fail signal.
- Headless scene smokes: **11/11 pass** — project main, standalone VN, standalone Battle, M6 entry, M7.3, M7.4, M7.5, M7.6, M7.7 entry, M7.7 result and reusable map. M7.8 uses those map/result/VN scenes; M7.9's integrated scene path is exercised by its dedicated regression.
- Layout/input evidence at **1152×648 and 1440×810** comes from the executed M7.2/M7.4/M7.5/M7.6/M7.7/M7.8 suites: markers, ITEM badge, panels, Save/Load, warning controls, button focus and mouse target geometry. M7.9 itself uses 1152×648. Aesthetic legibility remains a manual F6 check.
- Production defects found/fixed: **none**. The M7.9 test initially had a harness readiness fault: Godot's map `refresh_map()` is deferred, so `is_node_ready()` alone preceded marker/Inventory rendering. A failing run showed missing markers/targets; the wait now requires the Old Trail marker before continuing. This was a test-only correction, not a gameplay fix or arbitrary delay.
- Known P3 observation from M7.2 acceptance: reusable and roadblock indicators were reported small. No aesthetic change is made in M7.9; manual review should re-evaluate their legibility.
- `git diff --check`: **pass**. No commit or push. No M8 implementation.

## M8 readiness handoff

1. **VN authoring:** The state, handoff, completion and map-return foundation is reusable, but `VNPrototype.DIALOGUE_SEQUENCE_PATHS`/`KNOWN_DIALOGUE_PATHS` explicitly register sequence IDs and known save paths. New M8 VN events require content authoring and routing registration; arbitrary new IDs do not run solely from node data.
2. **Battle and Resource nodes:** The authored `primary_content` shape supports `type` (`vn_event`, `battle`, `resource`), `id`, optional `action_cost` and `optional`, with resource `reward: {type: "item", item_id, quantity}`. Battle IDs currently map through `ExplorationMapController.BATTLE_CONTENT_SCENES`; resource IDs through `RESOURCE_CONTENT_IDS`, and item definitions through the catalog. New content needs those explicit registrations and compatible Battle scenes/items.
3. **Context and time:** Trusted builders duplicate minimal Dictionary context definitions. Nodes author IDs, connections, initial reveal, reveal-on-complete, reusable/roadblock metadata, display name and normalized `Vector2` map position. Existing `NO_TIME`, `TIME_SLOTS` and `MULTI_DAY` modes select the shipped schedule; arbitrary calendars are not supported.
4. **Hubs and exits:** Authored reusable-node `hub_actions` support the current Shop catalog, capped Camp Rest and Wait action shapes. Optional primary content and leftovers drive the warning; a `final_progression` destination currently recognizes only the prototype result destination. New exits need deliberate destination routing.
5. **Persistence:** Version-2 saves safely restore only the allowlisted M7.7 Forest context at stable map checkpoints or its closed result scene. No mid-VN, mid-Battle, pending handoff, arbitrary new context, new save slot or automatic migration is supported. M8 context/version compatibility must be designed explicitly before shipping new durable checkpoints. Legacy four-field standalone VN saves remain exact; Exploration-dependent legacy VN positions are rejected.
6. **Presentation and deferred features:** The real dynamic-marker map, Shop/Items/Rest controls and warning/result UI are reusable prototypes, not a final art/accessibility pass. No procedural maps, free roaming, random encounters, equipment, quest system, cloud sync or full Forest Exam ending exists. M8 can build authored content on the foundation, but cannot claim zero-code content routing yet.

**Assessment:** Foundation-level Exploration integration is ready for M8 content planning, conditionally on manual F6 acceptance and explicit M8 routing/save compatibility work. This is not a declaration that M7 is complete.

## Manual F6 acceptance instructions

Open `scenes/exploration/m7_7_progression_prototype.tscn` in Godot and run the current scene with F6. At both 1152×648 and 1440×810, follow Old Trail → Riverside VN → Stone Victory → Ruins overflow → Camp Shop/Rest/Wait → Save → restart/load → collect leftover → Forest Boundary. Check readable markers/ITEM/roadblock/reusable badges, labels, button focus and mouse/keyboard activation, no content replay or HP/time reset, and no offscreen/overlapping controls. In a separate fresh F6 run, go directly to Forest Boundary, open the warning, Go Back, then Continue; save/load the result and confirm Forest cannot reopen except through an explicit New Game reset. Manual F6 acceptance remains **NOT TESTED** by this headless report.

## Repository hygiene and stopping point

Only the ignored local Source-of-Truth **Current Priority** block was changed: M7.8 complete, M7.9 active/current, M8 next. The backup stays byte-for-byte unchanged at the baseline SHA-256 above. Both files remain ignored/untracked. The unrelated untracked M2.4 UID was untouched. The final `git status` and integrity recheck are recorded in the handoff; no files are staged, committed or pushed. Stop at M7.9 pending manual acceptance and review.

Exact M7.9 additions: `tests/m7_9_full_exploration_regression.gd`, its Godot-generated `.gd.uid`, and this report. The only other local edit is the ignored `docs/LUMENCIA_SOURCE_OF_TRUTH.md` Current Priority block. No tracked production file changed. Final `git status --short --branch` is `## main...origin/main` followed by those three untracked M7.9 files and the pre-existing untracked `tests/m2_4_save_load_regression.gd.uid`; the index is empty. `HEAD`, `main` and `origin/main` still identify `a0d5a6ab439ec420d8ffd685f919dc21fe2244cf`. `git diff --check` passed; the new files have no trailing whitespace. Backup SHA-256 recheck: `D8E7B60F8525748AF04262C1415A00A23C53E43292CB61ED2BDA6E77EAC5D79E`.
