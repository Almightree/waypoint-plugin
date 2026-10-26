# Data observation prototype

This is a diagnostic addon, not the navigation arrow or finished EUI plugin. It uses read-only getters, owns its event frame, and never sets tracking state, hooks game/EUI functions, or accesses Blizzard navigation frames. EUI settings and skinning integration come later.

## Documentation authority

- EUI integration: [Plugin API](https://github.com/EllesmereGaming/EllesmereUI/blob/main/PLUGINS_API.md) and [Skinning API](https://github.com/EllesmereGaming/EllesmereUI/blob/main/SKINNING_API.md) on **main**. Inspected revision: ff95b06f9260db18447f626b0411a3508291da3a.
- WoW: Blizzard-authored, client-shipped generated API documentation and UI source. [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) is a community mirror, not an official Blizzard-hosted repository.
- Inspected Retail live revision: 15881d522c44cd106d3d8660106ec9f9d2f44167. [SuperTrack](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_APIDocumentationGenerated/SuperTrackManagerDocumentation.lua), [Navigation](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_APIDocumentationGenerated/InGameNavigationDocumentation.lua), [Map](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua), [Blizzard navigation implementation](https://github.com/Gethe/wow-ui-source/blob/15881d522c44cd106d3d8660106ec9f9d2f44167/Interface/AddOns/Blizzard_QuestNavigation/SuperTrackedFrame.lua).
- Match documentation to the tested client/build. WoW Forever must be verified against its own shipped APIs; Retail source does not prove compatibility.
- Battle.net web APIs are outside this addon's in-game navigation scope.

## Install

Copy the repository's **WaypointProbe** folder to your game's Interface/AddOns folder, then restart/reload the client. The folder must contain WaypointProbe.toc and WaypointProbe.lua directly.

The TOC lists 120100, 120105, and 16001 from EUI main's interface list as candidate development targets only. These are not a tested support matrix. Confirm the actual client build and addon loader status before testing.

No EUI dependency is needed for this isolated diagnostic. This does not change the intended EUI integration of the final plugin.

## Commands

- /wpprobe sample: save one out-of-combat snapshot.
- /wpprobe dump: print selected fields from the latest snapshot.
- /wpprobe start: capture relevant events and poll every two seconds, retaining only the latest 40 snapshots.
- /wpprobe stop: unregister events and stop polling.
- /wpprobe clear: clear recorded snapshots.

Recording starts disabled, does not resume after reload, and skips samples and chat output during combat. Run stop before entering combat if you need it stopped there; slash commands are intentionally ignored in combat. This prototype therefore does **not** validate combat-time API behavior.

After stop, /reload or log out normally to flush WaypointProbeDB to WTF/Account/<account>/SavedVariables/WaypointProbe.lua. The data may include quest/destination names and map coordinates; review it before sharing.

## Test sequence

1. Clear samples. With no tracked destination, take a sample and dump it.
2. Place a map pin without tracking it; sample again. A placed pin is not proof that it is the active destination.
3. Explicitly track that pin, start recording, move and turn, then stop. Dump the latest sample.
4. Select a quest for navigation. Repeat while approaching an objective; observe nextWaypoint (which can describe an entrance/intermediate target).
5. Change/remove the target; repeat across zone transitions, loading screens, inside an instance, and with native navigation disabled.
6. Save separate batches per scenario before the 40-sample rolling buffer overwrites earlier results.
7. Record client version/build, EUI version, scenario, available/missing getters, returned states, and any errors. Compare the active target type with quest IDs and placed pins: those fields may describe inactive data.
8. Repeat on each intended client. Combat-time behavior and taint testing remain a later phase.

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

The current prototype captures C_Navigation.GetNextWaypointForMap but does not yet collect C_QuestLog.GetNextWaypointText or render an arrow. Record native instruction text manually for now; direction/arrival/visual checks remain pending until rendering exists. Do not mark them passed from observation logs alone.

Develop against one shared API implementation on Retail first. Ellesmere reports Retail and Forever APIs are the same; treat that as the working assumption and verify behavior on Forever when available. Forever in-game testing is **blocked until after November 4, 2026**, because its beta has ended.

## What is measured

Active tracking kind/name, quest and user-waypoint tracking flags, quest ID, native navigation distance/state/screen validity, current map, next waypoint for that map, player map position, map world size, player facing, and separately the placed map pin.

Scalar values are sanitized before saving; restricted values become a marker, unavailable functions are marked missing, and getter failures are marked error. No direction is calculated yet: validate coordinate units, map relationship, navigation state, and facing conventions before deriving an angle. GetBuildInfo's first three return values are stored (version, build, date).

## Validation so far

Lua syntax and mocked execution passed for snapshots, missing/error/restricted values, combat suppression, the 40-sample bound, polling start/stop, dumping, and clearing. These checks ran using Lua 5.4; WoW runtime and in-game validation are still required. No compatibility or taint-free claim is made.
