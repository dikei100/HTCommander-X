import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../widgets/glass_card.dart';

class QsoEntry {
  String dateTime;
  String callsign;
  String frequency;
  String mode;
  String band;
  String rstSent;
  String rstRcvd;
  String myCall;
  String notes;

  QsoEntry({
    required this.dateTime,
    required this.callsign,
    required this.frequency,
    required this.mode,
    required this.band,
    required this.rstSent,
    required this.rstRcvd,
    required this.myCall,
    required this.notes,
  });

  Map<String, dynamic> toJson() => {
        'dateTime': dateTime,
        'callsign': callsign,
        'frequency': frequency,
        'mode': mode,
        'band': band,
        'rstSent': rstSent,
        'rstRcvd': rstRcvd,
        'myCall': myCall,
        'notes': notes,
      };

  factory QsoEntry.fromJson(Map<String, dynamic> json) => QsoEntry(
        dateTime: json['dateTime'] as String? ?? '',
        callsign: json['callsign'] as String? ?? '',
        frequency: json['frequency'] as String? ?? '',
        mode: json['mode'] as String? ?? '',
        band: json['band'] as String? ?? '',
        rstSent: json['rstSent'] as String? ?? '',
        rstRcvd: json['rstRcvd'] as String? ?? '',
        myCall: json['myCall'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );
}

class LogbookScreen extends StatefulWidget {
  const LogbookScreen({super.key});

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  List<QsoEntry> _entries = [];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _broker.subscribe(0, 'QsoLog', _onQsoLog);
    _loadEntries();
  }

  void _loadEntries() {
    final raw = DataBroker.getValue<String>(0, 'QsoLog', '');
    if (raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        setState(() {
          _entries = list
              .map((e) => QsoEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } catch (_) {
        // Ignore malformed data
      }
    }
  }

  void _onQsoLog(int deviceId, String name, Object? data) {
    if (data is String) {
      try {
        final list = jsonDecode(data) as List;
        setState(() {
          _entries = list
              .map((e) => QsoEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } catch (_) {
        // Ignore malformed data
      }
    }
  }

  void _saveEntries() {
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    DataBroker.dispatch(0, 'QsoLog', json);
  }

  void _addEntry() {
    final now = DateTime.now();
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _entries.add(QsoEntry(
        dateTime: dateStr,
        callsign: '',
        frequency: '',
        mode: '',
        band: '',
        rstSent: '59',
        rstRcvd: '59',
        myCall: '',
        notes: '',
      ));
      _selectedIndex = _entries.length - 1;
    });
    _saveEntries();
  }

  void _removeEntry() {
    if (_selectedIndex == null || _selectedIndex! >= _entries.length) return;
    setState(() {
      _entries.removeAt(_selectedIndex!);
      _selectedIndex = null;
    });
    _saveEntries();
  }

  @override
  void dispose() {
    _broker.dispose();
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
            child: _buildTable(colors),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: colors.surfaceContainer,
      child: Row(
        children: [
          Text(
            'QSO LOGBOOK',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_entries.length} entries',
            style: TextStyle(
              fontSize: 10,
              color: colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          _HeaderButton(label: 'Add', onPressed: _addEntry),
          const SizedBox(width: 6),
          _HeaderButton(
            label: 'Edit',
            onPressed: _selectedIndex != null ? () {} : null,
          ),
          const SizedBox(width: 6),
          _HeaderButton(
            label: 'Remove',
            onPressed: _selectedIndex != null ? _removeEntry : null,
          ),
          const SizedBox(width: 6),
          _HeaderButton(label: 'Export ADIF', onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildTable(ColorScheme colors) {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: _entries.isEmpty
          ? Center(
              child: Text(
                'No QSO entries',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.outline,
                ),
              ),
            )
          : SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 32,
                  dataRowMaxHeight: 32,
                  columnSpacing: 20,
                  horizontalMargin: 14,
                  headingRowColor: WidgetStateProperty.all(
                    colors.surfaceContainerHigh,
                  ),
                  columns: [
                    DataColumn(
                      label: Text('DATE/TIME',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('CALLSIGN',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('FREQUENCY',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('MODE',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('BAND',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('RST SENT',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('RST RCVD',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('MY CALL',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('NOTES',
                          style: _columnHeaderStyle(colors)),
                    ),
                  ],
                  rows: List.generate(_entries.length, (i) {
                    final e = _entries[i];
                    final selected = _selectedIndex == i;
                    return DataRow(
                      selected: selected,
                      color: selected
                          ? WidgetStateProperty.all(
                              colors.primary.withAlpha(30),
                            )
                          : null,
                      onSelectChanged: (_) {
                        setState(() => _selectedIndex = i);
                      },
                      cells: [
                        DataCell(Text(e.dateTime,
                            style: _cellStyle(colors))),
                        DataCell(Text(e.callsign,
                            style: _cellStyle(colors))),
                        DataCell(Text(e.frequency,
                            style: _cellStyle(colors))),
                        DataCell(
                            Text(e.mode, style: _cellStyle(colors))),
                        DataCell(
                            Text(e.band, style: _cellStyle(colors))),
                        DataCell(Text(e.rstSent,
                            style: _cellStyle(colors))),
                        DataCell(Text(e.rstRcvd,
                            style: _cellStyle(colors))),
                        DataCell(Text(e.myCall,
                            style: _cellStyle(colors))),
                        DataCell(Text(e.notes,
                            style: _cellStyle(colors))),
                      ],
                    );
                  }),
                ),
              ),
            ),
    );
  }

  TextStyle _columnHeaderStyle(ColorScheme colors) {
    return TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: colors.onSurfaceVariant,
    );
  }

  TextStyle _cellStyle(ColorScheme colors) {
    return TextStyle(
      fontSize: 12,
      color: colors.onSurface,
    );
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
