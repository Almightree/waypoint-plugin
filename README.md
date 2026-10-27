# Waypoint Plugin for EllesmereUI

An optional WoW navigation addon designed to integrate with EllesmereUI's public plugin API.

**Status: first visible navigation-arrow prototype. Automated checks pass; in-game arrow validation is pending.**

Copy **AlmightreeWaypoint** into `Interface/AddOns` to install the arrow. Keep **WaypointProbe** installed separately if you want diagnostic captures. EllesmereUI is optional: its public APIs supply settings and appearance when available, with standalone styling and slash controls otherwise.

Use `/atway preview` to see the display, `/atway unlock` to drag it, `/atway lock` to lock it, then `/atway preview` again to return to navigation. `/atway options` opens the EUI plugin page; `/atway disable` stops navigation updates.

See [installation and exact in-game tests](docs/navigation-prototype.md) for commands, source selection, limitations, and automated versus pending validation. The existing [observation probe](docs/data-observation.md) remains available.

## The idea

Choose a map pin or quest destination through the normal game controls. The plugin observes the active navigation target and presents a movable arrow, destination label, and available distance in a display styled to fit EUI.

The plugin complements EUI's existing waypoint commands; it does not require that feature to be enabled.

## Prototype behavior

- Follow the active tracking type: tracked manual pins, quest travel waypoints, then verified current-map quest POIs when no travel step is exposed; tracked Area POIs are also handled.
- Addon-owned arrow, destination, straight-line distance, and available travel instruction. World quests and event POIs can use validated task-zone/event-map coordinates after verified world-space conversion; hide direction without a validated common space and keep useful text.
- Independent saved position, scale, opacity, enable/disable, preview, and unlock/drag/lock/reset controls.
- Public EUI plugin settings and resolved `eui`/`modern` skinning, with fallback styling. Fonts and accent follow EUI rather than a separate theme selector.
- No arrival detection, tracking mutation, or pathfinding. Font/color overrides and arrival settings remain future work.

## Design boundaries

Observe navigation state without changing waypoint or super-tracking state. Render only in addon-owned frames and avoid modifying Blizzard navigation frames or EUI internals. This reduces taint risk; in-game validation is still required.

Follow Blizzard's active quest navigation target rather than treating every highlighted quest as a selected destination. Cross-zone routing, instances, intermediate targets, restricted values, and client API differences need feasibility testing.

Investigate WoW Forever and current Retail separately. Neither compatibility nor taint-free behavior is claimed before testing.

## Roadmap

1. Verify tracking APIs, client compatibility, and public EUI integration.
2. Validate the implemented pin/quest arrow, settings, persistence, and public EUI integration in game.
3. Extend validated navigation coverage and objective changes.
4. Validate in game, document limitations, and prepare a release.

See [planning issue #1](https://github.com/Almightree/waypoint-plugin/issues/1) for the full scope, architecture, and acceptance checklist.

World-space markers, guide integrations, ETA, route queues, and upstream bundling are future possibilities.

## References

- [EllesmereUI plugin API](https://github.com/EllesmereGaming/EllesmereUI/blob/main/PLUGINS_API.md)
- [EllesmereUI waypoint feature](https://github.com/EllesmereGaming/EllesmereUI/blob/main/EllesmereUIQoL/EllesmereUIQoL_Waypoint.lua)
- [Waypoint-UI](https://github.com/Adaptvx/Waypoint-UI), an experience reference.

Original implementation and assets are intended. Verify permissions and license compatibility before reusing external code or assets. See [LICENSE](LICENSE) for this repository's license.
