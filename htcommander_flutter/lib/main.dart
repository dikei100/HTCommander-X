import 'package:flutter/material.dart';

import 'app.dart';
import 'app_init.dart';
import 'core/data_broker.dart';
import 'core/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize settings persistence
  final store = await SharedPrefsSettingsStore.create();
  DataBroker.initialize(store);

  // Register all data handlers
  initializeDataHandlers();

  // Log startup
  DataBroker.dispatch(1, 'LogInfo', 'HTCommander-X Flutter started', store: false);

  runApp(const HTCommanderApp());
}
