import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../radio/ax25/ax25_packet.dart';
import '../widgets/glass_card.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isConnected = false;
  final List<String> _outputLines = [];
  List<int> _radioDeviceIds = [];
  int? _selectedRadioId;

  @override
  void initState() {
    super.initState();
    _broker.subscribe(
        DataBroker.allDevices, 'UniqueDataFrame', _onUniqueDataFrame);
    _broker.subscribe(DataBroker.allDevices, 'LockState', _onLockState);
    _broker.subscribe(1, 'ConnectedRadios', _onConnectedRadios);
  }

  void _onUniqueDataFrame(int deviceId, String name, Object? data) {
    if (!_isConnected) return;
    if (data is! AX25Packet) return;
    final packet = data;
    final from =
        packet.addresses.length > 1 ? packet.addresses[1].toString() : '?';
    final dataStr = packet.dataStr ?? '';
    setState(() {
      _outputLines.add('[$from] $dataStr');
    });
    _scrollToBottom();
  }

  void _onLockState(int deviceId, String name, Object? data) {
    if (data == null) {
      if (_selectedRadioId == deviceId && _isConnected) {
        setState(() {
          _isConnected = false;
        });
      }
      return;
    }
    if (data is Map) {
      final usage = data['Usage'] as String? ?? '';
      if (deviceId == _selectedRadioId) {
        setState(() {
          _isConnected = usage == 'Terminal';
        });
      }
    }
  }

  void _onConnectedRadios(int deviceId, String name, Object? data) {
    if (data is List) {
      final ids = <int>[];
      for (final radio in data) {
        if (radio is Map && radio.containsKey('DeviceId')) {
          ids.add(radio['DeviceId'] as int);
        }
      }
      setState(() {
        _radioDeviceIds = ids;
        if (_selectedRadioId != null && !ids.contains(_selectedRadioId)) {
          _selectedRadioId = null;
        }
      });
    }
  }

  void _connect() {
    if (_selectedRadioId == null) return;
    _broker.dispatch(_selectedRadioId!, 'SetLock', {
      'Usage': 'Terminal',
      'RegionId': -1,
      'ChannelId': -1,
    });
  }

  void _disconnect() {
    if (_selectedRadioId == null) return;
    _broker.dispatch(_selectedRadioId!, 'SetUnlock', {
      'Usage': 'Terminal',
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _broker.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildHeader(colors),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _buildTerminalArea(colors),
          ),
        ),
        _buildInputBar(colors),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colors.surfaceContainer,
      child: Row(
        children: [
          Text(
            'SYSTEM TERMINAL',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _isConnected
                  ? Colors.green.withAlpha(40)
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _isConnected ? 'CONNECTED' : 'IDLE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _isConnected
                    ? Colors.green.shade300
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          // Station selector
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<int>(
              value: _selectedRadioId,
              hint: Text(
                'Station',
                style: TextStyle(fontSize: 11, color: colors.outline),
              ),
              underline: const SizedBox(),
              isDense: true,
              dropdownColor: colors.surfaceContainerHigh,
              style: TextStyle(fontSize: 11, color: colors.onSurface),
              items: _radioDeviceIds
                  .map((id) => DropdownMenuItem(
                      value: id, child: Text('Radio $id')))
                  .toList(),
              onChanged: (v) => setState(() => _selectedRadioId = v),
            ),
          ),
          const SizedBox(width: 6),
          _HeaderButton(
            label: _isConnected ? 'Disconnect' : 'Connect',
            onPressed: _selectedRadioId != null
                ? (_isConnected ? _disconnect : _connect)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalArea(ColorScheme colors) {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _outputLines.isEmpty
            ? Center(
                child: Text(
                  'Terminal ready',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: colors.onSurfaceVariant,
                  ),
                ),
              )
            : SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  _outputLines.join('\n'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFFE6EDF3),
                    height: 1.5,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildInputBar(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: colors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Enter command...',
                hintStyle: TextStyle(fontSize: 12, color: colors.outline),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.primary),
                ),
                filled: true,
                fillColor: colors.surfaceContainerLow,
              ),
              onSubmitted: _isConnected ? (_) => _transmit() : null,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isConnected ? _transmit : null,
            style: FilledButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('TRANSMIT'),
          ),
        ],
      ),
    );
  }

  void _transmit() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _outputLines.add('> $text');
      _inputController.clear();
    });
    _scrollToBottom();
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.label, this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}
