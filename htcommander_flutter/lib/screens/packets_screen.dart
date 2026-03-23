import 'package:flutter/material.dart';
import '../core/data_broker.dart';
import '../core/data_broker_client.dart';
import '../handlers/packet_store.dart';
import '../radio/ax25/ax25_packet.dart';
import '../widgets/glass_card.dart';

class PacketsScreen extends StatefulWidget {
  const PacketsScreen({super.key});

  @override
  State<PacketsScreen> createState() => _PacketsScreenState();
}

class _PacketsScreenState extends State<PacketsScreen> {
  final DataBrokerClient _broker = DataBrokerClient();
  List<AX25Packet> _packets = [];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _broker.subscribe(1, 'PacketStoreUpdated', _onPacketStoreUpdated);
    // Load initial data
    _loadPackets();
  }

  void _loadPackets() {
    final store = DataBroker.getDataHandlerTyped<PacketStore>('PacketStore');
    if (store != null) {
      setState(() {
        _packets = store.packets;
      });
    }
  }

  void _onPacketStoreUpdated(int deviceId, String name, Object? data) {
    _loadPackets();
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }

  String _getFrameTypeName(AX25Packet p) {
    if (p.type == FrameType.iFrame) return 'I';
    if (p.type == FrameType.uFrameUI) return 'UI';
    if (p.type == FrameType.uFrameSABM) return 'SABM';
    if (p.type == FrameType.uFrameSABME) return 'SABME';
    if (p.type == FrameType.uFrameDISC) return 'DISC';
    if (p.type == FrameType.uFrameDM) return 'DM';
    if (p.type == FrameType.uFrameUA) return 'UA';
    if (p.type == FrameType.uFrameFRMR) return 'FRMR';
    if (p.type == FrameType.uFrameXID) return 'XID';
    if (p.type == FrameType.uFrameTEST) return 'TEST';
    if ((p.type & FrameType.uFrame) == FrameType.sFrame) {
      if (p.type == FrameType.sFrameRR) return 'RR';
      if (p.type == FrameType.sFrameRNR) return 'RNR';
      if (p.type == FrameType.sFrameREJ) return 'REJ';
      if (p.type == FrameType.sFrameSREJ) return 'SREJ';
      return 'S';
    }
    return 'U';
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
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildPacketTable(colors),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 180,
                  child: _buildDecodePanel(colors),
                ),
              ],
            ),
          ),
        ),
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
            'AX.25 PACKET STREAM',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_packets.length} packets',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPacketTable(ColorScheme colors) {
    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: _packets.isEmpty
          ? Center(
              child: Text(
                'No packets received',
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
                      label:
                          Text('TIME', style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label:
                          Text('FROM', style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label:
                          Text('TO', style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label:
                          Text('TYPE', style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label: Text('CHANNEL',
                          style: _columnHeaderStyle(colors)),
                    ),
                    DataColumn(
                      label:
                          Text('DATA', style: _columnHeaderStyle(colors)),
                    ),
                  ],
                  rows: List.generate(_packets.length, (i) {
                    final p = _packets[i];
                    final selected = _selectedIndex == i;
                    final from = p.addresses.length > 1
                        ? p.addresses[1].toString()
                        : '';
                    final to = p.addresses.isNotEmpty
                        ? p.addresses[0].toString()
                        : '';
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
                            Text(_formatTime(p.time), style: _cellStyle(colors))),
                        DataCell(
                            Text(from, style: _cellStyle(colors))),
                        DataCell(Text(to, style: _cellStyle(colors))),
                        DataCell(
                            Text(_getFrameTypeName(p), style: _cellStyle(colors))),
                        DataCell(Text(p.channelName,
                            style: _cellStyle(colors))),
                        DataCell(Text(
                          p.dataStr ?? '',
                          style: _cellMonoStyle(colors),
                          overflow: TextOverflow.ellipsis,
                        )),
                      ],
                    );
                  }),
                ),
              ),
            ),
    );
  }

  Widget _buildDecodePanel(ColorScheme colors) {
    final packet =
        _selectedIndex != null && _selectedIndex! < _packets.length
            ? _packets[_selectedIndex!]
            : null;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PACKET DECODE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
              ),
              child: packet == null
                  ? Center(
                      child: Text(
                        'Select a packet to view decode',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.outline,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Text(
                        'From: ${packet.addresses.length > 1 ? packet.addresses[1].toString() : ''}\n'
                        'To: ${packet.addresses.isNotEmpty ? packet.addresses[0].toString() : ''}\n'
                        'Type: ${_getFrameTypeName(packet)}\n'
                        'Channel: ${packet.channelName}\n'
                        'Data: ${packet.dataStr ?? ''}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: colors.onSurface,
                          height: 1.5,
                        ),
                      ),
                    ),
            ),
          ),
        ],
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

  TextStyle _cellMonoStyle(ColorScheme colors) {
    return TextStyle(
      fontSize: 11,
      fontFamily: 'monospace',
      color: colors.onSurface,
    );
  }
}
