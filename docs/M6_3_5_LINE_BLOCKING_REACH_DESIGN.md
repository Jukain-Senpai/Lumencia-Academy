# M6.3.5 Line Blocking & Weapon Reach Rework

## Goal

M6.3.5 separates physical battlefield position from blocking reach. Units keep
their semantic `FRONT`, `MID`, or `BACK` line for movement, presentation, pull
destinations, and Replica Line Exposure. Target eligibility instead uses the
live depth of occupied opposing lines, ignoring empty lines.

This patch changes reach eligibility only. It does not change damage, Hiruko's
action sequencing, Prescript behavior, Blessing, battle results, VN flow,
persistence, Bonds, or any M6.4 behavior.

## Semantic line and occupied depth

For either team, opposing semantic lines are inspected in `FRONT`, `MID`,
`BACK` order. Empty lines are skipped. The first line containing at least one
living unit has occupied depth 1, the second depth 2, and the third depth 3.
Every living unit in the same line shares that depth; defeated units never
occupy or block a line.

Depth is calculated from live units when needed and is never stored. Removing
the final living unit from a line immediately compresses later occupied depths,
but does not mutate any unit's semantic line.

Examples:

- Empty Front + occupied Mid/Back: Mid depth 1, Back depth 2.
- Only occupied Back: Back depth 1, while still semantically Back.
- Three living units in Front: Front is one depth layer, not three.

## Reach profiles

- Ordinary Basic attacks, current enemies, Hiruko Kick, and the initial Gut
  Stab target use maximum occupied depth 1.
- Replica Sword advances Jukain first, then validates maximum depth 1.
- Replica Whip uses maximum depth 1 from Back, 2 from Mid, and 3 from Front.
- Replica Scythe uses maximum depth 3 from every Jukain line.
- A generic maximum-depth-3 helper profile proves future Gun reach from Back;
  no Gun action, damage, UI, Joshua kit, or weapon hierarchy is added.

Enemy and player attacks call the same faction-neutral depth helpers. Existing
stable-ID ordering within the reachable set remains deterministic.

## Exposure and displacement

Replica Line Exposure remains bound to the target's semantic line:

- Front: 115%
- Mid: 100%
- Back: 85%

Occupied depth is never passed into damage math. A Mid target at depth 1 still
uses 100%, and a Back target at depth 1 still uses 85%.

Whip validates against current occupied depth, calculates damage from the
target's pre-pull semantic line, applies damage, and only pulls a survivor one
semantic line forward. A later hit then sees the new semantic line and freshly
calculated depth.

## Form Chain target selection and projection

The target-selection stage may show any living enemy reachable by at least one
available Replica form. Because current Scythe reaches depth 3 from every line,
all living enemies may be held as the chain target. This does not grant every
form that reach.

Each proposed slot recomputes projected state from the live starting lines and
all retained slots. Sword projects its self-advance before validating depth 1.
Whip validates using the projected Jukain line, then assumes a surviving-target
pull for subsequent slots. Scythe validates depth 3 and moves nothing. Undo
recomputes from remaining slots; Cancel discards projection.

Projection changes only deterministic lines. It never predicts damage or
death, so a living blocker remains occupied unless a deterministic pull changes
its line. Runtime independently repeats reach validation before every hit using
the actual live battlefield after earlier movement, pull, or defeat.

Gut Stab retains one selected target for Kick, movement, and sword follow-up;
the new system does not add retargeting.

## Compatibility boundaries

The old M5.4 Whip rule based directly on target semantic line is superseded by
occupied depth. M5.4 assertions are changed only where they encoded that old
rule. Efficiency, exposure, rounding, damage type, Sword movement, Whip pull,
Scythe finisher, one-target/no-retarget behavior, and four-hit sequencing remain
unchanged.

M6.1 Blessing remains the final modifier on resolved Jukain damage. M6.2 launch
context and M6.3 event-latched result facts remain unchanged. **M6.4 is not
started.**

## Assumptions and non-functional requirements

- The local ten-unit prototype makes on-demand line scans trivial in cost.
- No reach cache exists, avoiding invalidation and stale-state reliability risk.
- No networking, private data, persistence, or security boundary changes.
- The existing battle controller remains the owner for maintainability; helpers
  are narrow and faction-neutral rather than a generic equipment framework.

## Decision log

- Selected live controller-local depth helpers over cached depth tables because
  movement and defeat must be reflected immediately.
- Selected one shared team-symmetric reach function over separate player/enemy
  targeting algorithms.
- Selected projected line overrides over cloning combat units; projection needs
  only deterministic line changes.
- Selected broad chain target selection plus per-form validation because Scythe
  can reach every current occupied depth while Sword and Whip cannot.
- Rejected a weapon class hierarchy and Joshua/Gun implementation as outside
  this focused compatibility patch.
