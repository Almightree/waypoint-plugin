# Waypoint Plugin for EllesmereUI

An optional WoW navigation addon designed to integrate with EllesmereUI's public plugin API.

**Status: concept and planning. No playable addon is implemented yet.**

## The idea

Choose a map pin or quest destination through the normal game controls. The plugin observes the active navigation target and presents a movable arrow, destination label, and available distance in a display styled to fit EUI.

The plugin complements EUI's existing waypoint commands; it does not require that feature to be enabled.

## Planned first release

- Player-selected tracked map pins, followed by active quest navigation targets.
- Customizable position, scale, opacity, font/color, and arrival behavior.
- Safe hiding when a target disappears or usable navigation data is unavailable.
- Settings inside EUI through its supported plugin API.
- Independent SavedVariables and positioning controls unless a public EUI positioning API is confirmed.

## Design boundaries

Observe navigation state without changing waypoint or super-tracking state. Render only in addon-owned frames and avoid modifying Blizzard navigation frames or EUI internals. This reduces taint risk; in-game validation is still required.

Follow Blizzard's active quest navigation target rather than treating every highlighted quest as a selected destination. Cross-zone routing, instances, intermediate targets, restricted values, and client API differences need feasibility testing.

Investigate WoW Forever and current Retail separately. Neither compatibility nor taint-free behavior is claimed before testing.

## Roadmap

1. Verify tracking APIs, client compatibility, and public EUI integration.
2. Build the map-pin arrow MVP with settings and persistence.
3. Add quest navigation and objective changes.
4. Validate in game, document limitations, and prepare a release.

See [planning issue #1](https://github.com/Almightree/waypoint-plugin/issues/1) for the full scope, architecture, and acceptance checklist.

World-space markers, guide integrations, ETA, route queues, and upstream bundling are future possibilities.

## References

- [EllesmereUI plugin API](https://github.com/EllesmereGaming/EllesmereUI/blob/main/PLUGINS_API.md)
- [EllesmereUI waypoint feature](https://github.com/EllesmereGaming/EllesmereUI/blob/main/EllesmereUIQoL/EllesmereUIQoL_Waypoint.lua)
- [Waypoint-UI](https://github.com/Adaptvx/Waypoint-UI), an experience reference.

Original implementation and assets are intended. Verify permissions and license compatibility before reusing external code or assets. See [LICENSE](LICENSE) for this repository's license.
