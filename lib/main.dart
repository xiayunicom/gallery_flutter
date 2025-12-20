// lib/main.dart
import 'package:window_manager/window_manager.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'services/task_manager.dart';
import 'pages/gallery_page.dart';
import 'config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 设置图片缓存大小
  PaintingBinding.instance.imageCache.maximumSizeBytes = 500 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 3000;

  if (Platform.isAndroid) {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      // 只有包含 leanback 特性的才是真正的 Android TV
      isAndroidTv = androidInfo.systemFeatures.contains(
        'android.software.leanback',
      );
    } catch (e) {
      debugPrint("Device info check failed: $e");
    }
  }

  TaskManager().init(); // 初始化服务
  runApp(const GalleryApp());
}

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    String? getSystemFont() {
      if (Platform.isIOS || Platform.isMacOS) {
        return '.AppleSystemUIFont'; // iOS/macOS 专用的系统字体占位符
      } else if (Platform.isWindows) {
        return 'Microsoft YaHei'; // Windows 推荐强制指定微软雅黑，否则中文可能渲染不佳
      }
      return null; // Android/Linux 保持默认 (通常是 Roboto + Noto Sans)
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gallery Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: getSystemFont(),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF18181B),
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF202023),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Colors.white12,
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: CupertinoPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          },
        ),
      ),
      home: const GalleryPage(path: ""), // 引用拆分出去的页面
    );
  }
}
