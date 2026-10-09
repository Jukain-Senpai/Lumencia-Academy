# M5.4 — Scythe / Sword / Whip + Replica Form Hotkeys

## Understanding summary

- Extend the existing four-slot Replica Form Chain with the approved order Scythe → Sword → Whip.
- Resolve each hit from the authoritative semantic lines produced by every earlier hit.
- Add Scythe Hit-4 ×2, Sword pre-damage self-advance, and Whip post-damage enemy pull.
- Apply form-specific position efficiency and target Line Exposure only to Jukain's M5.4 Replica hits.
- Preserve the one-target, four-hit, one-action, no-retarget M5.3 architecture.
- Add six semantic InputMap actions; slots 1–3 map to current forms and 4–6 remain unassigned.
- Mouse and keyboard use the same form-selection function. Settings remapping, Gun, Spear, Rapier, Counter, Bind, and M5.5 remain out of scope.

## Assumptions and non-functional requirements

- The sandbox is deterministic and local; there are no networking, scale, persistence, or privacy changes.
- Damage uses one combined integer percentage calculation and ceiling at the end. This is temporary prototype rounding, not final balance.
- InputMap is the remapping boundary. Combat code reads semantic actions and never branches on numeric keycodes.
- Key echo/repeat is ignored; one pressed action event may append at most one form.
- Chain selection projects lines only. It never predicts HP, damage, defeat, Burn, or battle results.
- Runtime still re-reads Jukain line, target line, target life, and Whip reach for each hit.
- Restart clears chain state synchronously; no asynchronous form callback or cached projected state exists.
- Existing controller ownership is retained for maintainability; no generic weapon, input, damage, or line manager is introduced.

## Considered approaches

1. **Extend the controller-local enum and chain loop (selected).** Add two enum values, compact form helpers, one centralized slot mapping, and narrow line/damage helpers. This preserves M5.3 ownership and minimizes lifecycle risk.
2. **Dedicated Replica weapon resources/models.** Data-driven resources could scale to many weapons, but only three locked forms exist and their sequencing still belongs to the controller.
3. **Generic combat-effect pipeline.** A reusable movement/damage/displacement engine would be broader than the approved milestone and prematurely encode deferred mechanics.

## Final design

### Forms and damage

`JukainReplicaForm` contains `SCYTHE`, `SWORD`, and `WHIP`. Per-hit helpers provide display label, damage type, attacker-line efficiency, reach, pre-damage movement, post-damage displacement, and the Scythe Hit-4 modifier.

Target Line Exposure is Front 115%, Mid 100%, Back 85%. Scythe efficiency is 100% from every Jukain line. Sword is 100/60/35% at Front/Mid/Back, but moves Back→Mid or Mid→Front before its own efficiency is read. Whip is 100/100/60% and does not move Jukain.

Temporary prototype damage is:

`ceil(effective_atk × efficiency% × exposure% × form_modifier% / 1,000,000)`

The form modifier is 200% only for Scythe in slot four; otherwise it is 100%. Damage types remain Slash for Scythe/Sword and Blunt for Whip.

### Sequential resolution

For every slot, runtime validates target life and form reach, applies Sword movement, re-reads both current lines, calculates and applies damage, checks defeat/Victory, then applies surviving-target Whip displacement. Battlefield rendering occurs after each complete hit so later hits and tests observe authoritative lines.

Whip reach is Front/Mid target from Jukain Front or Mid, and Front target only from Jukain Back. A surviving target pulls Front→Front, Mid→Front, or Back→Mid after damage. Target death prevents displacement and every later effect.

### Projected-selection validation

When adding a form, the builder recomputes projected Jukain and target lines from the live starting lines and the already selected slots. Sword projection occurs before its hit. Whip reach is checked at that hit's projected start, then a valid Whip projects its post-hit pull for later slots. Scythe changes no line.

An unreachable proposed form is rejected with lightweight status text and no slot, action, damage, or queue change. Undo simply removes the final slot; the next selection recomputes projection from the remaining array. Cancel discards the array and target. HP and death are never projected, so an earlier hit that might be lethal does not prevent later form selection.

Execution performs the same line/reach checks against live state. Selection projection is only preventive UI validation, never gameplay authority.

### Input and prompts

`project.godot` defines `jukain_replica_slot_1` through `_6` with default number-key bindings 1–6. One ordered controller constant maps each action to Scythe, Sword, Whip, or unassigned. This mapping feeds event handling, form selection, visible prompts, and tests.

Unhandled pressed, non-echo action events are accepted only while the active Unlocked Jukain has a selected target, an open builder, fewer than four slots, and no terminal/confirmation/target-selection state. Assigned actions call the same `select_jukain_chain_form()` function as the mouse buttons. Unassigned actions return quietly.

Visible button labels derive their bracketed prompt from the InputMap event, not weapon data. Slots 4–6 are shown compactly as reserved/unassigned. A future remapping screen can replace action bindings without changing combat logic; that screen and persistence are deferred.

## Testing strategy

- Add a dedicated M5.4 suite for all six actions/bindings, contextual/echo guards, mouse-keyboard parity, Undo/Cancel/Restart, and reserved slots.
- Cover form types, every efficiency/exposure multiplier, line-only projection, runtime sequencing, mixed chains, early target death, Victory, Burn-once, and one-action behavior.
- Update only M5.3 assumptions superseded by the full form set and Scythe Hit-4 finisher while retaining its structural coverage.
- Run M5.4 through M2.4, import/class registration, battle/main smokes, 1152×648, 1440×810, five-card stability, builder prompts, and `git diff --check`.

## Decision log

- Existing controller-local chain architecture retained over new managers to avoid duplicating lifecycle ownership.
- One centralized six-slot action/form mapping selected over scattered numeric-key branches.
- InputMap-derived prompt text selected so future remapping does not alter weapon data or combat logic.
- Pressed non-echo action events selected so a held key cannot fill multiple slots.
- Combined integer multiplier with one final ceiling selected as the documented temporary rounding convention.
- Line Exposure is scoped only to Replica form hits; older M3/M4 damage remains unchanged.
- Sword movement precedes its own damage; Whip displacement follows its own damage.
- Projected-selection line validation accepted to prevent unreachable Whips without defining skipped-hit semantics.
- Projection is recomputed from slots and never cached, making Undo and Cancel safe.
- Damage/death is not projected; actual target death retains M5.3 stop/no-retarget behavior.
- One target and one completed action retained; per-slot targets and multi-target chains remain deferred.
- Gun, Spear, Rapier, Sword Counter, Whip Bind, remapping UI, persistence, and M5.5 remain deferred.
