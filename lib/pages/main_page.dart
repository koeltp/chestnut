import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/show_toast.dart';
import 'add_bill/add_bill_page.dart';
import 'budget/budget_page.dart';
import 'home/home_page.dart';
import 'settings/settings_page.dart';
import 'stats/stats_page.dart';

/// 主框架：底部导航 + 中央记账按钮
///
/// 使用 IndexedStack 保持四个页面的状态（滚动位置、已选月份等）。
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;

  /// 上次按返回的时间：2 秒内连按两次才真正退出（防误触）
  DateTime? _lastPopAt;

  /// 四个页面 GlobalKey：Tab 同点时各自调 resetToTop
  final _homeKey = GlobalKey<HomePageState>();
  final _statsKey = GlobalKey<StatsPageState>();
  final _budgetKey = GlobalKey<BudgetPageState>();
  final _settingsKey = GlobalKey<SettingsPageState>();

  /// 四个页面（IndexedStack 保持状态）
  late final _pages = <Widget>[
    HomePage(key: _homeKey),
    StatsPage(key: _statsKey),
    BudgetPage(key: _budgetKey),
    SettingsPage(key: _settingsKey),
  ];

  @override
  Widget build(BuildContext context) {
    // 根页面拦截返回：2 秒内连按两次才退出，第一次弹 toast 提示
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        final last = _lastPopAt;
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastPopAt = now;
        showAppToast(context, '再按一次退出');
      },
      child: Scaffold(
        extendBody: false,
        // extendBodyBehindAppBar / extendBody 默认 false，Scaffold body
        // 不会自动避让 centerDocked FAB 的 notch 凹陷区。
        // BottomAppBar 高 56 + FAB notch 凹陷约 72 + 余量 = 128，
        // 所有子页面共享这一避让，不再需要每页各算
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: MediaQuery.of(context).padding.copyWith(
                  bottom: MediaQuery.of(context).padding.bottom + 128,
                ),
          ),
          child: IndexedStack(index: _index, children: _pages),
        ),
        // 记账按钮：主题统一栗子棕圆形，突出核心动作
        floatingActionButton: FloatingActionButton(
          onPressed: _openAddBill,
          child: const Icon(Icons.add, size: 28),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: AppColors.card,
          elevation: 8,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                _buildTab(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  label: '明细',
                  tabIndex: 0,
                ),
                _buildTab(
                  icon: Icons.pie_chart_outline,
                  activeIcon: Icons.pie_chart,
                  label: '统计',
                  tabIndex: 1,
                ),
                // 中央为记账按钮预留缺口
                const SizedBox(width: 64),
                _buildTab(
                  icon: Icons.savings_outlined,
                  activeIcon: Icons.savings,
                  label: '预算',
                  tabIndex: 2,
                ),
                _buildTab(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: '我的',
                  tabIndex: 3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 单个底部导航项
  Widget _buildTab({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int tabIndex,
  }) {
    final selected = _index == tabIndex;
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return Expanded(
      child: InkResponse(
        // 同点当前 tab：各页面统一滚回顶 / 重置
        onTap: () {
          if (_index == tabIndex) {
            switch (tabIndex) {
              case 0:
                _homeKey.currentState?.resetToTop();
                break;
              case 1:
                _statsKey.currentState?.resetToTop();
                break;
              case 2:
                _budgetKey.currentState?.resetToTop();
                break;
              case 3:
                _settingsKey.currentState?.resetToTop();
                break;
            }
          } else {
            setState(() => _index = tabIndex);
          }
        },
        radius: 30,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 23),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                height: 1,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开"记一笔"页面
  void _openAddBill() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const AddBillPage()));
  }
}
