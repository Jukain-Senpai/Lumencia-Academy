# Milestone 2.1 VN External Dialogue Design

## Understanding

- Move the complete Milestone 1 conversation out of `vn_prototype.gd` without changing its player-visible behavior.
- Keep the current VN scene, controller, input handling, character presentation, two choice buttons, ending, and restart flow.
- Represent only the current needs: dialogue lines, one two-option choice, two immediate branches, reconvergence, and an end marker.
- Add defensive loading and validation without introducing persistent state or a general story scripting system.
- Keep technical texture mappings in code and authored conversation content under `data/dialogue/`.

## Assumptions

- The prototype remains local and single-player with a very small dialogue data set.
- JSON authoring and parse errors should be visible in the Godot debugger and should leave the scene in a stable error display.
- Security, networking, localization, high-volume content, and concurrent authoring are outside this subtask.
- Future Milestone 2 requirements may extend or replace this format after their requirements are deliberately designed.

## Final Design

The conversation is stored in one JSON document with a `start` node ID and an ordered `nodes` array. A `line` node contains its speaker, text, expression, and next node ID. The single `choice` node contains exactly two button labels and branch target IDs. Both branches target the same later line to reconverge. An `end` node invokes the existing Scene End presentation.

On scene startup, `vn_prototype.gd` opens and parses the file, validates the root and every supported node, builds an ID-to-node lookup, and verifies all targets. The runner displays the start node and follows `next` or choice `target` references. Load or validation failure emits a useful Godot error and shows a stable in-scene error message instead of indexing invalid data.

## Decision Log

1. **One JSON file.** Godot Resources would add custom resource classes or verbose resource syntax; JSON is the smallest author-friendly external representation for this fixed conversation.
2. **Ordered node array plus explicit IDs.** Separate intro/branch/ending arrays were rejected because reconvergence would remain encoded in controller state. A generic command list was rejected as beyond M2.1.
3. **Three node types only.** `line`, `choice`, and `end` exactly cover existing behavior. Conditions, flags, Bonds, transitions, and arbitrary commands remain deliberately unresolved.
4. **Validation stays inside the existing controller.** A separate loader or Autoload would add architecture without serving the current prototype.
5. **Existing two-button UI is authoritative.** Choice data is validated to exactly two options rather than making the scene dynamically generic.
