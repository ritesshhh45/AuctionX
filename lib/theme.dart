import 'package:flutter/material.dart';

// Premium Dark: deep navy background, gold actions, purple accents, white text.
const kBg = Color(0xFF10111D); // page background
const kCard = Color(0xFF1A1B2C); // cards, dialogs, inputs, nav bar
const kText = Color(0xFFFFFFFF); // text
const kGold = Color(0xFFDDB65B); // primary buttons and highlights
const kPurple = Color(0xFF6D42C1); // accents
const kSoft = Color(0xFF2A2347); // soft purple tint (chips, avatars, selected)
const kLine = Color(0xFF34364F); // borders and dividers

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kGold, brightness: Brightness.dark).copyWith(
    primary: kGold,
    onPrimary: kBg,
    secondary: kPurple,
    onSecondary: kText,
    onSurface: kText,
    surface: kBg,
    surfaceContainerLow: kCard,
    surfaceContainerHigh: kCard,
    primaryContainer: kSoft,
    onPrimaryContainer: kText,
    outline: kLine,
  );
  final text = ThemeData(brightness: Brightness.dark, useMaterial3: true).textTheme.apply(bodyColor: kText, displayColor: kText);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    textTheme: text,
    appBarTheme: const AppBarTheme(backgroundColor: kBg, foregroundColor: kText, elevation: 0, scrolledUnderElevation: 0),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: kGold, foregroundColor: kBg),
    dividerColor: kLine,
  );
}

/// Live screen presets: [background, text, accent]
const kLiveThemes = <String, List<Color>>{
  'classic': [Color(0xFF10111D), Color(0xFFFFFFFF), Color(0xFFDDB65B)],
  'maroon': [Color(0xFF5B2333), Color(0xFFFFF6EC), Color(0xFFE8B84A)],
  'teal': [Color(0xFF1F5F5B), Color(0xFFFFF6EC), Color(0xFFF2C14E)],
  'lime': [Color(0xFF2F6B3A), Color(0xFFFFF6EC), Color(0xFFC8F25A)],
  'bronze': [Color(0xFF6B4A32), Color(0xFFFFF6EC), Color(0xFFF2D38A)],
};
