import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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

  static const _pages = <Widget>[
    HomePage(),
    StatsPage(),
    BudgetPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              _buildTab(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, label: '明细', tabIndex: 0),
              _buildTab(icon: Icons.pie_chart_outline, activeIcon: Icons.pie_chart, label: '统计', tabIndex: 1),
              // 中央为记账按钮预留缺口
              const SizedBox(width: 64),
              _buildTab(icon: Icons.savings_outlined, activeIcon: Icons.savings, label: '预算', tabIndex: 2),
              _buildTab(icon: Icons.person_outline, activeIcon: Icons.person, label: '我的', tabIndex: 3),
            ],
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
        onTap: () => setState(() => _index = tabIndex),
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddBillPage()),
    );
  }
}
