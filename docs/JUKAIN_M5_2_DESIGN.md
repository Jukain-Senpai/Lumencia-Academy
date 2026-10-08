# M5.2 — Prototype Prescript + Reusable Character Inspector

## Understanding summary

- Replace the permanent Hiruko and Jukain detail columns with one shared Character Inspector.
- Store inspector selection as a stable party-unit ID and default it to Hiruko after initialization and Restart.
- Preserve combat targeting precedence: neutral allied-card clicks inspect; active target modes keep their existing meaning.
- Implement exactly one Jukain Prescript: “Make Hiruko lose HP before your next turn.”
- Support Obey, Exploit, Defy, one replacement requirement, and battle-local Karma without connecting success to production unlock.
- Preserve M5.1 Locked/effective-ATK rules and all M4/M3 combat behavior.
- Keep Form Chain, reusable kit frameworks, multiple Prescripts, production assets, and M5.3 outside this milestone.

## Assumptions and non-functional requirements

- The sandbox remains a deterministic, local ten-unit battle fixture; no large-scale data or traffic requirements apply.
- Prescript observation is synchronous with the existing turn and damage controller, so no event bus or asynchronous gameplay service is needed.
- No private data, network access, or new security boundary is introduced.
- Reliability means one deadline evaluation per real Jukain turn token, no UI-triggered gameplay transitions, and complete Restart cleanup.
- The battle controller remains the owner of flow integration; the small state model remains independently testable and maintainable.
- Existing ceiling percentage arithmetic is reused for temporary Karma damage rounding.

## Considered approaches

1. **Narrow state model plus controller-local inspector (selected).** Keeps Prescript transitions testable while leaving targeting, damage, and rendering with the controller that already owns them.
2. **All state in controller dictionaries.** Fewer files, but weaker invariants and harder isolated testing.
3. **Generic character-kit/requirement framework.** More extensible in theory, but premature and explicitly outside M5.2.

## Final design

`JukainPrescriptState` stores only the original/replacement phase, baseline and activation turn token, exploit setup, resolved route, deadline evaluation count, and Karma. The controller calls it from Jukain turn start, Jukain Move, confirmed ally Attack, enemy damage to Hiruko, and enemy damage to Jukain. Inspector rendering only reads state.

The shared inspector stores `selected_inspector_unit_id`. A neutral click on any allied card updates that ID and redraws the shared panel. During Attack or Skill targeting the same click is routed to the existing target path instead. Confirmed Jukain-to-Hiruko Attack is the only friendly-fire path.

Karma scales only enemy Basic Attack damage received by Jukain using ceiling arithmetic. Burn, allied damage, outgoing damage, and other units remain unchanged. Prescript resolution never calls Jukain unlock in M5.2.

## Decision log

- Stable ID selected over Control reference so Restart cannot retain stale runtime objects.
- One shared inspector selected over permanent character columns to reduce horizontal pressure and support generic allies.
- Explicit controller branches selected over reflection or registries to keep presentation reusable without creating a generic kit framework.
- One narrow Prescript model selected over a quest/database system because only one locked prototype requirement exists.
- Explicit ally confirmation selected over immediate friendly fire to prevent ambiguous inspector/target clicks.
- Unique Jukain turn tokens selected for deadline guards so redraws, Cancel, and inspector refresh cannot re-evaluate the deadline.
- M5.3 unlock integration remains a visible placeholder only.
