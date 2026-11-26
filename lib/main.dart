// 入口：刻意保持最简，这是防闪退的关键。
// main() 里只做 runApp，不初始化数据库、不碰相机、不加载任何原生 AI 库。
// 数据库在第一次打开衣橱时才懒加载；相机/姿态/抠图只在对应页面打开时初始化，
// 离开页面即释放。即使某个插件在某台手机上加载失败，也只影响那一个页面，
// 不会让 App 在启动时秒退。
import 'package:flutter/material.dart';

import 'pages/live_tryon_page.dart';
import 'pages/outfits_page.dart';
import 'pages/static_tryon_page.dart';
import 'pages/wardrobe_page.dart';

void main() {
  runApp(const AiWardrobeApp());
}

class AiWardrobeApp extends StatelessWidget {
  const AiWardrobeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 电子衣橱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  // 注意：不用 IndexedStack——它会一次性创建全部 4 个页面的 State，
  // 包括 AR 试衣页的相机初始化。改成按需创建，离开 AR 页即 dispose 释放相机。
  Widget _page(int i) {
    switch (i) {
      case 0:
        return const WardrobePage();
      case 1:
        return OutfitsPage(
          onTryOn: (tab) => setState(() => _index = tab),
        );
      case 2:
        return const StaticTryOnPage();
      case 3:
      default:
        return const LiveTryOnPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _page(_index),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checkroom_outlined),
            selectedIcon: Icon(Icons.checkroom),
            label: '衣橱',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '穿搭',
          ),
          NavigationDestination(
            icon: Icon(Icons.accessibility_new_outlined),
            selectedIcon: Icon(Icons.accessibility_new),
            label: '静态试穿',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'AR试衣',
          ),
        ],
      ),
    );
  }
}
