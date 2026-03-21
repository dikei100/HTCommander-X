---
name: radio-status
description: Check the status of connected radios using the HTCommander MCP server. Reports connection state, battery, signal, GPS, and channel info.
---

# Radio Status Check

Use the HTCommander MCP tools to check the current status of connected radios and provide a human-readable summary.

## Steps

1. Call the `get_connected_radios` MCP tool to list all connected radios
2. For each connected radio, gather status using these MCP tools:
   - `get_radio_state` — connection state
   - `get_battery` — battery percentage
   - `get_radio_info` — device model and capabilities
   - `get_radio_settings` — current VFO frequencies and settings
   - `get_gps_position` — GPS coordinates (if GPS is enabled)
3. Present a clear summary table with:
   - Device ID, model name, connection state
   - Battery percentage
   - Current VFO A/B frequencies (in MHz)
   - GPS status and coordinates (if available)
   - Audio streaming status

If no radios are connected, report that and suggest the user check Bluetooth pairing.

If the MCP server is not running, inform the user they need to enable it in Settings > Servers > "Enable MCP Server (AI Control)".
