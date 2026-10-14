# M7.6 — Contextual Time and Rest Design

## Status and understanding

Approved after M7.5 commit `90bb3c71d1d62e5b4ae7161ff8c4f67cd70cd0ff`,
manual F6 acceptance, and a green M7.5 regression. This milestone proves that
one Exploration framework can be untimed, use daypart slots without healing,
or run multiple days with automatic Night Rest. It adds a limited prototype
Camp Rest at Riverside Camp without replacing its Shop or VN event. It is not
the Forest Exam schedule or a story-content pass.

## Assumptions and non-functional boundary

This is a local, single-player prototype with one active Exploration context,
five map nodes, and six fixed party members. Clock changes, event resolution,
and recovery are synchronous and small enough for in-memory Dictionaries.
There is no network, account, personal data, real-world calendar, or external
availability requirement. Invalid inputs and duplicate activations must leave
clock, HP, Rest uses, money, Inventory, and completion unchanged. The existing
Exploration, GameState, and PartyRuntimeState owners remain maintainers; no
second clock or permanent HP owner is introduced. M7.8 owns persistence.

Completing a resource primary interaction is successful even when its item
reward overflows Inventory into a leftover. That completion costs one timed
action; collecting the leftover later costs zero.

## Approaches and decision log

1. **Selected:** narrow clock fields and Rest counters in `ExplorationState`,
   with `GameState` synchronously coordinating party recovery and existing
   cross-mode completion handoffs. This preserves one clock owner and one party
   HP owner while minimizing M7.3–M7.5 changes.
2. A separate GameState `TimeState` would simplify access from VN and Battle,
   but make context ownership and reset timing ambiguous. Rejected.
3. UI-managed time would keep code local to the map, but lose state across
   VN/Battle scene changes and permit duplicate charges. Rejected.

Additional decisions: the day schedule is fixed at 2/2/2 rather than a
configurable calendar; `primary_content.action_cost` is an optional integer
`0` or `1` with a default of `1` in timed modes; the prototype's explicit
`Wait / Advance Time` hub action supplies repeatable test actions without
rewards or a global Wait system; recovery percentages are fixed at 50 and 20
rather than new authoring knobs.

## Authored data and runtime ownership

Contexts may add `"time": {"mode": "NO_TIME" | "TIME_SLOTS" | "MULTI_DAY"}`.
Absence means `NO_TIME`. The only valid time key is `mode`; malformed or
unknown values reject the context. Authored data and nested hub definitions
remain deep-copied by the existing Exploration read APIs.

`ExplorationState` owns `time_mode`, one-based `day_number`, `daypart`,
`actions_spent_in_daypart`, and `total_timed_actions`. A fresh activation
initializes Day 1 Morning 0/2 and fresh per-node/action Rest counters.
`clear_runtime` resets both; reloading map/VN/Battle scenes does not. A
read-only snapshot API feeds the UI. There is no GameState, VN, Battle, or UI
copy of the authoritative clock.

Riverside Camp in the distinct M7.6 fixture retains its existing Shop and
adds `{id: "prototype_camp_rest", type: "rest", display_name: "Camp Rest",
max_uses: 2}`. A timed-fixture-only `wait` action has an ID, type, and display
name, with no rewards or use counter. Hub metadata validation remains narrow:
unique IDs, exact fields, positive Rest maximum, and reusable-node ownership.
The M7.5 context remains untimed and has no Rest or Wait action.

## Time and completion flow

Travel, Shop, Items, Healing Herbs, and leftover collection cost zero. In a
timed context, successful primary VN terminal return, Battle Victory, or
resource resolution costs one action by default; an authored zero-cost
exception costs zero. Launch, Defeat, Restart, failures, and completed-event
retries cost zero. In `NO_TIME`, every interaction costs zero regardless of
metadata.

`GameState.resolve_pending_exploration_content` remains the cross-mode commit
boundary. It validates the handoff, checks whether the node already completed,
completes it once, and only then charges its action. A retry observes completion
and cannot charge again. BattleSandbox already syncs final BattleUnit HP to
PartyRuntimeState on Victory before it calls this boundary; no combat-init
rewrite is needed. Resource overflow still resolves its primary content once;
the subsequent leftover collection does not pass this boundary.

Each two charged actions roll Morning → Afternoon → Night. The sixth action
ends the day. `TIME_SLOTS` advances to the next Morning without healing.
`MULTI_DAY` holds the sixth action at a pending day boundary, synchronously
applies Night Rest recovery, then finishes the transition and exposes Day N+1
Morning 0/2. This pending boundary is a narrow future cutscene hook, not an
asynchronous manager. The time result includes a small
day-transition/Night-Rest status for presentation. No seventh action or
separate Next Day button exists.

## Recovery and Camp Rest transaction

PartyRuntimeState computes a full proposed HP snapshot first and applies it
through its existing snapshot validation. For percentage `p`, each member's
recovery is `clamp(ceil(max_hp × p / 100), 1, max_hp)`. Living HP increases by
recovery up to Max HP; defeated HP becomes recovery. Camp Rest uses `p=50`;
automatic Night Rest uses `p=20`. Neither reconstructs BattleUnits or spends
money/Inventory.

`GameState.use_current_camp_rest` validates active/current node, exact authored
Rest action, remaining uses, and ability to charge time before mutation. It
applies 50% recovery, consumes one use, then charges its timed action. If that
is action six in `MULTI_DAY`, it applies 20% Night Rest once and returns Day 2
Morning. In `NO_TIME`, the Rest use still decreases but the clock does not
advance. A same-frame UI activation guard supplements the authoritative
remaining-use check. Failed or repeated requests cannot heal or charge time.

## Presentation and prototype

A compact time panel below the header appears only in timed contexts. It shows
day, daypart, and actions spent out of two, plus brief day-transition feedback.
The current-node action panel retains Interact and Shop and adds independent
Camp Rest and prototype Wait buttons in a compact two-row layout. Rest shows
remaining uses and is disabled at zero. Buttons remain keyboard focusable;
Travel, Shop, Items, and leftover controls remain usable. Geometry is checked
at 1152×648 and 1440×810, including the M7.4 leftover badge.

`m7_6_time_rest_prototype.tscn` starts a fresh test session, derives the
existing forest Dictionary at runtime, assigns a distinct context ID and
`MULTI_DAY` mode, adds Rest and Wait to Riverside, then instantiates the
existing map scene. It retains the M7.5 money/Herb test fixtures and map art.
The M7.5 entry remains `NO_TIME` and unchanged.

## Verification and deferrals

The dedicated M7.6 suite exercises all three modes, 2/2/2 transitions,
exactly-once VN/Battle/resource charging, real Battle Victory HP ordering,
Defeat/Restart, Camp Rest limits and revival, automatic Night Rest, zero-cost
operations, real scene/Button focus, and responsive geometry. All prior M2–M7.5
regressions and scene/import smokes must remain green before manual F6 review.
The M2 save payload remains exactly `sequence`, `node`, `flags`, and `bonds`.
M7.7 owns progression/missable warnings; M7.8 owns save/load. No later
milestone behavior is added here.
