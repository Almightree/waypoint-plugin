# Data observation prototype

This is a diagnostic addon, not the navigation arrow or finished EUI plugin. It uses read-only getters, owns its event frame, and never sets tracking state, hooks game/EUI functions, or accesses Blizzard navigation frames. This probe does not integrate EUI settings or skinning.

The separate **AlmightreeWaypoint** visible prototype is now available; see its [installation and in-game validation procedure](navigation-prototype.md). Keep using this probe independently for diagnostic captures.

## Documentation authority

- EUI integration: [Plugin API](https://github.com/EllesmereGaming/EllesmereUI/blob/main/PLUGINS_API.md) and [Skinning API](https://github.com/EllesmereGaming/EllesmereUI/blob/main/SKINNING_API.md) on **main**. Inspected revision: ff95b06f9260db18447f626b0411a3508291da3a.
- WoW: Blizzard-authored, client-shipped generated API documentation and UI source. [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) is a community mirror, not an official Blizzard-hosted repository.
- Inspected Retail live revision: 15881d522c44cd106d3d8660106ec9f9d2f44167. [SuperTrack](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_APIDocumentationGenerated/SuperTrackManagerDocumentation.lua), [Navigation](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_APIDocumentationGenerated/InGameNavigationDocumentation.lua), [Map](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua), [Blizzard navigation implementation](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_QuestNavigation/SuperTrackedFrame.lua).
- Match documentation to the tested client/build. WoW Forever must be verified against its own shipped APIs; Retail source does not prove compatibility.
- Quest waypoint signatures verified in Blizzard's generated [QuestLog documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua): `GetNextWaypoint(questID)` returns `(mapID, x, y)`, `GetNextWaypointForMap(questID, uiMapID)` returns `(x, y)`, and `GetNextWaypointText(questID)` returns text. All three may return nothing. This is a separate live-source check from the pinned revision above; verify against the tested client.
- Objective/POI sources: generated [QuestLog](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua), [QuestTaskInfo](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestTaskInfoDocumentation.lua), [QuestPOIMapInfo structure](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestInfoSharedDocumentation.lua), [SuperTrack getters](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SuperTrackManagerDocumentation.lua), [tracking enums](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SuperTrackManagerSharedDocumentation.lua), and [AreaPoiInfo](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AreaPoiInfoDocumentation.lua). Blizzard's [quest map provider](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedMapDataProviders/QuestDataProvider.lua) uses quest POI `x/y` to place pins on the queried map. These are live-source references, separate from the earlier pinned revision.
- Battle.net web APIs are outside this addon's in-game navigation scope.

- Supplementary reference/tooling: [wowlua](https://wowlua.dev/) provides typed Lua tooling, an API reference, and an emulated WoW test environment. Its site currently describes the browsable API reference as camelot-focused, with Retail and Classic Era coming; check actual per-flavor coverage before relying on it. API descriptions may include project-authored text, and emulator behavior can be implemented, recorded, guessed, or unimplemented. Use it to aid development, not as a replacement for Blizzard's client-shipped documentation or in-game validation. Adding this reference does not adopt its compiler/framework or change the plain-Lua prototype.

## Install

Copy the repository's **WaypointProbe** folder to your game's Interface/AddOns folder, then restart/reload the client. The folder must contain WaypointProbe.toc and WaypointProbe.lua directly.

The TOC lists 120100, 120105, and 16001 from EUI main's interface list as candidate development targets only. These are not a tested support matrix. Confirm the actual client build and addon loader status before testing.

No EUI dependency is needed for this isolated diagnostic. This does not change the intended EUI integration of the final plugin.

## Commands

- /wpprobe sample: save one out-of-combat snapshot.
- /wpprobe dump: print selected fields from the latest snapshot.
- /wpprobe start: capture relevant events and poll every two seconds, retaining only the latest 40 snapshots. Tracking/path changes also schedule a snapshot after 0.25 seconds without another such event; its reason ends in `:settled`. Event bursts reset this delay and coalesce into one follow-up.
- /wpprobe stop: unregister events, stop polling, and cancel any pending settled snapshot. Restarting also cancels the previous session's pending capture.
- /wpprobe clear: clear recorded snapshots.

Recording starts disabled, does not resume after reload, and skips samples and chat output during combat. Run stop before entering combat if you need it stopped there; slash commands are intentionally ignored in combat. This prototype therefore does **not** validate combat-time API behavior.

After stop, /reload or log out normally to flush WaypointProbeDB to WTF/Account/<account>/SavedVariables/WaypointProbe.lua. The data may include quest/destination names and map coordinates; review it before sharing.

## Arrow visibility and movement diagnostics

Update **both** addon folders to capture the visible prototype's state alongside navigation data. The probe has an optional dependency on AlmightreeWaypoint for load order; it still works by itself. Every snapshot, including immediate and settled captures, now saves these fields, and `/wpprobe dump` prints them:

| Field | Values |
| --- | --- |
| `arrowState` | `(arrowVisible, visibilityReason, panelVisible)`; visibility is read from the actual addon-owned texture/frame with `IsVisible()`, including parent visibility |
| `arrowTarget` | `(renderedTargetKey, selectedSource)`; sources include `pin`, `travel`, `objective`, `poi`, or synthetic `preview` |
| `arrowUpdatedAt` | `GetTime()` at the last render/clear; compare with the sample's `time` to identify an older display state |
| `flying` | `IsFlying("player")` |
| `mounted` | `IsMounted()` |

The optional read-only `AlmightreeWaypointDiagnostics` bridge reports renderer state; the probe does not inspect frames, rerun the arrow's selection logic, or infer visibility from raw navigation data. A visible arrow reports `visible`. A hidden arrow reports the exact code path that hid it, while `panelVisible=true` can distinguish text-only guidance from a fully hidden display. `IsVisible()` describes UI visibility, not pixel occlusion or another window covering the arrow. A parent becoming hidden without another render can change actual visibility while leaving `arrowUpdatedAt` unchanged.

Representative reasons:

| Reason | Meaning |
| --- | --- |
| `no_tracking` | Blizzard reported no active tracking |
| `tracking_missing`, `tracking_error`, `tracking_restricted`, `quest_id_invalid`, `unsupported_tracking_type` | Identity could not be established; not the same as confirmed tracking removal |
| `disabled`, `combat_suppressed`, `loading_screen` | A display/lifecycle rule suppressed the arrow |
| `refresh_pending`, `target_changed_pending` | Previous data was invalidated and a fresh capture is pending |
| `player_map_nil`, `player_map_restricted`, `map_mismatch` | No valid shared coordinate map |
| `quest_poi_no_match`, `quest_poi_map_mismatch`, `quest_poi_coordinates_invalid` | The objective lookup did not supply an appropriate coordinate |
| `player_position_missing`, `player_position_restricted`, `map_dimensions_invalid`, `facing_invalid` | A required direction input failed validation |
| `travel_step_other_map`, `travel_instruction_without_coordinates` | A known travel step blocks direct objective guidance |
| `quest_travel_missing`, `native_travel_restricted` | Travel API unavailable/unsafe; objective fallback is deliberately blocked |
| `coincident_coordinates` | Distance can be zero, but no bearing is defined; this is not arrival detection |
| `capture_error`, `identity_error` | Protected evaluation failed; error text is not persisted |
| `texture_or_parent_hidden` | A valid bearing was rendered, but the texture or its parent is now hidden |

Additional input-specific reasons follow the same naming scheme. Getter failures preserve `missing`, `error`, and `restricted`; successful getters with unusable values report `nil`, `false`, or `invalid` where applicable. Only the first failing validation/selection rule is reported, not a guess about the underlying game condition. Flying/mounted flags are observations and do not introduce any new visibility rule.

Without the arrow addon, before its initialization, or with an older version lacking the bridge, arrow diagnostic fields have `status=missing`, not `arrowVisible=false`. Getter exceptions and restricted values use the same markers as other probe fields. Probe combat suppression and its 40-sample bound are unchanged: no samples are taken during combat, even though the renderer can record a combat-suppression reason internally.

To investigate disappearing guidance, start a short capture, acquire a working target, mount/dismount, take off/land, then switch and clear targets. Take a manual snapshot/dump while the problem is visible and compare `arrowState`, `arrowTarget`, `arrowUpdatedAt`, tracking, coordinates, flying, and mounted. Also sample with `/atway disable` and re-enable; expect `disabled`, followed by pending/visible or the actual input failure. Immediate event handlers can run in different orders across addons; the arrow fields are its live state at sampling time, not an atomic post-event snapshot. Compare the settled sample and render timestamp before attributing a mismatch to stale tracking. Save the batch before the rolling buffer overwrites it.

Signatures were checked against Blizzard's generated [Unit documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua) (`IsFlying` accepts an optional unit and returns boolean) and [PlayerScript documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/PlayerScriptDocumentation.lua) (`IsMounted` returns boolean). In-game behavior of the added diagnostics remains pending.

## Test sequence

1. Clear samples. With no tracked destination, take a sample and dump it.
2. Place a map pin without tracking it; sample again. A placed pin is not proof that it is the active destination.
3. Explicitly track that pin, start recording, move and turn, then stop. Dump the latest sample.
4. Select a quest for navigation. Repeat while approaching an objective; compare `nextWaypoint` (native navigation), `questNextWaypoint` (map ID, x, y), `questNextWaypointForMap` (x, y on the current map), and `questNextWaypointText`. These can describe an entrance/intermediate target. Compare each immediate tracking/path snapshot with its `:settled` follow-up.
5. Switch quest-to-quest, quest-to-pin, pin-to-quest, and clear tracking, including rapid changes within 0.25 seconds. Check that follow-ups describe the current target and quest fields disappear when no quest is actively tracked, even if a quest ID remains. Repeat across zone transitions, loading screens, inside an instance, and with native navigation disabled. Stop immediately after a change, wait beyond 0.25 seconds, and confirm no pending snapshot appears; restart and confirm the old pending capture stays canceled.
6. Save separate batches per scenario before the 40-sample rolling buffer overwrites earlier results.
7. Record client version/build, EUI version, scenario, available/missing getters, returned states, and any errors. Compare the active target type with quest IDs and placed pins: those fields may describe inactive data.
8. Repeat on each intended client. Combat-time behavior and taint testing remain a later phase.

### Objective/POI coordinate checks

The waypoint APIs describe intermediate travel steps and may return nil even when a quest objective or POI has coordinates. Keep those observations separate:

| Saved/dumped field | Getter and stored values | Query context |
| --- | --- | --- |
| `questPOIPosition` | `C_QuestLog.GetQuestsOnMap(uiMapID)`: first entry matching the active quest ID, storing `(mapID, x, y)` | Current map in `map`; returned entry's `mapID` is retained separately from query context |
| `taskQuestPOIPosition` | `C_TaskQuest.GetQuestsOnMap(uiMapID)`: same filtering and values | Current map in `map` |
| `taskQuestLocation` | `C_TaskQuest.GetQuestLocation(questID, uiMapID)`: `(x, y)` | Current map in `map` |
| `taskQuestZone` | `C_TaskQuest.GetQuestZoneID(questID)`: zone UI map ID | Active quest; may return nothing for ordinary quests |
| `taskQuestZoneLocation` | `C_TaskQuest.GetQuestLocation(questID, zoneID)`: `(x, y)` | Usable positive `taskQuestZone` |
| `questPOIPositionInTaskZone`, `taskQuestPOIPositionInTaskZone` | Respective `GetQuestsOnMap(zoneID)` getter: matching `(mapID, x, y)` | `taskQuestZone`, allowing comparison with a destination zone while elsewhere |
| `mapPinTracked`, `trackedMapPin` | `IsSuperTrackingMapPin()` and `GetSuperTrackedMapPin()`: flag and `(pinType, typeID)` | Recorded independently of the quest flag |
| `areaPOIPosition` | `C_AreaPoiInfo.GetAreaPOIInfo(uiMapID, areaPoiID)`: sanitized `position.x/y` | Current `map`, only with an actively tracked `AreaPOI` subtype and usable ID |

All getters above are read-only. Quest position lookups require the same active-quest flag and usable quest ID as the portal getters. Area POI lookup works without a quest ID, uses the client's `Enum.SuperTrackingMapPinType.AreaPOI`, and does not guess that another map-pin subtype is an Area POI. Missing enums or unusable inputs skip that lookup. `linkedUiMapID` is not used as the coordinate map: a linked destination map is not proof that the returned position belongs to it.

Only the first matching quest POI is retained; this is a representative map pin, not an enumeration of every objective or a route. The probe scans at most 512 entries per result, stores no unrelated quests, and reports `<scan-limit>` if an unmatched result exceeds that bound. No match/nothing returned is `ok` with `<nil>` values; restricted containers, IDs preventing a match, vectors, and coordinate components retain restricted markers. Missing functions and getter/projection failures retain `missing` and `error` statuses. No API objects or vectors are saved.

Test a normal quest and a world quest on the current map, then a task/world quest in another zone. Compare POI/location fields against the displayed objective while also checking the separate portal waypoint fields. A missing task-zone ID leaves only current-map queries; ordinary cross-zone quests may therefore still have no objective coordinates. The probe does not change the world map, request quest data, or infer a destination map from a waypoint. Test an Area POI with `questTracked=false`, replace it with another POI, switch to a quest/manual pin, and clear tracking. Verify immediate and settled samples change IDs/coordinates or omit inapplicable fields, with no retained position from the previous target. `QUEST_POI_UPDATE` and `AREA_POIS_UPDATED` also trigger immediate snapshots while recording.

For POIs outside the current map, a current-map query may return nil or a projected position; it does not establish coordinates on the destination map. Quest offers, taxi nodes, dig sites, and housing pins retain their identity but are not resolved through AreaPoiInfo. Record these limits rather than substituting an unrelated coordinate source.

## Retail world-quest and POI test matrix

Run each destination twice: **A: explicitly track the world quest/quest POI**, then **B: place and explicitly track a manual pin at the same destination**. Keep the runs separate; identical destinations do not imply identical routing data.

| Scenario | Observation prototype checks | Later arrow acceptance |
| --- | --- | --- |
| Current-zone world quest | Active target kind, available distance, next waypoint and position while moving/turning and approaching | Correct direction/distance and arrival appearance |
| Adjacent-zone world quest | Capture before the border, at crossing, and after transition; note map IDs and waypoint changes | Guidance updates across the boundary without stale direction |
| Destination requiring a portal, boat, or other transport | Record whether Blizzard supplies an intermediate waypoint/instruction; capture before travel and after loading/arrival | Follow the supplied next step; hide gracefully if routing data is unavailable |
| Cave entrance or different map floor | Compare entrance/intermediate waypoint with final objective and current floor/map | Guide toward the appropriate supplied waypoint; avoid misleading floor/entrance directions |
| Switch or clear tracked target | Switch quest-to-quest, quest-to-pin, pin-to-quest, and clear tracking; inspect the next sample | Display changes or hides promptly with no stale labels/direction |
| Target with no usable routing data | Note missing/nil/error/restricted getters and invalid/disabled native navigation | Hide directional guidance rather than infer a route |

For each run record:
- Scenario ID, A/B target mode, client version/build, addon revision, EUI version, quest ID (where applicable), destination coordinates/map, and starting map.
- What Blizzard's own navigation displays, the observed next waypoint, distance/state, and any intermediate instruction.
- Samples before/after each zone boundary, portal/transport leg, floor change, target replacement/removal, and arrival.
- Actual versus expected behavior, errors, and result: **not run**, **pass**, **fail**, or **blocked**. Missing native routing is a documented coverage limit, not automatically a plugin defect.
- Save named copies of the SavedVariables batch per scenario/run after stopping and reloading; preserve earlier files before starting a new batch. The rolling buffer holds 40 samples (about 80 seconds at the polling rate, less with events), so use short captures around transitions.

The probe captures native and quest waypoint getters, including instruction text, but does not render an arrow. Compare captured text with native instructions and run the separate visible prototype's in-game validation procedure for direction and appearance. Those checks remain pending; do not mark them passed from observation logs alone. The visible prototype does not implement arrival detection.

Develop against one shared API implementation on Retail first. Ellesmere reports Retail and Forever APIs are the same; treat that as the working assumption and verify behavior on Forever when available. Forever in-game testing is **blocked until after November 4, 2026**, because its beta has ended.

## What is measured

Active tracking kind/name, quest and user-waypoint tracking flags, quest ID, native navigation distance/state/screen validity, current map, next waypoint for that map, player map position, map world size, player facing, and separately the placed map pin.

`questNextWaypoint`, `questNextWaypointForMap`, and `questNextWaypointText` are also included in saved samples and `/wpprobe dump`. They are read only when `IsSuperTrackingQuest()` is true and the quest ID is a nonrestricted positive number. The map-specific getter additionally requires a usable current map ID. Inapplicable fields are omitted, while eligible missing APIs retain `missing` status. Each settled snapshot rereads tracking and map state rather than retaining event-time IDs. Combat-suppressed snapshots are discarded, including settled captures; they are not retried after combat.

Scalar values are sanitized before saving; restricted values become a marker, unavailable functions are marked missing, and getter failures are marked error. No direction is calculated yet: validate coordinate units, map relationship, navigation state, and facing conventions before deriving an angle. GetBuildInfo's first three return values are stored (version, build, date).

## Validation so far

The supplied `probe_results/WaypointProbe.lua` batch contains 40 snapshots on client 12.1.5/build 70575. It includes five settled captures and tracking type 6 (`MapPin` in the generated enum), with no active quest IDs, no placed user pins, and nil native waypoint coordinates throughout. Immediate/settled pairs show navigation distance/state updating after the tracking event. This demonstrates why quest portal getters alone cannot resolve that batch's coordinates. The older batch lacks map-pin subtype/ID and the new POI fields, so it cannot identify which POI getter would have succeeded. It does not validate the new coordinate getters, stop cancellation, combat behavior, or rendering.

Lua syntax and mocked execution passed for snapshots, missing/error/restricted values, combat suppression, the 40-sample bound, polling start/stop, dumping, and clearing. These checks ran using Lua 5.4; WoW runtime and in-game validation are still required. No compatibility or taint-free claim is made.

Run the regression harness from the repository root with `lua tests/WaypointProbe.test.lua`. It checks quest signatures/return values and dump output, target switching/removal with stale IDs, invalid/restricted quest and map inputs, absent quest APIs, getter errors and restricted/nil returns, immediate/settled timing and burst coalescing, stop/restart cancellation, combat suppression, polling, and the bounded buffer. The added harness passed using Fengari's Lua 5.3 runtime (`fengari tests/WaypointProbe.test.lua`); mocked results do not establish client compatibility.

The extended harness also passed under Fengari for quest/task POI filtering and map contexts, task destination-zone lookup, coordinates independent of intermediate waypoints, Area POI resolution without a quest, POI replacement/removal, unsupported map-pin types and missing enums, unavailable APIs, restricted containers/fields, nil/no-match results, getter failures, bounded scans, and dump output. In-game validation of the newly added coordinate getters remains pending.
