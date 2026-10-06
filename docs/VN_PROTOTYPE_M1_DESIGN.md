# Milestone 1 VN Prototype Design

## Understanding

- Build one playable Jukain/Hiruko classroom scene that proves basic VN presentation.
- Reuse the existing classroom and character-expression artwork.
- Support mouse and `ui_accept` progression, a single two-option choice, reconvergence, a clear end state, and restart.
- Keep the implementation local to the prototype and deliberately avoid Milestone 2 state or dialogue architecture.
- Make the prototype the main scene because the project has no existing entry point.

## Assumptions

- Existing/default project display settings remain unchanged; anchors and containers keep the UI usable at the current window size.
- Both characters remain visible, and simple modulation identifies the current speaker.
- A plain color end screen is a non-canonical test presentation used only to prove a visible background transition.
- This is a local, single-player prototype with no persistence, security, networking, or scale requirements.

## Final Design

`VNPrototype` is one `Control` scene with a background, two character `TextureRect`s, a dialogue panel, a normally hidden choice panel, and a normally hidden end screen. One attached script owns small local arrays for the fixed intro, each immediate branch, and the shared ending. It advances through a few explicit local states, updates the speaker, line, and matching expression texture, blocks normal advancement while choices are visible, and reloads the current scene on Restart.

## Decision Log

1. **One scene and one controller script.** Separate UI, content, and orchestration layers were rejected because they add structure that this isolated prototype does not need.
2. **Scene-authored controls with local arrays.** A Resource, JSON format, parser, and global manager were rejected as premature Milestone 2 work.
3. **Default display configuration.** A fixed 1280x720 project setting was rejected; anchors and containers are sufficient for the existing/default window.
4. **Both supplied sprites remain visible.** Trivial modulation provides speaker emphasis without animation or reusable speaker-state infrastructure.
5. **Color end screen.** This visibly replaces the story background without inventing a second canonical location.

