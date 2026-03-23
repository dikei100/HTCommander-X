import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../handlers/aprs_handler.dart';
import '../widgets/glass_card.dart';

class AprsScreen extends StatefulWidget {
  const AprsScreen({super.key});

  @override
  State<AprsScreen> createState() => _AprsScreenState();
}

class _AprsScreenState extends State<AprsScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  bool _showAll = false;
  bool _showWarning = true;
  String _selectedRoute = 'WIDE1-1,WIDE2-1';
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  final List<String> _routes = [
    'WIDE1-1,WIDE2-1',
    'WIDE1-1',
    'WIDE2-1',
    'Direct',
  ];

  List<AprsEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _broker.subscribe(1, 'AprsStoreUpdated', _onAprsStoreUpdated);
    // Load initial data
    _loadEntries();
  }

  void _loadEntries() {
    final handler =
        DataBroker.getDataHandlerTyped<AprsHandler>('AprsHandler');
    if (handler != null) {
      setState(() {
        _entries = handler.entries;
      });
    }
  }

  void _onAprsStoreUpdated(int deviceId, String name, Object? data) {
    _loadEntries();
  }

  @override
  void dispose() {
    _broker.dispose();
    _destinationController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildHeader(colors),
        if (_showWarning) _buildWarningBanner(colors),
        Expanded(
          child: _buildDataTable(colors),
        ),
        _buildTransmitBar(colors),
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
            'APRS DASHBOARD',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'N0CALL',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 28,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _showAll,
                  onChanged: (v) => setState(() => _showAll = v ?? false),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                ),
                Text(
                  'SHOW ALL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '${_entries.length} MESSAGES',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.amber.withAlpha(25),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No APRS channel configured. Set an APRS channel in Settings to enable packet reception.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.amber[700],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: () => setState(() => _showWarning = false),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'PACKET LOG',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowHeight: 32,
                    dataRowMinHeight: 28,
                    dataRowMaxHeight: 32,
                    columnSpacing: 24,
                    horizontalMargin: 16,
                    headingTextStyle: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant,
                    ),
                    dataTextStyle: TextStyle(
                      fontSize: 11,
                      color: colors.onSurface,
                    ),
                    columns: const [
                      DataColumn(label: Text('TIME')),
                      DataColumn(label: Text('FROM')),
                      DataColumn(label: Text('TO')),
                      DataColumn(label: Text('TYPE')),
                      DataColumn(label: Text('MESSAGE')),
                    ],
                    rows: _entries.map((entry) {
                      final typeName = entry.packet.dataType.name;
                      return DataRow(cells: [
                        DataCell(Text(_formatTime(entry.time))),
                        DataCell(Text(
                          entry.from,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        )),
                        DataCell(Text(entry.to)),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _typeColor(typeName).withAlpha(25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              typeName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _typeColor(typeName),
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text(entry.packet.comment)),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'position':
      case 'positionMsg':
      case 'positionTime':
      case 'positionTimeMsg':
        return Colors.blue;
      case 'status':
        return Colors.green;
      case 'weatherReport':
        return Colors.orange;
      case 'beacon':
        return Colors.purple;
      case 'message':
        return Colors.teal;
      case 'micE':
      case 'micECurrent':
      case 'micEOld':
        return Colors.indigo;
      case 'object':
      case 'item':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildTransmitBar(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          // Route dropdown
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ROUTE',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButton<String>(
                  value: _selectedRoute,
                  underline: const SizedBox(),
                  isDense: true,
                  dropdownColor: colors.surfaceContainerHigh,
                  style: TextStyle(fontSize: 10, color: colors.onSurface),
                  items: _routes
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedRoute = v ?? _selectedRoute),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Destination
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'DESTINATION',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _destinationController,
                    style: TextStyle(fontSize: 11, color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Callsign',
                      hintStyle:
                          TextStyle(fontSize: 10, color: colors.outline),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Message
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MESSAGE',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _messageController,
                    style: TextStyle(fontSize: 11, color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Type APRS message...',
                      hintStyle:
                          TextStyle(fontSize: 10, color: colors.outline),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              child: const Text('SEND'),
            ),
          ),
        ],
      ),
    );
  }
}
