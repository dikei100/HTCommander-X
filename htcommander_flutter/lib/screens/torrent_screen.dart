import 'package:flutter/material.dart';
import '../core/data_broker_client.dart';
import '../handlers/torrent_handler.dart';
import '../widgets/glass_card.dart';

class TorrentScreen extends StatefulWidget {
  const TorrentScreen({super.key});

  @override
  State<TorrentScreen> createState() => _TorrentScreenState();
}

class _TorrentScreenState extends State<TorrentScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  bool _isActive = false;
  List<TorrentFile> _torrents = [];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _broker.subscribe(1, 'TorrentFiles', _onTorrentFiles);
  }

  void _onTorrentFiles(int deviceId, String name, Object? data) {
    if (data is List<TorrentFile>) {
      setState(() {
        _torrents = data;
        if (_selectedIndex != null && _selectedIndex! >= _torrents.length) {
          _selectedIndex = null;
        }
      });
    }
  }

  void _addFile() {
    // Placeholder: in the future, open a file picker and dispatch TorrentAddFile
  }

  void _activate() {
    setState(() {
      _isActive = !_isActive;
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
            child: _buildTorrentTable(colors),
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
            'TORRENT FILES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _isActive
                  ? colors.tertiary.withAlpha(30)
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _isActive ? 'ACTIVE' : 'INACTIVE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _isActive
                    ? colors.tertiary
                    : colors.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          _HeaderButton(label: 'Add File', onPressed: _addFile),
          const SizedBox(width: 6),
          _HeaderButton(
            label: _isActive ? 'Deactivate' : 'Activate',
            onPressed: _activate,
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentTable(ColorScheme colors) {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: _torrents.isEmpty
          ? Center(
              child: Text(
                'No torrent files',
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
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 40,
                  columnSpacing: 24,
                  horizontalMargin: 14,
                  headingRowColor: WidgetStateProperty.all(
                    colors.surfaceContainerHigh,
                  ),
                  columns: [
                    DataColumn(
                      label:
                          Text('FILE', style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label:
                          Text('MODE', style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label:
                          Text('SIZE', style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('PROGRESS',
                          style: _columnHeaderStyle(colors)),
                    ),
                  ],
                  rows: List.generate(_torrents.length, (i) {
                    final t = _torrents[i];
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
                        DataCell(
                            Text(t.fileName, style: _cellStyle(colors))),
                        DataCell(
                            Text(t.mode, style: _cellStyle(colors))),
                        DataCell(
                            Text(_formatSize(t.fileSize), style: _cellStyle(colors))),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: Row(
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: t.progress,
                                    minHeight: 6,
                                    borderRadius:
                                        BorderRadius.circular(3),
                                    backgroundColor:
                                        colors.surfaceContainerLow,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                      t.progress >= 1.0
                                          ? Colors.green
                                          : colors.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${(t.progress * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
