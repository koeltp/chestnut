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
        // body 本来就结束在底部导航栏上沿，各页面的 SafeArea 只该吃系统的
        // 底部安全区。之前在这里把 padding.bottom 额外加了 128（想给 FAB
        // 缺口让位），结果所有页面都被 SafeArea 当成系统安全区吃掉，底部
        // 凭空多出一大块空白、内容被顶起——FAB 上沿只比导航栏高半个按钮，
        // 各页自己的底部留白足够，不需要全局垫高
        body: IndexedStack(index: _index, children: _pages),
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
          // 底部安全区只在这里处理一次：全面屏机型的系统手势条/三键栏会画在
          // 应用之上，导航栏不垫 inset，标签就会落进系统手势区。页面各自
          // 不再吃底部安全区（统一 SafeArea(bottom: false)）
          child: SafeArea(
            top: false,
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
