# Milestone 2.3 VN Data-Sequence Transition Design

## Understanding

- Represent the classroom and hallway as distinct external dialogue sequences using the existing VN scene and runner.
- Let classroom data explicitly identify the hallway sequence as its next destination.
- Preserve `GameState` while resetting the runner's current sequence, node lookup, node position, and background.
- Move the `helped_hiruko` conditional reaction into the hallway so it proves cross-sequence state persistence.
- Keep the existing choice effects, Hiruko Bond value, input behavior, character presentation, ending, and restart behavior.
- Exclude save/load, multiple Godot scenes, transition animation, navigation managers, and M2.4 work.

## Assumptions

- Dialogue files are tiny local JSON documents loaded synchronously.
- Each sequence uses the same character and UI composition but declares its own background resource path.
- State and sequence transitions involve no networking, sensitive data, or meaningful performance concerns.
- Invalid sequence or background paths and malformed target data must stop playback in the existing visible error state.

## Approaches Considered

1. **One runner with multiple sequence files (selected).** A narrow transition node loads the next JSON document and swaps its background while the Autoload state survives.
2. **One Godot scene per location.** This would duplicate or parameterize presentation lifecycle code solely to prove a data transition.
3. **Embed both locations in one JSON file.** This would change the background but would not prove loading a distinct external sequence.

## Final Design

Each sequence root adds a required `background` path. The classroom's final line targets a `transition` node containing only a `sequence` path. On reaching it, the runner opens, parses, and fully validates that JSON file using the existing loader. A successful load replaces the current node lookup, start node, sequence path, and background, then displays the new start node. It does not reset `GameState` or apply effects.

The hallway begins with one location-establishing line, evaluates the existing `flag_equals` condition, displays one of two Hiruko reactions, and reconverges for two short closing lines before the existing end presentation. Restart remains the only UI action that resets state and reloads the initial classroom sequence.

## Decision Log

1. **Add one `transition` node type.** A dedicated node is explicit and avoids overloading `end` with optional behavior.
2. **Store the target as a resource path.** This is the smallest external-data-driven connection between two local sequence files.
3. **Require a root `background`.** Location presentation stays authored with its sequence without introducing background-change commands.
4. **Reuse one runner and scene.** The existing layout already supports both locations, so another `.tscn` provides no benefit here.
5. **Preserve state by omission.** Sequence loading changes runner data only; no extra state-copy or transition manager is needed.
