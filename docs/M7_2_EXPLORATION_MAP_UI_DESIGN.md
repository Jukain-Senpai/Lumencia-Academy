# M7.2 Exploration Map UI Design

## Goal and Boundary

M7.2 turns the M7.1 Exploration state foundation into a functional,
player-facing node map. The player can see the current location, distinguish
known but unreachable destinations, and travel by activating reachable map
markers. The milestone adds presentation only: no node content, VN/battle
launch, resource collection, inventory, economy, time, final progression, or
save-schema field is introduced.

## Understanding and Assumptions

- `ExplorationState` remains authoritative for context, location, reveal,
  completion, roadblock, reusable metadata, connectivity, and travel validity.
- The UI is reconstructed from state and authored definitions; it owns no
  parallel exploration truth.
- The approved Art Director map is the pre-existing 2560×1440
  `lumencia_forest_exploration_map.png`.
- The prototype has only five neutral presentation names and no canonical
  Forest Exam narrative meaning.
- Expected scale is one small context and a handful of marker Controls.
- The feature uses no network or sensitive data; reliability is enforced by
  state validation, defensive copies, and safe diagnostics.

## Visual Direction

The presentation direction is **Enchanted Cartographer**: the illustrated map
is dominant, while translucent violet-black framing and warm gold accents tie
the screen to the existing VN interface. The recognizable anchor is a layered
circular-cornered marker with a gold current ring and independent corner/status
indicators. Decoration is restrained so M7.2 remains a functional prototype,
not the M9 presentation pass.

## Approved Background Asset

- Original path:
  `assets/art/New folder/lumencia_forest_exploration_map.png`
- Final path:
  `assets/art/backgrounds/lumencia_forest_exploration_map.png`
- Dimensions: 2560×1440
- Original and final SHA-256:
  `68A53B944589B1414F1447D6726C2C8864897DACB08360E11A197992CF3681CE`

The file was moved byte-for-byte. It is not re-encoded, resized, recolored, or
otherwise edited. Labels and indicators remain Godot overlays.

## Architecture and Ownership

```text
M7ExplorationPrototype
└─ ExplorationMap
   ├─ Backdrop
   ├─ MapFrame
   │  ├─ MapTexture
   │  └─ MarkerLayer
   │     └─ dynamic Button markers
   ├─ HeaderPanel
   ├─ LegendPanel
   └─ DiagnosticPanel
```

The reusable `ExplorationMapController` reads
`GameState.exploration_state`, synchronizes visible Controls, requests travel
through `move_to_node()`, and rereads state before repainting. It never assigns
runtime exploration fields directly. The separate prototype root registers
and activates test content in `_enter_tree()`; the reusable map never invents
a missing context.

M7.1 gains three read-only presentation boundaries:

```gdscript
get_active_context_definition()
get_active_node_definitions()
get_node_definition(node_id)
```

All return deep defensive copies so UI code cannot mutate authored nested data.

## Presentation Metadata

M7.2 adds only:

```gdscript
Context: "display_name": String
Node:    "display_name": String
         "map_position": Vector2
```

The controller requires finite normalized coordinates in the inclusive
`0.0...1.0` range. Missing names, wrong types, NaN/infinite values, or
out-of-range positions are configuration errors and display the diagnostic.
Coordinates are never silently clamped.

## Prototype Context

The neutral five-node layout is:

```text
Old Trail ↔ Riverside Camp ↔ Stone Crossing ↔ Ruins Approach
                  ↕
              Deep Grove
```

Old Trail begins current. Riverside Camp, Stone Crossing, and Ruins Approach
are revealed; only Riverside Camp is reachable from the start. Deep Grove is
hidden and is revealed by completing Riverside Camp through the M7.1 state API
in the automated regression. Riverside Camp is authored reusable and initially
roadblocked so the UI can prove overlapping facts without adding functionality.

## Responsive Marker Positioning

`MapTexture` uses keep-aspect-centered rendering. The controller calculates the
actual rendered texture rectangle from the source and available dimensions,
then makes `MarkerLayer.position` and `MarkerLayer.size` equal that rectangle.
Each marker center is simply:

```gdscript
node.map_position * MarkerLayer.size
```

Therefore letterboxing offsets the whole marker layer once; individual markers
remain attached to the same landmarks. The regression verifies normalized
centers, containment, and overlap safety at 1152×648 and 1440×810.

## Reveal, Reachability, and Interaction

- Hidden nodes have no marker Control and cannot receive input.
- Revealed but unreachable nodes remain visible and disabled.
- Revealed connected destinations are enabled Buttons.
- The current marker is visible, unmistakable, and non-travel-interactable.
- Activation requests `move_to_node(node_id)` and then refreshes from state.
- A rejected travel caused by state changing after render is expected; the UI
  refreshes without optimistic mutation or an error panel.
- An unknown marker ID is an invariant/configuration error and shows the
  diagnostic.

Marker Buttons are kept in `marker_buttons[node_id]`. Ordinary travel updates
the same instances, preserving predictable focus behavior. Controls are added
or removed only when reveal state changes.

## Layered Visual Composition

Visual facts have presentation layering, not semantic precedence:

```text
reachable/unreachable base
+ completed muted interior and check
+ current gold outer ring and CURRENT tag
+ roadblock red badge
+ reusable loop glyph
```

A current, completed, roadblocked, reusable node displays every applicable
layer. Completion never disables an otherwise reachable destination, and
roadblocks do not override M7.1 travel rules.

## Refresh and Invalid Context Lifecycle

Refresh occurs after scene entry, viewport resize, explicit external state
changes, and every travel request. A valid context hides the diagnostic and
enables the map. Missing context/background or malformed presentation metadata
hides the marker layer, disables map interaction, and shows a concise
developer-facing diagnostic. The controller never repairs or mutates invalid
state.

## F6 Prototype Entry

`scenes/exploration/m7_2_exploration_prototype.tscn` is the standalone F6
entry. Its root is the only prototype bootstrap owner. The main scene and M6
story flow remain unchanged.

## Regression Strategy

The dedicated suite instantiates the real prototype scene, background, context,
and dynamic Buttons. It verifies initial reveal/current state, real Button
signal travel through M7.1, stable instance identity, keyboard focusability,
revealed-but-unreachable handling, hidden-to-revealed synchronization,
completed return travel, layered four-fact presentation, invalid travel and
invalid-context safety, normalized layouts at both target resolutions, and no
render-side completion.

## Deferred Work

M7.3 owns VN/battle/resource node content. M7.4 owns inventory. M7.5 owns
economy and reusable hub actions. M7.6 owns time/rest. M7.7 owns final
progression and warnings. M7.8 owns persistence. M8 owns Forest Exam content,
and M9 owns final visual polish.

## Decision Log

1. Use dynamic Button markers rather than pre-authored marker nodes or custom
   hit testing for data ownership, accessibility, and maintainability.
2. Use one reusable scene/controller instead of a map framework or manager.
3. Use the approved art unchanged and omit connection lines because its roads
   already provide spatial readability.
4. Add only display names and normalized positions as presentation metadata.
5. Keep ExplorationState authoritative and expose only deep-copy read APIs.
6. Make MarkerLayer track the actual rendered image rectangle.
7. Keep marker instances stable; add/remove primarily on reveal changes.
8. Compose visual facts in layers rather than exclusive style states.
9. Keep reusable-scene failure behavior separate from prototype bootstrap.
10. Reread authoritative state after every travel request instead of assuming
    success.
11. Reject invalid normalized coordinates instead of silently clamping them.
12. Treat normal travel rejection as expected and broken marker/context data
    as diagnostic-worthy.
