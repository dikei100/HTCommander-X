import 'package:flutter/material.dart';

import '../platform/bluetooth_service.dart';

/// Dialog for scanning, listing, and selecting Bluetooth radios.
///
/// Calls [scanForDevices] on open and on refresh. Shows a loading indicator
/// while scanning. Falls back to manual MAC entry when no devices are found
/// or the user taps "MANUAL ENTRY".
///
/// Returns a map with 'action' ('connect'/'disconnect') and 'mac'/'name' keys,
/// or null on cancel.
class RadioConnectionDialog extends StatefulWidget {
  /// Callback that scans for compatible Bluetooth devices.
  final Future<List<CompatibleDevice>> Function() scanForDevices;

  /// MAC address of the last connected radio (pre-selects in list).
  final String lastMac;

  const RadioConnectionDialog({
    super.key,
    required this.scanForDevices,
    this.lastMac = '',
  });

  @override
  State<RadioConnectionDialog> createState() => _RadioConnectionDialogState();
}

class _RadioConnectionDialogState extends State<RadioConnectionDialog> {
  List<Map<String, String>> _devices = [];
  int _selectedIndex = -1;
  bool _scanning = false;
  bool _showManualEntry = false;
  late TextEditingController _macController;

  @override
  void initState() {
    super.initState();
    _macController = TextEditingController(text: _formatMac(widget.lastMac));
    _scan();
  }

  @override
  void dispose() {
    _macController.dispose();
    super.dispose();
  }

  /// Formats a raw MAC (e.g. "38D20001E4E2") to colon-separated form.
  String _formatMac(String raw) {
    final clean = raw.replaceAll(RegExp(r'[:\-]'), '').toUpperCase();
    if (clean.length != 12) return raw;
    return List.generate(6, (i) => clean.substring(i * 2, i * 2 + 2)).join(':');
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _selectedIndex = -1;
    });

    try {
      final results = await widget.scanForDevices();
      if (!mounted) return;

      final lastClean =
          widget.lastMac.replaceAll(RegExp(r'[:\-]'), '').toUpperCase();

      final devices = results.map((d) {
        final macFormatted = _formatMac(d.mac);
        return <String, String>{
          'name': d.name,
          'mac': macFormatted,
          'state': 'Available',
        };
      }).toList();

      int preselect = -1;
      if (lastClean.length == 12) {
        preselect = devices.indexWhere((d) =>
            d['mac']!.replaceAll(':', '').toUpperCase() == lastClean);
      }

      setState(() {
        _devices = devices;
        _selectedIndex = preselect;
        _scanning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _devices = [];
        _scanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with title and scan button
              Row(
                children: [
                  Text('RADIO CONNECTION',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: colors.onSurfaceVariant)),
                  const Spacer(),
                  if (!_showManualEntry)
                    SizedBox(
                      height: 24,
                      child: TextButton.icon(
                        onPressed: _scanning ? null : _scan,
                        icon: _scanning
                            ? SizedBox(
                                width: 10,
                                height: 10,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: colors.primary))
                            : Icon(Icons.refresh,
                                size: 12, color: colors.primary),
                        label: Text(
                          _scanning ? 'SCANNING...' : 'SCAN',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: _scanning
                                  ? colors.onSurfaceVariant
                                  : colors.primary),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              if (_showManualEntry)
                _buildManualEntry(colors)
              else
                _buildDeviceList(colors),

              const SizedBox(height: 16),

              // Actions row
              Row(
                children: [
                  // Manual entry / back toggle
                  TextButton(
                    onPressed: () =>
                        setState(() => _showManualEntry = !_showManualEntry),
                    child: Text(
                      _showManualEntry ? 'DEVICE LIST' : 'MANUAL ENTRY',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: colors.onSurfaceVariant),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('CANCEL',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: colors.onSurfaceVariant)),
                  ),
                  const SizedBox(width: 8),
                  if (_showManualEntry)
                    FilledButton(
                      onPressed: _macController.text.trim().isNotEmpty
                          ? () => Navigator.pop(context, <String, String>{
                                'action': 'connect',
                                'mac': _macController.text.trim(),
                                'name': '',
                              })
                          : null,
                      child: const Text('CONNECT',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1)),
                    )
                  else ...[
                    FilledButton(
                      onPressed: _selectedIndex >= 0
                          ? () => _close('connect')
                          : null,
                      child: const Text('CONNECT',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceList(ColorScheme colors) {
    if (_scanning && _devices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bluetooth_searching,
                  size: 32, color: colors.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('No compatible radios found',
                  style: TextStyle(
                      fontSize: 11, color: colors.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text('Make sure your radio is paired in system Bluetooth settings',
                  style: TextStyle(fontSize: 9, color: colors.outline)),
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _devices.length,
        itemBuilder: (context, index) {
          final device = _devices[index];
          final name = device['name'] ?? 'Unknown';
          final mac = device['mac'] ?? '';
          final isSelected = _selectedIndex == index;

          return InkWell(
            onTap: () => setState(() => _selectedIndex = index),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.15)
                    : null,
                border: Border(
                  bottom:
                      BorderSide(color: colors.outlineVariant, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.bluetooth,
                      size: 16, color: colors.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurface)),
                        Text(mac,
                            style: TextStyle(
                                fontSize: 9,
                                fontFamily: 'monospace',
                                color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('Available',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildManualEntry(ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BLUETOOTH MAC ADDRESS',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _macController,
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: colors.onSurface,
          ),
          decoration: InputDecoration(
            hintText: 'XX:XX:XX:XX:XX:XX',
            hintStyle: TextStyle(color: colors.outline),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Text(
          'Compatible: UV-Pro, UV-50Pro, GA-5WB, VR-N75, VR-N76, VR-N7500, VR-N7600, RT-660, DB50-B',
          style: TextStyle(fontSize: 10, color: colors.outline),
        ),
      ],
    );
  }

  void _close(String action) {
    final device = _devices[_selectedIndex];
    Navigator.pop(context, <String, String>{
      'action': action,
      'mac': device['mac'] ?? '',
      'name': device['name'] ?? '',
    });
  }
}
