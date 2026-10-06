# Lumencia Academy — Source of Truth

**Document status:** Canonical project reference  
**Version:** 0.1  
**Last updated:** 2026-10-06  
**Engine:** Godot 4.x, GDScript  
**Project type:** Story-first visual novel / turn-based RPG  
**Primary target:** Windows PC demo, later suitable for itch.io distribution

> **Rule:** If a design idea, implementation, prompt, or old chat contradicts this document, this document wins until it is deliberately updated.

---

## 1. Game Vision

**Lumencia Academy** is a story-first fantasy academy visual novel/RPG with menu-driven progression, relationship systems, and character-specific turn-based combat.

The game should feel like a visual novel with meaningful RPG systems rather than an exploration-heavy JRPG.

### Core identity

- Story and characters come first.
- No free-roaming 3D or top-down exploration is required for the demo.
- Locations are selected through menus and presented as VN scenes.
- Combat uses a full six-member party and three combat lines: **Front / Mid / Back**.
- Every playable character has a unique kit based on their actual story abilities rather than a shared class system.
- Player choices affect Bonds, story reactions, and some combat outcomes.
- Jukain's **Prescripts** are a signature mechanic that creates tactical and roleplaying choices during battle.

---

## 2. Demo Goal

The first demo is a **vertical slice**, not a full chapter system.

It only needs to prove that the following experience is fun:

1. VN dialogue and character presentation.
2. Dialogue choices and simple persistent flags.
3. A short academy/story sequence.
4. One simple/tutorial battle.
5. One more meaningful battle that demonstrates the real combat system.
6. Jukain's Prescript → Unlock → weapon-chain gameplay.
7. Hiruko's frontline / Seal gameplay.
8. Story resumes after battle and reacts to at least one combat decision.
9. Save/load works.
10. Basic music and SFX make the presentation feel complete.

### Demo non-goals

Do **not** build these before the vertical slice is fun:

- free exploration
- large inventory system
- full crafting
- every Class Seven character's complete combat kit
- complete calendar / school-year simulation
- romance routes
- dozens of CGs
- voice acting
- online features
- complex procedural content
- final game balance

---

## 3. Core Gameplay Loop

```text
Story / VN scene
      ↓
Player choice
      ↓
Relationship / flag / stat consequence
      ↓
Preparation or party context
      ↓
Battle
      ↓
Combat decisions / Prescripts
      ↓
Battle result
      ↓
Story reacts
```

The important rule is that story systems and combat systems should connect to each other rather than feeling like separate games.

---

## 4. VN Structure

The game is primarily presented through:

- backgrounds
- character sprites / portraits
- expression changes
- dialogue box
- choices
- music
- ambience
- SFX
- camera / screen effects
- occasional important CGs

### Dialogue data should support

- speaker
- text
- portrait / sprite
- expression
- background
- music / ambience change
- choices
- condition checks
- flags
- Bond changes
- transition into battle
- transition back from battle

The implementation should be data-driven where practical so story content does not require rewriting core code.

---

## 5. Party and Battle Structure

### Party

- The active party contains **all 6 Class Seven members**.
- Characters remain in battle full time rather than selecting only 3 active combatants.
- Individual characters may move between combat lines.

### Lines

There are three lines:

```text
FRONT
MID
BACK
```

Position affects targeting, skill behavior, movement, range, safety, and character-specific mechanics.

The line system is not merely cosmetic. It is a central combat rule.

### General combat principles

- Turn-based.
- Speed affects turn order.
- Character kits may manipulate lines and positioning.
- Skills can move the user and/or target.
- Damage types can matter, including at minimum:
  - Blunt
  - Slash
  - Pierce
  - Fire / Burn
- Character mechanics should remain readable without requiring class terminology.

---

## 6. Jukain — Demo Combat Source of Truth

### Identity

Jukain is a volatile adaptive damage dealer whose power is restricted by the Replica.

His combat flow is:

```text
LOCKED
  ↓
Complete / resolve Prescript
  ↓
UNLOCKED
  ↓
Weapon-chain combo
  ↓
Lock returns later
```

### Locked State

- Jukain's **Attack is forced to 1** while Locked.
- His real Attack progression is still stored and becomes active when Unlocked.
- Other stats are not automatically reduced to 1.
- Locked Jukain should still be able to Guard, reposition, use items, and interact with Prescripts.
- His weak Locked attacks can sometimes be useful for creative Prescript solutions.

### Prescripts

Prescripts give Jukain battle-specific tasks.

They normally allow three philosophical resolution styles:

#### Obey
Follow the Prescript as intended.

- Usually straightforward.
- Can create undesirable tactical or relationship consequences.
- May reduce a relevant ally Bond in some situations.

#### Exploit
Satisfy the wording through a clever technical interpretation.

- Intended to reward player creativity.
- Usually gives the best tactical outcome.
- Should feel like discovering a loophole.

#### Defy
Refuse the Prescript.

- Original Prescript fails.
- Can improve an affected ally's Bond.
- The system generates a replacement / changed requirement.
- Defy should not be a free "good" option; it trades convenience for principle or relationship.

The game does not need to expose literal **OBEY / EXPLOIT / DEFY** buttons. The system may classify the player's actual actions behind the scenes.

### Unlocked State

When Unlocked, Jukain regains his actual Attack and can use the Replica weapon chain.

### Weapon Chain

A Jukain offensive action is a **4-hit custom chain**.

Each hit can select one of his currently unlocked Replica weapon forms.

Weapons may repeat.

Example:

```text
Sword → Whip → Gun → Scythe
```

or:

```text
Gun → Gun → Rapier → Gun
```

Each form has unique movement, range, damage, and/or finisher properties.

### Current form concepts

#### Sword
- Slash.
- Advances Jukain toward Front.
- Defensive / counter utility.
- Finisher can grant a Counter stance.

#### Whip
- Primarily control and line manipulation.
- Best around Mid range.
- Can pull / disrupt targets.
- Finisher can Bind or heavily disrupt movement.

#### Gun
- Pierce.
- Can target across lines.
- Accurate ranged option.
- Finisher can Expose the target.

#### Spear
- Pierce.
- Reach / line penetration.
- Useful against formations.
- Finisher can Impale / break armor.

#### Scythe
- Heavy Slash.
- Works from any line.
- Strong finisher identity.
- **4th hit deals double damage**.

#### Rapier
- Pierce.
- High precision / crit / tempo.
- Useful as combo glue.
- Finisher can reposition Jukain backward.

### Jukain design rule

> Other characters learn distinct techniques. Jukain learns more ways to combine weapon actions.

---

## 7. Hiruko — Demo Combat Source of Truth

### Identity

Hiruko is the strongest Class Seven member in raw reliability and physical power.

She is:

- tanky
- hard-hitting
- primarily single-target
- average speed
- naturally drawn to the frontline
- extremely dependable
- able to cover for Jukain and the rest of Class Seven

Even with both sword seals intact, she is already one of the strongest combatants.

Jukain can rival or exceed her burst damage only after successfully reaching his Unlocked state.

### Passive: Sealed Sword

Hiruko has HP plus two additional Seal bars:

```text
HP
Seal [Chains]
Seal [Wrapper]
```

Taking damage also depletes the active Seal state.

#### Both seals intact

- Hiruko takes **70% less damage**.
- Sword attacks primarily deal **Blunt** damage because the weapon remains sealed.

#### Chains broken

Hiruko gains **Flaming Sword**.

- Damage +20%.
- Sword attacks become primarily **Slash**.
- Sword attacks apply **Burn DoT**.
- Damage resistance becomes **35%**.

#### Wrapper broken

Hiruko gains **Laevatain**.

- Damage +40%.
- Remaining damage resistance is lost.
- Allies and enemies are affected by Burn DoT from the sword's dangerous aura.
- Hiruko herself is mysteriously unaffected by the weapon's fire.

The exact numerical values can be tuned later, but this progression is canonical for the demo design.

### Hiruko skill philosophy

Hiruko does not use Jukain-style chains.

Her skills are individual sword techniques.

Typical skills:

- move her toward Front
- deal large single-target damage
- kick / stagger / displace enemies
- follow a kick with a sword strike
- protect or intercept for allies
- punish enemies that try to move her away from the frontline

### Kicks

Kicks are the connective tissue of Hiruko's kit.

General logic:

```text
KICK
Blunt damage
+ movement / stagger / disruption
        ↓
SWORD
Blunt while sealed
Slash + Burn after Chains break
```

Common kick functions can include:

- advancing Hiruko toward Front
- staggering
- breaking Guard
- pushing enemies backward
- controlling enemy formation
- setting up the sword follow-up

Hiruko's kicks remain Blunt even after the sword becomes Flaming Sword / Laevatain.

### Frontline rule

Hiruko strongly prefers Front.

Her skills should naturally return her to Front if displaced.

She should also be difficult to force backward compared with other party members.

### Example technique: Gut Stab

Concept:

1. Hiruko launches herself at the target.
2. Kick deals Blunt damage and advances her toward Front.
3. She follows with a sword strike.

Sword follow-up:

- Sealed: Blunt.
- Flaming Sword: Slash + Burn.
- Laevatain: stronger Slash + Burn.

Hiruko ends at or moves toward Front.

---

## 8. Bonds

Bonds represent relationships and combat familiarity.

They may affect:

- dialogue
- reactions
- Prescript consequences
- passive combat benefits
- combination attacks
- story information
- special scenes

For the demo, only implement enough Bond logic to prove the concept.

A full 10-rank relationship system is not required yet.

---

## 9. Art Direction for the Demo

The demo should be achievable with a low-cost / free pipeline.

### Main asset types

- VN backgrounds
- character sprites / portraits
- expression variants
- enemy illustrations
- UI
- weapon / attack VFX
- a very small number of important CGs

### CG rule

CGs are rare rewards for important moments.

The demo should target **0–2 true CGs**.

Most dramatic scenes should use:

- sprite composition
- close-up crops
- lighting
- overlays
- screen shake
- particles
- sound
- music

### Character consistency rule

For each important character:

```text
Character sheet
→ approved master sprite
→ expression variants
→ CG reference
```

Do not independently regenerate character identity for every asset.

---

## 10. Audio Direction

No voice acting is required.

The demo should use:

- BGM
- ambience
- UI SFX
- combat impacts
- weapon sounds
- Prescript sound identity
- Replica transformation sound identity

Sound should carry a significant portion of the game's presentation.

---

## 11. Technical Direction

### Engine

Godot 4.x using GDScript.

### High-level architecture

Prefer data-driven systems.

Suggested project areas:

```text
res://
├── scenes/
│   ├── vn/
│   ├── battle/
│   ├── menus/
│   └── demo/
│
├── scripts/
│   ├── vn/
│   ├── battle/
│   ├── systems/
│   └── ui/
│
├── data/
│   ├── dialogue/
│   ├── characters/
│   ├── skills/
│   ├── prescripts/
│   └── encounters/
│
├── assets/
│   ├── art/
│   ├── audio/
│   └── fonts/
│
└── docs/
```

### Development philosophy

- Build one small vertical feature at a time.
- Test manually after each meaningful feature.
- Commit after a feature is verified.
- Do not let Codex redesign multiple systems at once.
- Keep game rules in data/resources where practical.
- Avoid premature architecture.

---

## 12. Development Order

### Milestone 0 — Project Foundation

- Create Godot project.
- Initialize Git.
- Add `.gitignore`.
- Create minimal folder structure.
- Add this Source of Truth document.
- Confirm project runs.

**Done when:** empty project launches successfully and is committed.

### Milestone 1 — VN Prototype

Build:

- dialogue box
- speaker name
- next / advance
- character sprite
- expression switching
- background switching
- basic choice selection

Use placeholder art if necessary.

**Done when:** a short Jukain/Hiruko conversation can be played from start to finish.

### Milestone 2 — VN Data + State

Build:

- dialogue data format
- flags
- simple conditions
- simple Bond changes
- transitions between scenes
- save/load foundation

**Done when:** a dialogue choice can change a later line and survive save/load.

### Milestone 3 — Combat Sandbox

Do not integrate story yet.

Build an isolated battle test scene with placeholder rectangles if necessary.

Implement:

- 6 party members
- Front / Mid / Back
- enemies
- turn order
- HP
- Attack
- targeting
- basic damage
- moving between lines
- combat log
- win / lose condition

**Done when:** placeholder characters can complete a basic battle reliably.

### Milestone 4 — Hiruko Prototype

Implement only the rules necessary for Hiruko:

- Seal [Chains]
- Seal [Wrapper]
- 70% / 35% / 0% resistance states
- Flaming Sword
- Laevatain
- Burn
- one movement / kick technique
- Gut Stab
- frontline preference

**Done when:** all three Hiruko states can be deliberately tested in the combat sandbox.

### Milestone 5 — Jukain Prototype

Implement:

- Locked state
- Attack forced to 1
- Prescript framework
- one Obey path
- one Exploit path
- one Defy path
- Unlocked state
- four-hit Form Chain
- initial form behavior needed for the demo

Do not implement every future Prescript.

**Done when:** one battle can demonstrate the full Locked → Prescript → Unlocked → Form Chain loop.

### Milestone 6 — Story ↔ Combat Integration

Build:

```text
VN scene
→ battle
→ result
→ VN scene
```

Pass combat consequences back to story state.

Example:

- player obeys Prescript involving Hiruko
- battle resolves
- post-battle dialogue notices it
- Bond changes

**Done when:** one player decision inside battle changes post-battle story content.

### Milestone 7 — Demo Content

Create the actual short vertical slice.

Recommended scope:

- opening VN scene
- one academy interaction
- one small tutorial fight
- one meaningful fight
- post-battle scene
- ending / demo title card

Use Jukain and Hiruko as the first fully realized combat characters.

The remaining four party members can initially use simplified temporary kits if needed.

### Milestone 8 — Presentation Pass

Replace placeholders with:

- final-ish sprites
- expression variants
- backgrounds
- enemy art
- battle effects
- music
- ambience
- SFX
- UI polish

Do not wait for final art before testing gameplay.

### Milestone 9 — Demo QA and Build

- save/load verification
- input testing
- resolution / fullscreen testing
- combat edge cases
- spelling / dialogue review
- audio volume settings
- Windows export
- itch.io-ready ZIP

---

## 13. Current Priority

The next development task is **Milestone 0**.

Do not begin by implementing the full combat system.

First:

1. Create the Godot project.
2. Create Git repository.
3. Add project folders.
4. Add this document to `docs/`.
5. Build the smallest possible VN prototype.

After the VN prototype works, create the isolated combat sandbox.

---

## 14. Open Design Questions

These are intentionally unresolved:

- Exact turn-order formula.
- Exact global Front / Mid / Back targeting rules.
- Whether characters can manually reposition without using a skill.
- Exact Seal-bar depletion formula.
- Exact Burn stacking rules.
- Exact duration of Jukain's Unlocked state.
- Whether all six Replica forms are available in the demo.
- How many Prescripts the demo battle needs.
- Final damage coefficients.
- Full kits for Ash, Joshua, Elena, and K.
- Final Bond progression structure.
- Full calendar / academy activity system.

Do not invent permanent answers in code without first updating this document.

---

## 15. Definition of a Successful First Demo

The demo succeeds if a new player can finish it and understand:

- who Jukain and Hiruko are
- how dialogue choices matter
- why Hiruko is an absurdly reliable frontline powerhouse
- why Jukain is weak while Locked
- what a Prescript is
- why choosing how to resolve a Prescript matters
- how Jukain becomes dangerous when Unlocked
- how Front / Mid / Back positioning affects combat
- that story relationships and combat decisions influence each other

Polish, content volume, and final balance are secondary to proving those ideas.
