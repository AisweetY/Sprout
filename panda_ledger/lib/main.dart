import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Supabase
  // 可通过环境变量覆盖（CI/CD 场景）：
  //   flutter run --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx
  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://rnoxwqyaicbkewtqmfal.supabase.co',
    ),
    publishableKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_WNmWD0159YFlaSHvXAQMaQ_2oSQ0Rzb',
    ),
  );

  runApp(
    const ProviderScope(
      child: PandaLedgerApp(),
    ),
  );
}

class PandaLedgerApp extends ConsumerWidget {
  const PandaLedgerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '熊猫记账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}
