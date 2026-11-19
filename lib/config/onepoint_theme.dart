import 'package:flutter/material.dart';
import '../utils/page_transitions.dart';
import 'onepoint_design.dart';

ThemeData buildOnepointTheme() => ThemeData(
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: OnepointPageTransitionsBuilder(),
        TargetPlatform.iOS: OnepointPageTransitionsBuilder(),
        TargetPlatform.macOS: OnepointPageTransitionsBuilder(),
        TargetPlatform.windows: OnepointPageTransitionsBuilder(),
        TargetPlatform.linux: OnepointPageTransitionsBuilder(),
        TargetPlatform.fuchsia: OnepointPageTransitionsBuilder(),
      }),
      // Figma typography. Inter has no Hangul glyphs, so bundle a fallback.
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Pretendard'],
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: OnepointDesign.lime,
        foregroundColor: Colors.black,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: OnepointDesign.control,
      ),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      )),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        backgroundColor: OnepointDesign.lime,
        foregroundColor: Colors.black,
        disabledBackgroundColor: OnepointDesign.surface,
        disabledForegroundColor: Colors.white24,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: OnepointDesign.control,
      )),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: OnepointDesign.lime,
        foregroundColor: Colors.black,
        disabledBackgroundColor: OnepointDesign.surface,
        disabledForegroundColor: Colors.white24,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: OnepointDesign.control,
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        backgroundColor: OnepointDesign.surface,
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: OnepointDesign.control,
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
              foregroundColor: OnepointDesign.blue,
              textStyle: OnepointDesign.control,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)))),
      colorScheme: const ColorScheme.dark(
        primary: OnepointDesign.lime,
        onPrimary: Colors.black,
        secondary: OnepointDesign.blue,
        onSecondary: Colors.black,
        surface: OnepointDesign.surface,
        onSurface: Colors.white,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: OnepointDesign.blue,
        selectionColor: Color(0x5524A9FF),
        selectionHandleColor: OnepointDesign.blue,
      ),

      // Background and surfaces from the supplied SVG exports.
      scaffoldBackgroundColor: OnepointDesign.background,

      // Shared screen title: Inter Semi Bold, 20 logical pixels.
      appBarTheme: const AppBarTheme(
        backgroundColor: OnepointDesign.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: ['Pretendard'],
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      // Preserve the existing light text on dark surfaces.
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
      ),
    );
