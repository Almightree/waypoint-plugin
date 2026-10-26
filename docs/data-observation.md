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

## What is measured

Active tracking kind/name, quest and user-waypoint tracking flags, quest ID, native navigation distance/state/screen validity, current map, next waypoint for that map, player map position, map world size, player facing, and separately the placed map pin.

Scalar values are sanitized before saving; restricted values become a marker, unavailable functions are marked missing, and getter failures are marked error. No direction is calculated yet: validate coordinate units, map relationship, navigation state, and facing conventions before deriving an angle. GetBuildInfo's first three return values are stored (version, build, date).

## Validation so far

Lua syntax and mocked execution passed for snapshots, missing/error/restricted values, combat suppression, the 40-sample bound, polling start/stop, dumping, and clearing. These checks ran using Lua 5.4; WoW runtime and in-game validation are still required. No compatibility or taint-free claim is made.
