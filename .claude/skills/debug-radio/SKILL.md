---
name: debug-radio
description: Debug HTCommander radio connection and application issues using MCP tools. Inspects logs, DataBroker state, and radio status.
---

# Debug Radio Issues

Use the HTCommander MCP debug tools to diagnose radio connection and application issues.

**Note:** Debug tools must be enabled in Settings > Servers > "Enable debug tools" checkbox.

## Steps

1. First check connectivity:
   - Call `get_connected_radios` to see if any radios are connected
   - For each radio, call `get_radio_state` to check connection state

2. Check application logs for errors:
   - Call `get_logs` with `count: 100` to get recent log entries
   - Look for error messages, connection failures, or Bluetooth issues
   - Pay attention to RFCOMM, GAIA, and Bluetooth-related messages

3. If a radio is connected but behaving unexpectedly:
   - Call `get_radio_info` to verify device capabilities
   - Call `get_radio_settings` to check current configuration
   - Call `get_databroker_state` with the radio's device ID to see all stored state

4. Check application-level state:
   - Call `get_databroker_state` with `device_id: 1` for app events
   - Call `get_databroker_state` with `device_id: 0` for settings

5. Present findings as:
   - **Status**: Overall health assessment
   - **Issues found**: List of problems detected in logs or state
   - **Recommendations**: Suggested actions to resolve issues

## Common issues to look for
- "RFCOMM" errors: Bluetooth connection problems
- "GAIA" errors: Radio protocol communication failures
- "SBC" or "Audio" errors: Audio pipeline issues
- Missing "ConnectedRadios" in device 1: No radios paired/connected
- "Timeout" or "Disconnected" states: Connection instability
