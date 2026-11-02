# Native EllesmereUI navigation integration plan

Reviewed November 2, 2026 against EllesmereGaming/EllesmereUI `main` at **e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a**. This is a source-based proposal for upstream integration, not an implementation or a claim of in-game validation. Proposed names below do not exist upstream yet.

## Recommendation

Implement Navigation Arrow as an opt-in feature inside **EllesmereUIQoL**, with a **Navigation** page in the existing Quality of Life settings module. Keep tracking resolution, rendering, and lifecycle in separate QoL source files. Use the native profile, font, options, and Unlock Mode systems. Do not ship another addon folder, third-party plugin registration, or separate SavedVariables table as part of EUI.

QoL already owns the `/way` command, several movable HUD displays, and a shared per-profile database. Navigation serves players who track destinations through Blizzard controls, including players who have EUI's Quest Tracker or `/way` command disabled. Housing it in Quest Tracker would unnecessarily couple the arrow to a tracker replacement. Putting it in the root core would load feature-specific navigation logic outside its natural module owner.

The existing `/way` implementation should remain a separate feature. It creates clickable Blizzard map links and handles its own arrival announcements; it does not provide an arrow. Enabling either feature must not enable the other.

## What the upstream review established

All source links in this document pin the inspected revision.

| Area | Existing implementation | Consequence for navigation |
| --- | --- | --- |
| Runtime ownership | [QoL runtime](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUIQoL/EllesmereUIQoL.lua) registers its namespace in `EllesmereUI._ModuleNS` and supplies `ns.CombatQueue` | Share the QoL namespace and lifecycle infrastructure |
| Load order | [QoL TOC](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUIQoL/EllesmereUIQoL.toc) loads feature files after the main QoL file and declares `EllesmereUIQoLDB` | Add resident runtime files to this TOC; retain its parent dependency |
| Existing waypoint behavior | [Waypoint command](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUIQoL/EllesmereUIQoL_Waypoint.lua) is off by default, reload-gated, and reads `EllesmereUIDB.waypointCmd` | Do not put the observer behind that file's early return or consume its private destination list |
| Options | [QoL options](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUIOptions/EUI_QoL_Options.lua) registers `EllesmereUIQoL` using `RegisterModule`, dispatches page builders, and handles cache restore/reset/module leave | Extend the existing registration; do not call `RegisterPlugin` |
| Existing command settings | [Auto Logging options](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUIOptions/EUI_QoL_AutoLogging_Options.lua) also builds the `/way` section and its manual-arrival cog | Leave command settings intact; label the arrow toggle independently |
| Profiles | [Lite database](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUI_Lite.lua) provides `NewDB`; [profile coordinator](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUI_Profiles.lua) already includes QoL and `REFRESH_ADDON_STEPS` | Add a navigation slice to QoL's profile and a native reapply step |
| Positioning | [Unlock registration/listeners](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EUI_UnlockMode.lua) supports owning folders, position callbacks, and session listeners; [Movement Alert](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUIQoL/EllesmereUIQoL_MovementAlert.lua) demonstrates `MakeUnlockElement` | Register a native QoL mover and static preview |
| Sync | [Profile sync exclusions](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUI_ProfileSync.lua) preserve QoL position fields during automatic cross-profile sync | Exclude navigation position and size explicitly |
| Fonts | [Font system](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUI_Fonts.lua) maps `extras` to QoL; [Battle Res](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/EllesmereUIQoL/EllesmereUIQoL_BattleRes.lua) uses `GetFontPath("extras")` | Follow native font settings and refresh paths |
| Packaging | [.pkgmeta](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/.pkgmeta) already moves QoL and Options into their addon folders | Files placed within those folders need TOC entries, not a new packaged module |

## Proposed file placement

```text
EllesmereUIQoL/
  EllesmereUIQoL_NavigationData.lua       # reads, identity, target/step resolution, geometry
  EllesmereUIQoL_NavigationDisplay.lua    # owned arrow/text frames and appearance
  EllesmereUIQoL_Navigation.lua           # defaults, lifecycle, apply, events, mover
  Media/
    navigation-arrow.tga                 # original arrow asset
EllesmereUIOptions/
  EUI_QoL_Navigation_Options.lua          # native QoL Navigation page
.tools/tests/
  test_navigation.lua                    # deterministic data/lifecycle regressions
```

Load data, display, then lifecycle after `EllesmereUIQoL.lua` in the QoL TOC. Add the options file to `EllesmereUIOptions.toc`, alongside the other QoL page files. Resolve its runtime interface through `_ModuleNS["EllesmereUIQoL"]`, as existing QoL options do. Keep runtime creation out of options-page construction.

Use a small `ns.Navigation` interface: proposed operations are `Apply`, `Reset`, `SetPreview`, and `GetDiagnostics`. Keep selection and geometry helpers private to that feature. `Apply` must be idempotent and read the current profile every time. The profile refresh coordinator can resolve this namespace directly, avoiding a large new global API.

The asset's installed path becomes `Interface\\AddOns\\EllesmereUIQoL\\Media\\navigation-arrow.tga`. Do not retain the standalone addon's texture path or addon bootstrap. Confirm asset authorship and contribution rights before upstream submission.

## Storage and settings ownership

Create a **proposed** `db.profile.navigation` slice using `EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults)`. Other QoL features already merge slices into the shared profile. Use a live accessor such as `P()` rather than retaining `db.profile.navigation` across profile switches.

| Proposed field | Default / purpose |
| --- | --- |
| `enabled` | `false`; explicit opt-in, including after upgrading EUI |
| `pos` | unset; native point/relative-point/x/y placement, with a default above center |
| `size` | validated arrow/text dimensions owned by Unlock Mode |
| `opacity` | `1`; affects only the owned display |
| `showDestination`, `showDistance`, `showInstruction` | `true`; independently configurable text |
| `arrowColor` | unset means native accent; optional explicit override |
| `textSize` | native QoL default, using the shared `extras` font |
| `arrivalMode` | `"none"` initially; additional modes require their own implementation and validation |
| `arrivalDistance` | used only when a supported arrival mode is enabled |

Do not persist target identity, coordinates, route state, preview state, acquisition flags, or conversion results in profile data. These are session state. A profile switch changes presentation and enablement, then reacquires the currently tracked destination.

Add `navigation.pos` and `navigation.size` to QoL's `RegisterSyncExclusions` list. Test full profile export/import separately from automatic sync: exclusions should preserve each profile's layout during sync while intentional layout exports retain it. Pass the owning folder `EllesmereUIQoL` when registering the mover so anchor links are attributed correctly.

Extend QoL reset with a navigation-specific reset that changes only this slice, stops its runtime, and resets the mover's anchor/match relationships through the existing layout reset path. Do not call a whole shared-database `ResetProfile()` just to reset navigation. Confirm both the module-wide reset and any page-local reset behavior.

No automatic import from `AlmightreeWaypointDB` is needed for the first upstream version. If migration is later requested, make it explicit and one-time; importing appearance must not silently enable the feature. Until then users can reproduce their placement in Unlock Mode. Detect an enabled standalone arrow and explain the duplicate display in settings rather than disabling another addon automatically.

## Native options and visual integration

Add Navigation to QoL's page list and page-builder dispatcher, and add search terms for navigation, waypoint, arrow, pin, destination, and quest guidance. The page should contain:

1. **Navigation:** enable toggle and static preview control. Explain that Blizzard's selected tracked destination drives the display and `/way` is optional.
2. **Display:** opacity, text visibility, native font sizing/color controls, and a `BuildSectionUnlockJump` link to the mover.
3. **Arrival:** initially describe the absence of arrival behavior. Expose threshold/fade controls only when implemented; do not show nonfunctional controls.
4. **Unavailable guidance:** concise explanation that direction hides when coordinates or routing are unavailable, while useful destination/instruction text may remain.

Follow the surrounding `W:DualRow` patterns, pooled options frames, house tooltips, and localization helpers. Size and position belong in Unlock Mode, matching neighboring HUD features; avoid a second independent drag/lock system or competing scale controls.

Retain the transparent arrow-and-text presentation. Use the native `extras` font and appropriate shared accent/style helpers from the target revision. Trace native font/color refresh dispatch during implementation and ensure the navigation `Apply` path participates. Do not use third-party `RegisterSkin`/`OnLooksChanged` registration as the feature's architecture, or introduce a separate theme selector. Verify readability in the styles actually offered by the target build.

Global Search prebuilding, page cache restoration, switching pages/modules, options close, and combat must not start or strand a preview. Start preview only on explicit interaction. Tear it down through both page/module lifecycle paths and options-close handling. Preview must not write `enabled=true` and must not query navigation APIs.

## Unlock Mode

Register a proposed `EUI_NavigationArrow` element in the Quality of Life group with `MakeUnlockElement` and `RegisterUnlockElements`. Supply `getFrame`, size callbacks, `savePos`, `loadPos`, `clearPos`, and `applyPos`, following the native mover contract. The owning folder is `EllesmereUIQoL`.

Register lightweight metadata through the existing initialization path; do not create the visible frame until first enable or explicit preview. Disabled navigation should not contribute an active visible mover. Use the Unlock Mode listener to suspend live navigation, show synthetic guidance while editing an enabled element, and reacquire current tracking on exit.

Let Unlock Mode own save/discard, anchors, size matching, and position restoration. In particular, do not save coordinates from an `OnHide` drag handler as the standalone display does: hiding during a native discard/combat transition must not commit a cancelled position. Follow `SetFramePlacer` ownership where native anchoring requires it; avoid competing `SetPoint` writers.

## Runtime behavior to preserve

The current prototype is useful as a behavioral specification, not a drop-in module:

- Observe active tracking using Blizzard's highest-priority tracking type; a retained quest ID or an inactive placed pin cannot override it. Never set or clear user waypoints or supertracking.
- Support tracked manual pins, active quest guidance, and validated Area POIs. Prefer current-map quest travel/intermediate destinations before final-objective fallback. Unknown or restricted travel data blocks fallback.
- Keep stable destination identity separate from the player's map, projection, route source, labels, and zone. Revalidate routine POI/path/zone changes without erasing unchanged identity or blanking a usable arrow.
- Immediately hide stale guidance on confirmed removal, real target replacement, invalid input, disable, combat, or loading. Recheck identity before publishing data assembled through several getters.
- Compute distance and bearing from the same validated coordinate space. Label distance as straight-line distance. Do not reuse native distance as if it necessarily refers to the selected point.
- Validate finite, nonsecret coordinates, map dimensions, facing, and common space before arithmetic. Cross-map task/event conversions require matching world IDs and a compatible player origin. Unsupported floors, instances, or travel contexts must not create guessed directions.
- Own every rendered frame and texture. Do not modify Blizzard navigation frames, tracking internals, or Quest Tracker selection behavior.

Keep extended cross-map task/event guidance behind validation work if it makes the first upstream change too large. It is acceptable to land a clearly limited current-map implementation first, then add verified coverage. Do not advertise the prototype's entire coverage as proven client behavior.

## Blocking design question: continuous movement and turning

The current [contribution guide](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/.github/CONTRIBUTING.md) requires event-driven features and prohibits `OnUpdate` polling and wall-clock timers as logic gates. The prototype uses a 10 Hz active `OnUpdate`, slower refreshes without direction, and a 0.25-second acquisition delay. Porting that controller unchanged would violate the reviewed requirements.

Movement start/stop and target-change events alone do not establish that an arrow will update throughout movement, flying, or in-place turning. This review has not established a Blizzard event stream or native rendering primitive that supplies all required updates to an owned arrow. Existing upstream polling code is not evidence of permission for new polling.

Resolve this before implementing the port:

1. Inspect the supported client's Blizzard navigation implementation and generated API/event documentation for a suitable event-driven mechanism. Prove movement, turning, flight, and idle behavior in-client without modifying native navigation frames.
2. If that cannot provide continuous guidance, present the measured need for a narrowly scoped active update loop to the maintainer. Any exception must be explicitly accepted; an inert frame, a timer renamed as a refresh scheduler, or hooking Blizzard's per-frame update does not resolve the policy conflict.
3. If neither an acceptable mechanism nor an exception is available, revise the feature scope with the maintainer or keep the continuous arrow external. Do not call an event-only, intermittently stale bearing equivalent to continuous navigation.

Even with an approved loop, replace full repeated capture allocations with reusable state, cache event-owned target/route data, and update only necessary geometry while actively displaying a target. Stop continuous work when disabled, untracked, combat-suppressed, loading, or previewing. Do not treat an elapsed delay as proof that Blizzard's target/route state is ready.

## Lifecycle, profiles, and combat

Integrate initial `Apply` with the QoL initialization path, rather than adding a feature-owned login listener that runs for everyone. An inert driver may be created in the file's main chunk for correct profiler attribution; visible frames and meaningful runtime work remain lazy. Off means no navigation event registrations, hooks doing work, tickers, or `OnUpdate` handlers.

Add navigation reapplication to `REFRESH_ADDON_STEPS` in `EllesmereUI_Profiles.lua`. It must handle enable-to-disable profile switches, import, reset, and changes in position/style. Invalidate prior work before replacing configuration, clear preview, and reacquire fresh target state only if the new profile enables navigation.

Use QoL's `ns.CombatQueue.Defer(key, fn)` for combat-locked work. The upstream [agent rules](https://github.com/EllesmereGaming/EllesmereUI/blob/e95dfbcc7e38d2a08c3608011335ddb8bc0c9a2a/AGENTS.md) distinguish paired combat-state observation from using a raw regen event as a deferral mechanism. Combat entry should hide owned output immediately; resume must read current enablement and identity, not restore a captured model. Disable must invalidate pending callbacks so a queued resume cannot resurrect the display.

The contribution guide targets **Midnight 12.1+**, even though the inspected tree/TOCs still contain Forever and legacy branches. Treat the guide as the proposed submission target and clarify any broader target with the maintainer. Do not add a second client adapter or promise Forever support for this native feature based on the prototype's investigation. Every new Lua file needs the line-one `EUI_CLIENT_BLOCKED` guard required upstream.

## Arrival and relationship to `/way`

Arrival display changes are still future work in this repository. EUI already has separate `/way` announcement behavior using a fixed 30-yard pin-distance check, navigation-arrival and stopped-moving events, and combat-queued chat output. Do not silently replace or expand it when adding the arrow.

For a later arrow-arrival option, only classify proximity using validated distance to the selected destination. A native arrival event can refer to an intermediate portal or another tracked object. Reaching a travel step must not announce that the final quest objective is complete. Use a threshold plus hysteresis if a visual near-destination state is implemented; it must not clear tracking or advance a route. Keep arrow arrival visual-only initially to avoid duplicate command announcements.

## Implementation sequence

| Stage | Deliverable | Completion condition |
| --- | --- | --- |
| 1. Upstream design alignment | Agree on QoL ownership, page placement, support target, continuous-update mechanism, and scope | Resolve the update-policy conflict before committing to a port; the guide requests maintainer discussion for large features |
| 2. Native shell | Profile defaults, native page, lazy display, mover, reset/profile refresh wiring | Off by default; opening settings/search does not activate navigation; mover save/discard and profile changes work |
| 3. Current-map navigation | Original native data/controller implementation for tracked pins and exposed quest travel/objective positions | Live movement/turning works under the agreed update model; tracking setters are never called; old targets cannot reappear |
| 4. POI and conversion coverage | Area POIs and validated task/event cross-map conversions, if included | Per-scenario client evidence, correct common-space checks, safe unavailable behavior, no regression in travel priority |
| 5. Optional arrival behavior | Configurable visual threshold/state | Correct distinction between an intermediate step and destination; no automatic clearing or duplicate chat |
| 6. Release validation | Tests, screenshots, profiling, localization, documentation | Honest client coverage and all upstream checks pass |

Keep each change reviewable. Do not refactor unrelated `/way`, Quest Tracker, profile, or skin systems to make room for navigation. No upstream PR or maintainer communication is performed by this planning task.

## Validation and upstream acceptance

Automated checks should exercise real navigation logic with controlled APIs: active-type precedence, travel-before-objective ordering, secret/nil/error inputs, map/world mismatch, stable identity during event bursts, rapid replacement/removal, disable/profile-switch during pending work, and no polling or registrations while off. Test profile-slice reset without altering other QoL settings, sync exclusions, export/import ownership, and preview/search lifecycle.

The prototype docs refer to earlier local tests, but this checkout excludes `tests/` and `tools/` through `.gitignore`. Do not rely on those unavailable files as upstream evidence. Recreate and commit focused tests under EUI's existing `.tools/tests/` convention. Run its Lua 5.1 guardrails for changed Lua; update locale keys with `.tools/extract-locale-keys.sh` when adding localized strings. Do not claim that guardrails alone verify taint safety.

Client validation must cover:

- Fresh install and upgrade remain off; enabling only the arrow works without `/way` or Quest Tracker. Test all four arrow/command enabled combinations and check for duplicate displays with the standalone addon.
- Cardinal directions, rectangular maps, turning without moving, camera-only rotation, walking, mounted flight, and same-target POI/path/zone notification bursts.
- Quest/pin/POI switching, clearing tracking, portal before/after loading, remote or missing steps, instances/floors/vehicles, and unusable position/facing/conversion data.
- Combat/loading during navigation and preview, disable while suppressed, then resume with current identity; compare taint/protected-action reports with a feature-disabled baseline.
- Native Unlock Mode save/discard/reset/anchor behavior, options close/cache restore, font/accent changes, UI scale, login/reload, profile switch, reset, import/export, and automatic sync preserving layout.
- Profiler evidence for disabled, enabled idle with no target, active stationary, active movement/turning, and event bursts. Record actual API-call/update cost rather than deriving performance claims from nominal frequency.

Record client/build, EUI revision, scenario, expected/actual output, and pass/fail/blocked. Capture screenshots for visual review as requested by the contribution guide. A source review cannot establish any of these client outcomes.

## Decisions still needed

The recommended home and wiring are concrete. Before implementation, settle the continuous-update mechanism, whether a dedicated Navigation tab fits the maintainer's page budget, the first release's cross-map scope, and whether arrival controls belong in that first release. Confirm contribution/asset rights under EUI's custom license and contribution terms. These are design/release decisions, not features already delivered by this document.
