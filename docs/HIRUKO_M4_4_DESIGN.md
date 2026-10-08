# Hiruko M4.4 — Skill Menu, Kick, and Gut Stab

## Understanding summary

M4.4 adds a Hiruko-only Skill action to the existing battle sandbox. Hiruko's root actions become Attack, Skill, and Move, while generic party members keep Attack and Move. The Skill menu contains Kick, Gut Stab, and Back. Both skills use the existing nearest-occupied-enemy-line targeting rule and consume one complete turn.

Kick deals Hiruko's base ATK as Blunt damage and advances her one semantic line toward Front. Gut Stab is one action containing a 10 Blunt Kick, the same forward movement, and—only if the original target survives—the existing state-dependent sword hit. Flaming Sword and Laevatain apply Burn only from a surviving sword follow-up target.

M4.2 Seal/resistance behavior and M4.3 Burn/aura ordering remain unchanged. M4.4 does not add enemy displacement, stagger, interception, costs, cooldowns, enemy skills, or a generic skill system.

## Assumptions and non-functional requirements

- The sandbox remains a small, local, deterministic battle fixture; synchronous two-hit resolution is sufficient.
- No networking, persistence, sensitive data, or multiplayer concurrency is involved.
- Reliability requires one action-completion call per committed skill, safe menu cancellation, stale-state cleanup on turn changes and Restart, and retained regression coverage.
- `BattleUnit` remains generic. `HirukoCombatState` remains the sole authority for sword damage and type.
- The pre-existing user-owned Source of Truth edit remains untouched.

## Approaches considered

1. **Controller-local enum and helpers — selected.** A small `HirukoSkill` enum plus narrow menu, targeting, movement, and resolution helpers fits the existing sandbox and minimizes scope.
2. **Separate Hiruko skill model.** This could isolate skill definitions, but M4.4 has only two fixed skills and no costs, unlocks, or data-driven behavior, so it adds unnecessary indirection.
3. **Generic skill/action framework.** This could support future characters but would prematurely introduce universal commands, skill data, and multi-hit abstractions explicitly excluded from M4.4.

## Decision log

- Keep all selection and execution state in `battle_sandbox.gd`; this matches the existing Attack and Move authority.
- Represent the chosen skill with a small enum rather than scattered strings.
- Give skill targeting its own valid-target list while reusing `_get_valid_attack_targets()` as the eligibility authority.
- Reuse the existing card click path and route it according to whether Basic Attack or a Hiruko skill owns target selection.
- Use `_finish_completed_action(hiruko_unit)` exactly once after the entire skill sequence so Burn and terminal ordering stay unchanged.
- Ask `HirukoCombatState` for Gut Stab's sword damage and type. Kick remains base ATK and Blunt in every state.
- Add compact buttons to the existing action row; hidden controls do not affect formation/card height.

## Controller state and navigation

The controller stores whether the Skill menu is open, the selected `HirukoSkill`, and valid skill targets. On a living Hiruko turn, the root menu shows Attack, Skill, and Move. Generic allies never expose Skill.

- Skill opens Kick, Gut Stab, and Back.
- Back clears skill-menu state and returns to root actions.
- Choosing Kick or Gut Stab closes the menu and marks valid enemy cards.
- Cancel during skill target selection clears the target choice and returns to the Skill menu.
- Turn advance, battle end, and Restart clear every skill-selection field.

Entering or leaving these menus never calls turn-start processing, so Laevatain's aura token remains untouched.

## Skill resolution

Kick validates the current actor and target, deals base ATK as a distinct Blunt hit, advances Back to Mid or Mid to Front, renders the updated formation, then finishes one action. At Front, Hiruko holds position without a bonus.

Gut Stab captures the current Hiruko sword state, resolves the Kick hit, advances Hiruko, and refreshes the formation. If the same target survives, it resolves one sword hit using `HirukoCombatState.get_basic_attack_damage()` and `get_basic_attack_type_label()`. A surviving Flaming Sword or Laevatain target receives or refreshes Burn to two ticks. A target defeated by either hit has Burn cleared.

If the Kick defeats the target, movement still occurs but the sword stage, retargeting, and Burn application do not. Both skills reach `_finish_completed_action()` once, preserving immediate terminal results and at most one end-of-turn Burn tick on Hiruko.

## Testing strategy

A focused M4.4 regression covers root/menu visibility, Back and Cancel behavior, protected targets, movement from every line, state-independent Kick type, all Gut Stab state profiles, defeat between hits, final-enemy terminal ordering, one-turn consumption, one Burn tick after a full skill, aura-once behavior, unaffected Basic Attack and Move, Restart cleanup, mixed-action battle completion, and both supported layouts. All M2.4–M4.3 suites remain required.
