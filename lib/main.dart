import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/assistant_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/assistant_screen.dart';
import 'screens/terms_screen.dart';
import 'services/log_service.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  await LogService().init();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProxyProvider<SettingsProvider, AssistantProvider>(
          create: (_) => AssistantProvider(),
          update: (_, settings, assistant) {
            assistant!.setSettingsProvider(settings);
            return assistant;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Kevin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 65, 73, 80)),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            if (!settings.loaded) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!settings.termsAccepted) {
              return const TermsScreen();
            }
            return const AssistantScreen();
          },
        ),
      ),
    );
  }
}
