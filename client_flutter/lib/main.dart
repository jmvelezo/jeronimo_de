import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(const JeronimoDeApp());
}

class JeronimoDeApp extends StatelessWidget {
  const JeronimoDeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.light).copyWith(primary: kPrimary, secondary: kPrimaryMid, surface: Colors.white, background: kSoftBackground);
    return MaterialApp(
      title: 'Jeronimo Dé',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: kSoftBackground,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: kInk,
          titleTextStyle: TextStyle(color: kInk, fontSize: 21, fontWeight: FontWeight.w900),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.94),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          labelStyle: const TextStyle(color: kMuted, fontWeight: FontWeight.w700),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: kPrimary, width: 1.6)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            elevation: 0,
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            foregroundColor: kPrimary,
            side: BorderSide(color: kPrimary.withOpacity(0.22)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withOpacity(0.96),
          indicatorColor: kLavender,
          labelTextStyle: MaterialStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(MaterialState.selected) ? kPrimary : kMuted,
              fontWeight: states.contains(MaterialState.selected) ? FontWeight.w900 : FontWeight.w600,
              fontSize: 12,
            );
          }),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
