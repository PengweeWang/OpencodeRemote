import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'src/rust/frb_generated.dart';
import 'theme/app_theme.dart';
import 'views/home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize RustLib
  try {
    await RustLib.init(forceSameCodegenVersion: false);
  } catch (e, stack) {
    debugPrint('Failed to initialize RustLib: $e\n$stack');
  }

  // Initialize Local Storage
  try {
    await StorageService().init();
  } catch (e, stack) {
    debugPrint('Failed to initialize StorageService: $e\n$stack');
  }

  runApp(const OpencodeRemoteApp());
}

class OpencodeRemoteApp extends StatelessWidget {
  const OpencodeRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Opencode Remote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeView(),
    );
  }
}
