import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://thpkiasoiifmapkoerls.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRocGtpYXNvaWlmbWFwa29lcmxzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI4MDA2ODUsImV4cCI6MjA4ODM3NjY4NX0.2ixdJyE3cDnQeWiyRK3TO_yqTVWHK-NxpB0n4N1jqkI',
  );

  runApp(const ProviderScope(child: ACTTradingApp()));
}

class ACTTradingApp extends ConsumerWidget {
  const ACTTradingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'ACT Trading',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
