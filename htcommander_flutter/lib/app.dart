import 'dart:io' show Platform;
import 'package:flutter/material.dart';

import 'core/data_broker.dart';
import 'core/data_broker_client.dart';
import 'radio/radio.dart' as ht;
import 'radio/models/radio_dev_info.dart';
import 'platform/bluetooth_service.dart';
import 'platform/linux/linux_platform_services.dart';
import 'theme/signal_protocol_theme.dart';
import 'widgets/sidebar_nav.dart';
import 'screens/communication_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/logbook_screen.dart';
import 'screens/packets_screen.dart';
import 'screens/terminal_screen.dart';
import 'screens/bbs_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/torrent_screen.dart';
import 'screens/aprs_screen.dart';
import 'screens/map_screen.dart';
import 'screens/debug_screen.dart';
import 'screens/settings_screen.dart';

class HTCommanderApp extends StatelessWidget {
  const HTCommanderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HTCommander-X',
      debugShowCheckedModeBanner: false,
      theme: SignalProtocolTheme.light(),
      darkTheme: SignalProtocolTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _showSettings = false;

  // DataBroker wiring
  final DataBrokerClient _broker = DataBrokerClient();

  // Radio connection
  static const int _radioDeviceId = 100;
  PlatformServices? _platformServices;
  ht.Radio? _radio;
  String _radioMac = '';
  String _radioState = 'Disconnected';
  String? _radioName;
  int _batteryPercent = 0;

  bool get _isConnected => _radioState == 'connected';
  bool get _isConnecting => _radioState == 'connecting';

  static final _screens = <Widget>[
    const CommunicationScreen(),
    const ContactsScreen(),
    const LogbookScreen(),
    const PacketsScreen(),
    const TerminalScreen(),
    const BbsScreen(),
    const MailScreen(),
    const TorrentScreen(),
    const AprsScreen(),
    const MapScreen(),
    const DebugScreen(),
  ];

  Widget get _currentScreen {
    if (_showSettings) return const SettingsScreen();
    return _screens[_selectedIndex];
  }

  @override
  void initState() {
    super.initState();

    // Load last used MAC from settings
    _radioMac = DataBroker.getValue<String>(0, 'LastRadioMac', '38:D2:00:01:04:E2');

    // Detect platform and create services
    // LinuxPlatformServices will be created once the dart:ffi implementation exists
    // For now, _platformServices stays null (connection will log an error)
    _initPlatformServices();

    // Subscribe to radio state changes
    _broker.subscribe(DataBroker.allDevices, 'State', _onRadioStateChanged);
    _broker.subscribe(DataBroker.allDevices, 'Info', _onRadioInfoChanged);
    _broker.subscribe(DataBroker.allDevices, 'BatteryAsPercentage', _onBatteryChanged);
    _broker.subscribe(DataBroker.allDevices, 'FriendlyName', _onFriendlyNameChanged);
  }

  void _initPlatformServices() {
    if (Platform.isLinux) {
      _platformServices = LinuxPlatformServices();
    }
  }

  @override
  void dispose() {
    _broker.dispose();
    _radio?.dispose();
    super.dispose();
  }

  // ── DataBroker callbacks ───────────────────────────────────────────

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    if (deviceId < 100) return;
    if (data is String && mounted) {
      setState(() => _radioState = data);
    }
  }

  void _onRadioInfoChanged(int deviceId, String name, Object? data) {
    if (deviceId < 100) return;
    if (data is RadioDevInfo && mounted) {
      setState(() {
        _radioName = 'Radio ${data.productId}';
      });
    } else if (data == null && mounted) {
      setState(() => _radioName = null);
    }
  }

  void _onBatteryChanged(int deviceId, String name, Object? data) {
    if (deviceId < 100) return;
    if (data is int && mounted) {
      setState(() => _batteryPercent = data);
    }
  }

  void _onFriendlyNameChanged(int deviceId, String name, Object? data) {
    if (deviceId < 100 || data is! String) return;
    if (mounted) setState(() => _radioName = data);
  }

  // ── Radio connection ───────────────────────────────────────────────

  void _onConnectTap() {
    if (_isConnected || _isConnecting) {
      _disconnectRadio();
    } else {
      _showConnectDialog();
    }
  }

  void _connectToRadio(String mac) {
    if (mac.isEmpty) return;

    // Save MAC
    _radioMac = mac;
    DataBroker.dispatch(0, 'LastRadioMac', mac);

    if (_platformServices == null) {
      // No platform implementation yet — show info
      DataBroker.dispatch(1, 'LogInfo',
          'Bluetooth not yet implemented for this platform. '
          'Waiting for Linux dart:ffi RFCOMM implementation.',
          store: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bluetooth transport not yet implemented for this platform'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Create and connect radio
    _radio?.dispose();
    _radio = ht.Radio(_radioDeviceId, mac, _platformServices);
    DataBroker.addDataHandler('Radio_$_radioDeviceId', _radio!);

    // Dispatch connected radios list
    DataBroker.dispatch(1, 'ConnectedRadios', [_radio!]);

    _radio!.connect();
  }

  void _disconnectRadio() {
    if (_radio != null) {
      _radio!.disconnect();
      DataBroker.removeDataHandler('Radio_$_radioDeviceId');
      _radio = null;
    }
    DataBroker.dispatch(1, 'ConnectedRadios', <ht.Radio>[]);
    setState(() {
      _radioState = 'Disconnected';
      _radioName = null;
      _batteryPercent = 0;
    });
  }

  void _showConnectDialog() {
    final controller = TextEditingController(text: _radioMac);
    showDialog(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: colors.surfaceContainerHigh,
          title: Text(
            'CONNECT RADIO',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
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
                controller: controller,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: colors.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'XX:XX:XX:XX:XX:XX',
                  hintStyle: TextStyle(color: colors.outline),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Compatible: UV-Pro, VR-N76, VR-N7500, GA-5WB, RT-660',
                style: TextStyle(fontSize: 10, color: colors.outline),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _connectToRadio(controller.text.trim());
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
      _showSettings = false;
    });
  }

  void _onSettingsTap() {
    setState(() => _showSettings = true);
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width > 800;
    final colors = Theme.of(context).colorScheme;

    if (isWide) {
      return Scaffold(
        body: Column(
          children: [
            _buildToolbar(colors),
            Expanded(
              child: Row(
                children: [
                  SidebarNav(
                    selectedIndex: _showSettings ? -1 : _selectedIndex,
                    onDestinationSelected: _onDestinationSelected,
                    onSettingsTap: _onSettingsTap,
                    onAboutTap: () => _showAboutDialog(context),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: _currentScreen),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _buildToolbar(colors),
          Expanded(child: _currentScreen),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _showSettings
            ? sidebarDestinations.length
            : _selectedIndex.clamp(0, 4),
        onDestinationSelected: (index) {
          if (index < _mobileDestinations.length) {
            setState(() {
              _selectedIndex = _mobileIndexMap[index];
              _showSettings = false;
            });
          }
        },
        destinations: _mobileDestinations
            .map((d) => NavigationDestination(icon: Icon(d.icon), label: d.label))
            .toList(),
      ),
    );
  }

  Widget _buildToolbar(ColorScheme colors) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'HTCommander-X',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.primary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected
                  ? colors.tertiary
                  : _isConnecting
                      ? Colors.amber
                      : colors.outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isConnected
                  ? '${_radioName ?? "Radio"} ($_radioMac) ${_batteryPercent > 0 ? "- $_batteryPercent%" : ""}'
                  : _isConnecting
                      ? 'Connecting to $_radioMac...'
                      : 'No Radio Connected',
              style: TextStyle(
                fontSize: 11,
                color: _isConnected ? colors.onSurface : colors.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: _isConnecting
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Connecting...', style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                    ],
                  )
                : _isConnected
                    ? OutlinedButton.icon(
                        onPressed: _onConnectTap,
                        icon: const Icon(Icons.bluetooth_disabled, size: 14),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(fontSize: 11),
                          side: BorderSide(color: colors.error.withAlpha(120)),
                          foregroundColor: colors.error,
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _onConnectTap,
                        icon: const Icon(Icons.bluetooth, size: 14),
                        label: const Text('Connect Radio'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  static const _mobileIndexMap = [0, 1, 8, 9, 10];
  static final _mobileDestinations = [
    sidebarDestinations[0],
    sidebarDestinations[1],
    sidebarDestinations[8],
    sidebarDestinations[9],
    sidebarDestinations[10],
  ];

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'HTCommander-X',
      applicationVersion: '0.3.0',
      children: [
        const Text('Flutter edition of HTCommander ham radio controller.'),
      ],
    );
  }
}
