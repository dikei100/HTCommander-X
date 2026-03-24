import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../platform/linux/linux_audio_service.dart';
import '../radio/models/radio_dev_info.dart';
import '../radio/models/radio_ht_status.dart';
import '../radio/models/radio_settings.dart';
import '../radio/models/radio_channel_info.dart';
import '../radio/models/radio_position.dart';
import '../widgets/glass_card.dart';
import '../widgets/vfo_display.dart';
import '../widgets/signal_bars.dart';
import '../widgets/radio_status_card.dart';
import '../widgets/ptt_button.dart';
import '../widgets/status_strip.dart';

/// Communication Hub — the flagship screen.
/// Layout: Control panel (left, 320px) + content area (right).
class CommunicationScreen extends StatefulWidget {
  const CommunicationScreen({super.key});

  @override
  State<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends State<CommunicationScreen> {
  final TextEditingController _inputController = TextEditingController();
  String _selectedMode = 'Chat';
  bool _isMuted = false;

  // DataBroker wiring
  late final DataBrokerClient _broker;

  // Live state from DataBroker
  bool _isConnected = false;
  String? _deviceName;
  int _rssi = 0;
  bool _isTransmitting = false;
  int _batteryPercent = 0;
  bool _isGpsLocked = false;
  double _vfoAFreq = 0;
  double _vfoBFreq = 0;
  String _vfoAName = '';
  String _vfoBName = '';
  final List<String> _messages = [];

  // Cached radio data for deriving VFO info
  RadioSettings? _settings;
  List<RadioChannelInfo?> _channels = [];

  // Audio I/O
  LinuxMicCapture? _micCapture;
  LinuxAudioOutput? _audioOutput;
  bool _audioEnabled = false;

  @override
  void initState() {
    super.initState();
    _broker = DataBrokerClient();
    _loadCurrentState();

    _broker.subscribe(100, 'State', _onState);
    _broker.subscribe(100, 'Info', _onInfo);
    _broker.subscribe(100, 'FriendlyName', _onFriendlyName);
    _broker.subscribe(100, 'HtStatus', _onHtStatus);
    _broker.subscribe(100, 'Settings', _onSettings);
    _broker.subscribe(100, 'Channels', _onChannels);
    _broker.subscribe(100, 'BatteryAsPercentage', _onBattery);
    _broker.subscribe(100, 'Position', _onPosition);
    _broker.subscribe(100, 'AudioState', _onAudioState);
  }

  void _loadCurrentState() {
    final state = _broker.getValue<String>(100, 'State', '');
    _isConnected = state.toLowerCase() == 'connected';

    final friendlyName = _broker.getValue<String>(100, 'FriendlyName', '');
    if (friendlyName.isNotEmpty) {
      _deviceName = friendlyName;
    } else {
      final info = _broker.getValueDynamic(100, 'Info');
      if (info is RadioDevInfo) {
        _deviceName = 'Radio ${info.productId}';
      }
    }

    final htStatus = _broker.getValueDynamic(100, 'HtStatus');
    if (htStatus is RadioHtStatus) {
      _rssi = htStatus.rssi;
      _isTransmitting = htStatus.isInTx;
    }

    final settings = _broker.getValueDynamic(100, 'Settings');
    if (settings is RadioSettings) _settings = settings;

    final channels = _broker.getValueDynamic(100, 'Channels');
    if (channels is List) _channels = channels.cast<RadioChannelInfo?>();

    _batteryPercent = _broker.getValue<int>(100, 'BatteryAsPercentage', 0);

    final pos = _broker.getValueDynamic(100, 'Position');
    if (pos is RadioPosition) _isGpsLocked = pos.isGpsLocked;

    _updateVfoFromChannels();
  }

  @override
  void dispose() {
    _stopMicCapture();
    _audioOutput?.stop();
    _broker.dispose();
    _inputController.dispose();
    super.dispose();
  }

  // ── DataBroker callbacks ──────────────────────────────────────────

  void _onState(int deviceId, String name, Object? data) {
    if (!mounted) return;
    final connected = (data is String && data.toLowerCase() == 'connected');
    setState(() => _isConnected = connected);
    if (!connected) {
      _stopMicCapture();
      _audioOutput?.stop();
      _audioOutput = null;
      if (mounted) setState(() => _audioEnabled = false);
    }
  }

  void _onAudioState(int deviceId, String name, Object? data) {
    if (!mounted || data is! bool) return;
    setState(() => _audioEnabled = data);
    if (data && _audioOutput == null && Platform.isLinux) {
      _audioOutput = LinuxAudioOutput();
      _audioOutput!.start(100);
    } else if (!data) {
      _audioOutput?.stop();
      _audioOutput = null;
    }
  }

  void _onInfo(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioDevInfo) return;
    if (_deviceName == null || _deviceName!.startsWith('Radio ')) {
      setState(() => _deviceName = 'Radio ${data.productId}');
    }
  }

  void _onFriendlyName(int deviceId, String name, Object? data) {
    if (!mounted || data is! String || data.isEmpty) return;
    setState(() => _deviceName = data);
  }

  void _onHtStatus(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioHtStatus) return;
    setState(() {
      _rssi = data.rssi;
      _isTransmitting = data.isInTx;
    });
  }

  void _onSettings(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioSettings) return;
    setState(() {
      _settings = data;
      _updateVfoFromChannels();
    });
  }

  void _onChannels(int deviceId, String name, Object? data) {
    if (!mounted || data is! List) return;
    setState(() {
      _channels = data.cast<RadioChannelInfo?>();
      _updateVfoFromChannels();
    });
  }

  void _onBattery(int deviceId, String name, Object? data) {
    if (!mounted || data is! int) return;
    setState(() => _batteryPercent = data);
  }

  void _onPosition(int deviceId, String name, Object? data) {
    if (!mounted || data is! RadioPosition) return;
    setState(() => _isGpsLocked = data.isGpsLocked);
  }

  void _updateVfoFromChannels() {
    final settings = _settings;
    if (settings == null) return;
    final chA = settings.channelA;
    final chB = settings.channelB;

    if (chA >= 0 && chA < _channels.length && _channels[chA] != null) {
      final ch = _channels[chA]!;
      _vfoAFreq = ch.rxFreq / 1000000.0;
      _vfoAName = ch.nameStr;
    } else {
      _vfoAFreq = 0;
      _vfoAName = '';
    }

    if (chB >= 0 && chB < _channels.length && _channels[chB] != null) {
      final ch = _channels[chB]!;
      _vfoBFreq = ch.rxFreq / 1000000.0;
      _vfoBName = ch.nameStr;
    } else {
      _vfoBFreq = 0;
      _vfoBName = '';
    }
  }

  // ── PTT ────────────────────────────────────────────────────────────

  void _onPttStart() {
    if (!_isConnected) return;
    if (!_audioEnabled) {
      DataBroker.dispatch(100, 'SetAudio', true, store: false);
    }
    if (Platform.isLinux) {
      _micCapture ??= LinuxMicCapture();
      _micCapture!.start(100);
    }
  }

  void _onPttStop() {
    _stopMicCapture();
    DataBroker.dispatch(100, 'CancelVoiceTransmit', null, store: false);
  }

  void _stopMicCapture() {
    _micCapture?.stop();
    _micCapture = null;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Control panel
              SizedBox(
                width: 320,
                child: _buildControlPanel(colors),
              ),
              // Right: Content area
              Expanded(
                child: Column(
                  children: [
                    // Quick controls bar
                    _buildQuickControls(colors),
                    // Two-column content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildPacketNodeCard(colors)),
                            const SizedBox(width: 14),
                            Expanded(child: _buildOperationLog(colors)),
                          ],
                        ),
                      ),
                    ),
                    // Input bar
                    _buildInputBar(colors),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Status strip at very bottom
        StatusStrip(isConnected: _isConnected),
      ],
    );
  }

  Widget _buildControlPanel(ColorScheme colors) {
    return Container(
      color: colors.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Device status
            RadioStatusCard(
              deviceName: _deviceName,
              isConnected: _isConnected,
              rssi: _rssi,
              isTransmitting: _isTransmitting,
              batteryPercent: _batteryPercent,
              isGpsLocked: _isGpsLocked,
            ),
            const SizedBox(height: 14),

            // Frequency Matrix title
            Row(
              children: [
                Text(
                  'FREQUENCY MATRIX',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // VFO A
            VfoDisplay(
              label: 'VFO A',
              frequency: _vfoAFreq,
              channelName: _vfoAName,
              modulation: 'FM',
              isActive: true,
              isPrimary: true,
            ),
            const SizedBox(height: 8),

            // VFO B
            VfoDisplay(
              label: 'VFO B',
              frequency: _vfoBFreq,
              channelName: _vfoBName,
              isActive: false,
              isPrimary: false,
            ),
            const SizedBox(height: 20),

            // PTT Button with integrated label
            Center(
              child: PttButton(
                isEnabled: _isConnected,
                isTransmitting: _isTransmitting,
                size: 80,
                onPttStart: _onPttStart,
                onPttStop: _onPttStop,
              ),
            ),
            const SizedBox(height: 16),

            // RSSI / TX bars
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _MiniStatus(
                    label: 'RSSI',
                    child: SignalBars(level: _rssi, height: 14),
                  ),
                  const SizedBox(width: 16),
                  _MiniStatus(
                    label: 'TX',
                    child: SignalBars(
                      level: _isTransmitting ? 12 : 0,
                      isTransmitting: true,
                      height: 14,
                    ),
                  ),
                  const Spacer(),
                  if (_rssi > 0)
                    Text(
                      '${-113 + _rssi} dBm',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickControls(ColorScheme colors) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colors.surfaceContainer,
      child: Row(
        children: [
          Text(
            'COMMUNICATION HUB',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isConnected ? 'Connected' : 'Idle',
            style: TextStyle(
              fontSize: 10,
              color: colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          _QuickButton(
            label: 'Send SSTV',
            onPressed: _isConnected ? () {} : null,
          ),
          const SizedBox(width: 6),
          _QuickButton(
            label: _isMuted ? 'Unmute' : 'Mute',
            isActive: _isMuted,
            onPressed: () => setState(() => _isMuted = !_isMuted),
          ),
          const SizedBox(width: 6),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<String>(
              value: _selectedMode,
              underline: const SizedBox(),
              isDense: true,
              dropdownColor: colors.surfaceContainerHigh,
              style: TextStyle(fontSize: 11, color: colors.onSurface),
              items: ['Chat', 'Speak', 'Morse', 'DTMF']
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedMode = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPacketNodeCard(ColorScheme colors) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LOCAL PACKET NODE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          // SSTV / Data Link placeholder
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.satellite_alt, size: 32, color: colors.outline),
                  const SizedBox(height: 8),
                  Text(
                    'SSTV / DATA LINK',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Waiting for incoming data...',
                    style: TextStyle(fontSize: 11, color: colors.outline),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Status / Protocol row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STATUS',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Standby',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PROTOCOL',
                      style: TextStyle(
                        fontSize: 9,
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AX.25',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOperationLog(ColorScheme colors) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OPERATION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 28, color: colors.outline),
                        const SizedBox(height: 8),
                        Text(
                          'No messages yet',
                          style: TextStyle(fontSize: 11, color: colors.outline),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _messages[index],
                          style: TextStyle(fontSize: 12, color: colors.onSurface),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          Text(
            '>',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.primary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inputController,
              style: TextStyle(fontSize: 12, color: colors.onSurface),
              decoration: InputDecoration(
                hintText: 'Type message...',
                hintStyle: TextStyle(fontSize: 12, color: colors.outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.outlineVariant.withAlpha(38)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.outlineVariant.withAlpha(38)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.primary),
                ),
                filled: true,
                fillColor: colors.surfaceContainerLow,
              ),
              onSubmitted: _isConnected ? (_) => _sendMessage() : null,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isConnected ? _sendMessage : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: const Text('Transmit'),
          ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: _isConnected ? () {} : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _broker.dispatch(1, 'Chat', text, store: false);
    setState(() {
      _messages.add(text);
      _inputController.clear();
    });
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({required this.label, this.onPressed, this.isActive = false});
  final String label;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        backgroundColor: isActive ? colors.primaryContainer : null,
        textStyle: const TextStyle(fontSize: 11),
      ),
      child: Text(label),
    );
  }
}

class _MiniStatus extends StatelessWidget {
  const _MiniStatus({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: colors.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
