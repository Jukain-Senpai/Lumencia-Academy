# M6.1 — Blessing of the Index Compatibility Patch

## Understanding summary

- Resolving the prototype Prescript through Obey grants Jukain one Blessing stack.
- Each stack adds 10% to Jukain's direct outgoing damage for the current battle, with no cap currently defined.
- Blessing is independent from Karma: Blessing modifies outgoing Jukain damage, while Karma modifies enemy damage received by Jukain.
- Blessing never changes stored ATK, effective ATK, line efficiency, Line Exposure, form behavior, or Scythe's Hit-4 modifier.
- The Obey-resolving Locked hit completes Hiruko's HP/resistance/Seal pipeline before the stack is granted, so that hit is not boosted by the stack it earns.
- Restart, Victory, and Defeat clear active Blessing; no VN, story, result-contract, Bond, save, or other persistent state is added.
- Existing Character Inspector and combat-log presentation are extended without new art or permanent battle UI.

## Assumptions and non-functional requirements

- The deterministic local battle sandbox remains the only runtime scale; no networking, persistence, privacy, or security boundary changes.
- Prescript and damage resolution remain synchronous, so the existing controller boundary is sufficient and no event bus or generic modifier framework is needed.
- Reliability means one grant per authoritative Obey transition, read-only rendering, and cleanup at every battle lifecycle boundary.
- Maintenance ownership stays narrow: `JukainCombatState` owns stacks and damage scaling, while `battle_sandbox.gd` owns grant timing, direct-damage integration, presentation, and terminal cleanup.

## Considered approaches

1. **Extend `JukainCombatState` and integrate narrowly in the controller (selected).** This keeps battle-local Jukain state together and touches only the two current direct-damage paths.
2. **Store Blessing in `JukainPrescriptState`.** This would couple a route observer to an independent outgoing combat modifier and blur the Karma/Blessing ownership boundary.
3. **Create a generic buff or damage pipeline.** This would add lifecycle and abstraction work without a second consumer and is outside M6.1.

## Final design

`JukainCombatState` stores `blessing_stacks`, grants without a hard cap, exposes the additive percentage, and applies a final multiplier to an already-resolved positive integer damage value. The state reset clears both Locked/Unlocked state and Blessing.

The authoritative Prescript observation remains after the Basic Attack HP and Hiruko Seal pipeline. Only a successful transition whose route is `OBEY` grants one stack and writes the one-time gain log. Exploit grants neither Blessing nor Karma. Defy retains its existing Karma grant and grants no Blessing. Unlock remains part of the same transition boundary.

For Basic Attack, the existing attacker and target-specific calculation first produces integer HP damage. For every Replica hit, the complete M5.4 formula first resolves effective ATK, position efficiency, target Line Exposure, and form modifier—including Scythe Hit-4 ×2—to its existing integer result. Blessing then scales each individual result:

`final_damage = ceil(base_resolved_damage × (100 + 10 × blessing_stacks) / 100)`

Positive integer arithmetic uses `(base_resolved_damage × percentage + 99) / 100`. This is **TEMPORARY M6 PROTOTYPE ROUNDING**, not final balance canon.

The affected sources are Jukain Basic Attack and each Scythe, Sword, and Whip Replica hit. Blessing does not alter Hiruko attacks or skills, Burn, Laevatain aura, generic allies or enemies, enemy attacks, Karma calculations, movement, reach, displacement, or projected-chain validation.

The shared Jukain inspector displays the stack and damage percentage and refreshes through the existing battlefield render after Obey. The combat log announces the grant and current +10% increment once at resolution, never during ordinary calculations. Restart rebuilds state; Victory and Defeat clear active stacks. No external art is required.

## Decision log

- `JukainCombatState` owns Blessing because it is battle-local Jukain combat state; Prescript state remains route/Karma focused.
- The successful Prescript transition owns the grant because render and log refreshes are not gameplay authority.
- Grant occurs after damage and Hiruko's Seal update, preventing the earned stack from modifying its resolving hit.
- One final per-hit modifier preserves M5.4 integer damage and Scythe/Sword/Whip sequencing.
- Uncapped integer storage preserves controlled stacks above three without inventing balance policy.
- Explicit terminal clearing prevents active combat progression from leaking into later milestones.
