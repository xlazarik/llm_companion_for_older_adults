import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'providers/assistant_provider.dart';
import 'screens/assistant_screen.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AssistantProvider(),
      child: MaterialApp(
        title: 'Asistent pre Starku',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 65, 73, 80)),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: const AssistantScreen(),
      ),
    );
  }
}
