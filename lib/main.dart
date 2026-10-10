import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/database.dart';
import 'data/repositories/asset_repository.dart';
import 'data/repositories/bill_image_repository.dart';
import 'data/repositories/bill_repository.dart';
import 'data/repositories/budget_repository.dart';
import 'data/repositories/category_repository.dart';
import 'data/repositories/debt_note_repository.dart';
import 'data/repositories/tag_repository.dart';
import 'pages/db_error_page.dart';
import 'pages/lock/lock_screen.dart';
import 'pages/main_page.dart';
import 'pages/privacy/privacy_consent_page.dart';
import 'providers/asset_provider.dart';
import 'providers/bill_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/category_provider.dart';
import 'providers/cloud_storage_provider.dart';
import 'providers/debt_note_provider.dart';
import 'providers/lock_provider.dart';
import 'providers/settings_provider.dart';
import 'services/backup_service.dart';
import 'theme/app_theme.dart';

/// 隐私政策同意标记：未同意前不初始化高德等第三方 SDK、不进入主界面
const String kPrivacyAgreedKey = 'privacy_policy_agreed';

/// 向高德 SDK 声明隐私状态（政策已包含、已弹窗、已同意）。
/// 必须在任何地图组件创建前调用，否则地图白屏且不合规。
void _declareAmapPrivacyAgreed() {
  AMapInitializer.updatePrivacyAgree(
    const AMapPrivacyStatement(hasContains: true, hasShow: true, hasAgree: true),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 固定竖屏，记账场景无横屏需求
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // 启动早期执行待定数据恢复：必须在数据库首次打开前完成文件替换
  await BackupService().restoreIfNeeded();
  // 清理上次会话遗留的导出临时文件（分享时微信异步读取，不能当场删）
  await BackupService().cleanupExportTemp();
  // 预加载设置存储，UI 各处可同步读取开关状态
  final prefs = await SharedPreferences.getInstance();
  // 已同意过隐私政策：启动即完成高德 SDK 合规声明（首启由同意页触发）
  if (prefs.getBool(kPrivacyAgreedKey) ?? false) {
    _declareAmapPrivacyAgreed();
  }
  // 只读健康探测：主库损坏时走兜底页，避免白屏或崩溃
  final dbHealthy = await BackupService().checkDatabaseHealth();
  // 每日自动备份：用户开启开关后每天首次启动执行（库不健康时跳过）
  if (dbHealthy) await BackupService().autoBackupIfNeeded(prefs);
  // 清理图片暂存目录：上次会话选了图但没保存的残留文件
  await BillImageRepository.cleanupStaging();
  // 清理借条照片暂存目录：同理（借据照片选了没保存的残留）
  await DebtNoteRepository.cleanupStaging();
  runApp(ChestnutApp(prefs: prefs, dbHealthy: dbHealthy));
}

/// 应用根组件：主库健康时进入依赖注入与主页，损坏时展示兜底页
class ChestnutApp extends StatelessWidget {
  const ChestnutApp({super.key, required this.prefs, this.dbHealthy = true});

  final SharedPreferences prefs;

  /// 主库健康探测结果；false 时展示数据库错误兜底页，
  /// 不注入数据库依赖，避免打开损坏库引发更严重的错误
  final bool dbHealthy;

  @override
  Widget build(BuildContext context) {
    return dbHealthy
        ? _ProvidersApp(prefs: prefs)
        : const _MaterialShell(home: DatabaseErrorPage());
  }
}

/// MaterialApp 公共壳：中文本地化 + 主题，主页与兜底页两处复用
class _MaterialShell extends StatelessWidget {
  const _MaterialShell({required this.home, this.lockGate = false});

  final Widget home;

  /// 是否注入密码锁遮罩：仅依赖注入壳启用；
  /// 兜底页无 provider 且数据库已损坏，锁屏无意义
  final bool lockGate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: home,
      // 锁定遮罩挂在 builder 上：位于 Navigator 之上，任何页面都会被盖住
      builder: lockGate
          ? (context, child) =>
                _LockGate(child: child ?? const SizedBox.shrink())
          : null,
    );
  }
}

/// 密码锁遮罩：启用密码且处于锁定态时全屏盖锁屏页；
/// Stack 保留下层 Navigator，解锁瞬间无需整树重建
class _LockGate extends StatelessWidget {
  const _LockGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final needLock = context.watch<SettingsProvider>().passcodeEnabled &&
        context.watch<LockProvider>().locked;
    return Stack(
      children: [
        child,
        if (needLock) const Positioned.fill(child: LockScreen()),
      ],
    );
  }
}

/// 依赖注入容器：数据库 → 仓储 → Provider → 主页
///
/// MultiProvider 必须包在 MaterialApp 之上：push 出的二级页面是
/// Navigator 里与 home 平级的兄弟 OverlayEntry，provider 若注入在
/// home 内部，二级页面沿树向上找不到，会报 Provider not found。
class _ProvidersApp extends StatelessWidget {
  const _ProvidersApp({required this.prefs});

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
        Provider<TagRepository>(
          create: (ctx) => TagRepository(ctx.read<AppDatabase>()),
        ),
        Provider<BillImageRepository>(
          create: (ctx) => BillImageRepository(ctx.read<AppDatabase>()),
        ),
        Provider<AssetRepository>(
          create: (ctx) => AssetRepository(ctx.read<AppDatabase>()),
        ),
        Provider<DebtNoteRepository>(
          create: (ctx) => DebtNoteRepository(ctx.read<AppDatabase>()),
        ),
        // 图片云存储配置：未配置/未启用时 App 内不出现任何图片入口。
        // 必须注册在 BillProvider 之前——MultiProvider 列表前面的包住
        // 后面的（祖先方向），BillProvider 的 create 要 read 它
        ChangeNotifierProvider<CloudStorageProvider>(
          create: (_) => CloudStorageProvider(prefs),
        ),
        // 状态层
        ChangeNotifierProvider<BillProvider>(
          create: (ctx) => BillProvider(
            ctx.read<BillRepository>(),
            ctx.read<BillImageRepository>(),
            ctx.read<CloudStorageProvider>(),
          ),
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
        ChangeNotifierProvider<AssetProvider>(
          create: (ctx) => AssetProvider(ctx.read<AssetRepository>()),
        ),
        ChangeNotifierProvider<DebtNoteProvider>(
          create: (ctx) => DebtNoteProvider(ctx.read<DebtNoteRepository>()),
        ),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(prefs),
        ),
        // 密码锁：读取设置开关与超时配置，冷启动即决定是否进入锁定态
        ChangeNotifierProvider<LockProvider>(
          create: (ctx) => LockProvider(ctx.read<SettingsProvider>()),
        ),
      ],
      child: _MaterialShell(home: _StartupGate(prefs: prefs), lockGate: true),
    );
  }
}

/// 启动门：首次启动未同意隐私政策时只显示同意页（MainPage 不构建，
/// 因此首页的更新检测等网络行为在同意前均不会发生）；同意后切换进主页
class _StartupGate extends StatefulWidget {
  const _StartupGate({required this.prefs});

  final SharedPreferences prefs;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late bool _agreed =
      widget.prefs.getBool(kPrivacyAgreedKey) ?? false;

  @override
  void initState() {
    super.initState();
    // 启动静默补传（仅同意隐私政策后，与其他联网行为同口径）：
    // 扫描 uploadState != done 的图片记录逐张补传，失败留在下次启动重试
    if (_agreed) unawaited(_uploadPendingImages());
  }

  /// 延迟触发启动补传：避开启动高峰，也让弱网下首屏请求优先。
  /// 未配置/未启用云存储时 createClient 为 null，无任何图片网络行为
  Future<void> _uploadPendingImages() async {
    // 捕获依赖后再进入 await：补传是异步任务，不能依赖 async gap 后的 context
    final repo = context.read<BillImageRepository>();
    final debtRepo = context.read<DebtNoteRepository>();
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    final client = context.read<CloudStorageProvider>().createClient();
    if (client == null) return;
    await repo.uploadPending(client);
    // 借据照片同口径补传（失败的单张由下次启动继续重试）
    await debtRepo.uploadPending(client);
  }

  Future<void> _agree() async {
    await widget.prefs.setBool(kPrivacyAgreedKey, true);
    _declareAmapPrivacyAgreed();
    if (mounted) setState(() => _agreed = true);
  }

  @override
  Widget build(BuildContext context) {
    return _agreed
        ? const MainPage()
        : PrivacyConsentPage(onAgree: _agree);
  }
}
