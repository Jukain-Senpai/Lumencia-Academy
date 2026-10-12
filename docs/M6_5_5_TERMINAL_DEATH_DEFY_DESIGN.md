# M6.5.5 Terminal Death to Deferred Defy Design

## Purpose and bug

M6.3 currently publishes `UNRESOLVED` when Jukain is defeated before the
prototype Prescript resolves and the remaining party later ends the battle.
That result has no valid M6.5 reaction. M6.5.5 records the real defeat event
and classifies a still-unresolved terminal result as story-facing `DEFY`.

This classification does not resolve or otherwise mutate the live
`JukainPrescriptState`. During combat the Prescript remains unresolved, Karma is
not granted, the replacement requirement is not activated or completed, and
Jukain is not unlocked.

## Defeat-transition fact

The result fact `jukain_died_before_prescript_resolution` defaults to `false`.
All legitimate runtime HP-loss paths keep their existing damage calculation and
then pass the already-resolved damage to one narrow HP-loss application helper.
The helper records whether the target was living before the real HP mutation,
applies the final HP loss, and observes whether the unit became defeated.

The observer latches the fact only when:

- the unit genuinely transitions from living to defeated;
- the unit is Jukain; and
- the prototype Prescript is still unresolved after damage.

The observer is damage-source agnostic. Enemy attacks, Burn, existing skills,
and future legitimate callers all receive the same transition behavior. It does
not calculate damage, interpret Seal or Karma, infer facts from terminal state,
or react to direct debug/test field mutation.

The latch is monotonic for one attempt. Healing or simulated future revival does
not clear it, and a later real Prescript resolution preserves it as historical
information. Restart and full battle-result reset are the only clearing points.

## Deferred terminal classification and route precedence

When an integrated terminal result is built, the reported route follows this
precedence:

1. an actually resolved `OBEY` route;
2. an actually resolved `EXPLOIT` route;
3. an actually resolved normal `DEFY` route;
4. unresolved plus `jukain_died_before_prescript_resolution == true` reports
   story-facing `DEFY`; and
5. every other unresolved state reports `UNRESOLVED`.

The fourth case changes only the result contract. It never changes the live
Prescript phase or invokes the normal Defy/replacement pipeline. Consequently a
terminal-death Defy keeps `replacement_requirement_completed == false`,
`karma_gained == 0`, and Jukain's existing lock state. A death followed by
revival and real OBEY, EXPLOIT, or normal DEFY reports that real route instead.

## Story reaction

The M6.5 graph checks normal replacement-completed Defy before terminal-death
Defy. Normal Defy retains its existing dialogue and Hiruko Bond `+1` effect.
The second Defy condition requires the historical death fact and is reachable
only after the replacement condition fails, so the two factual contexts cannot
steal one another's branch.

Terminal-death Defy displays the approved four-line reaction and then joins the
existing shared ending. Its explicit Hiruko Bond delta is `0`. A bare Defy with
neither replacement completion nor the death fact remains malformed and reaches
the diagnostic fallback. Dialogue evaluation does not mutate or consume the
battle result.

## Lifecycle, compatibility, and boundaries

- Victory and Defeat results both use the terminal classification; M6.4 still
  returns to VN only after Victory.
- Restart clears the pending result and all attempt facts, including the death
  latch, while preserving battle context under existing rules.
- The existing full result/debug reset clears the same fact. Character-state
  debug controls do not synthesize a combat death event.
- Standalone battle may maintain the local fact but publishes no story result,
  performs no VN return, and changes no Bond.
- No revive ability, item, UI, death timer, save field, consumed marker, new
  Prescript, universal route reward, or M6.6 behavior is introduced.

## Non-functional assumptions

The battle contains a small fixed roster and local dictionaries, so the common
transition observer is constant-time and has no material performance or scale
cost. The feature introduces no networking, sensitive data, or additional
availability requirements. Maintenance remains with the existing battle result
owner and VN data/condition system; no damage manager or reaction manager is
created.

## Decision log

1. Centralize genuine living-to-defeated observation after final HP damage.
2. Keep damage calculation in its existing source-specific owners.
3. Keep death non-resolving and classify only the terminal result contract.
4. Give every real resolved route precedence over the death fallback.
5. Preserve the historical death fact through future revival and later
   resolution.
6. Distinguish normal Defy and terminal-death Defy through authoritative facts.
7. Give the death-specific story reaction an explicit Bond delta of zero.
8. Clear the fact only with Restart/full attempt reset.
9. Reject terminal-state inference because it loses event ordering and can turn
   debug mutation into a false combat fact.
