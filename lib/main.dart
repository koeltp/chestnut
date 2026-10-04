import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database.dart';
import 'data/repositories/bill_repository.dart';
import 'data/repositories/budget_repository.dart';
import 'data/repositories/category_repository.dart';
import 'pages/main_page.dart';
import 'providers/bill_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/category_provider.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 固定竖屏，记账场景无横屏需求
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 预加载设置存储，UI 各处可同步读取开关状态
  final prefs = await SharedPreferences.getInstance();
  runApp(ChestnutApp(prefs: prefs));
}

/// 应用根组件：完成依赖注入（数据库 → 仓储 → Provider）
class ChestnutApp extends StatelessWidget {
  const ChestnutApp({super.key, required this.prefs});

  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 数据库为全局单例，应用退出时由 dispose 关闭
        Provider<AppDatabase>(
          create: (_) => AppDatabase(),
          dispose: (_, db) => db.close(),
        ),
        // 仓储层：一次性创建的单例依赖，用 read 获取上游实例即可
        Provider<BillRepository>(
          create: (ctx) => BillRepository(ctx.read<AppDatabase>()),
        ),
        Provider<CategoryRepository>(
          create: (ctx) => CategoryRepository(ctx.read<AppDatabase>()),
        ),
        Provider<BudgetRepository>(
          create: (ctx) => BudgetRepository(ctx.read<AppDatabase>()),
        ),
        // 状态层
        ChangeNotifierProvider<BillProvider>(
          create: (ctx) => BillProvider(ctx.read<BillRepository>()),
        ),
        ChangeNotifierProvider<CategoryProvider>(
          create: (ctx) => CategoryProvider(ctx.read<CategoryRepository>()),
        ),
        ChangeNotifierProvider<BudgetProvider>(
          create: (ctx) => BudgetProvider(
            ctx.read<BudgetRepository>(),
            ctx.read<BillRepository>(),
          ),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(prefs),
        ),
      ],
      child: MaterialApp(
        title: '栗子记账',
        debugShowCheckedModeBanner: false,
        // 中文本地化：钟面时间选择器、日期选择器等内置控件显示中文
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
        theme: AppTheme.light,
        home: const MainPage(),
      ),
    );
  }
}
