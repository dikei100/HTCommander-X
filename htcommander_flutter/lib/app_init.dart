import 'core/data_broker.dart';
import 'handlers/frame_deduplicator.dart';
import 'handlers/packet_store.dart';
import 'handlers/aprs_handler.dart';
import 'handlers/log_store.dart';
import 'handlers/mail_store.dart';
import 'handlers/audio_clip_handler.dart';
import 'handlers/torrent_handler.dart';
import 'handlers/bbs_handler.dart';
import 'handlers/voice_handler.dart';
import 'handlers/winlink_client.dart';
import 'handlers/server_stubs.dart';

/// Registers all data handlers with the DataBroker.
/// Must be called after DataBroker.initialize().
/// Mirrors C# MainWindow.InitializeDataHandlers().
void initializeDataHandlers() {
  DataBroker.addDataHandler('FrameDeduplicator', FrameDeduplicator());
  DataBroker.addDataHandler('PacketStore', PacketStore());
  DataBroker.addDataHandler('AprsHandler', AprsHandler());
  DataBroker.addDataHandler('LogStore', LogStore());
  DataBroker.addDataHandler('MailStore', MailStore());
  DataBroker.addDataHandler('AudioClipHandler', AudioClipHandler());
  DataBroker.addDataHandler('TorrentHandler', TorrentHandler());
  DataBroker.addDataHandler('BbsHandler', BbsHandler());
  DataBroker.addDataHandler('VoiceHandler', VoiceHandler());
  DataBroker.addDataHandler('WinlinkClient', WinlinkClient());

  // Server stubs (desktop-only, will be replaced with real implementations)
  DataBroker.addDataHandler('McpServer', McpServerStub());
  DataBroker.addDataHandler('WebServer', WebServerStub());
  DataBroker.addDataHandler('RigctldServer', RigctldServerStub());
  DataBroker.addDataHandler('AgwpeServer', AgwpeServerStub());
}
