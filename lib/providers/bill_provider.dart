import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositories/bill_image_repository.dart';
import '../data/repositories/bill_repository.dart';
import '../models/enums.dart';
import '../models/summaries.dart';
import '../pages/stats/stats_query.dart';
import 'cloud_storage_provider.dart';

/// 账单状态管理
///
/// 首页的状态中枢：维护当前查看月份与查看模式（按月/按年/全部），
/// 并提供账单/汇总两条数据流。流由 UI 层的 StreamBuilder 订阅——
/// 月份/模式切换时 StreamBuilder 会自动取消旧订阅并建立新订阅，
/// 无需在这里手动管理监听器生命周期。
class BillProvider extends ChangeNotifier {
  BillProvider(this._repo, this._imageRepo, this._cloud);

  final BillRepository _repo;

  final BillImageRepository _imageRepo;

  /// 删除账单时按此配置级联清理云端图片对象
  final CloudStorageProvider _cloud;

  /// 当前查看的月份（按月/按年模式的基准；按年只取其年份）
  DateTime _selectedMonth = DateTime.now();
  DateTime get selectedMonth => _selectedMonth;

  /// 当前查看模式（钱迹式"显示方式"：按月/按年/全部）
  HomePeriod _period = HomePeriod.month;
  HomePeriod get period => _period;

  /// 指定月份收支汇总流
  Stream<MonthSummary> summaryStream(DateTime month) =>
      _repo.watchMonthSummary(month);

  /// 首页收支汇总流：按当前查看模式分流（月/年/全部）
  Stream<MonthSummary> homeSummaryStream() => switch (_period) {
    HomePeriod.month => _repo.watchMonthSummary(_selectedMonth),
    HomePeriod.year => _repo.watchYearSummary(_selectedMonth.year),
    HomePeriod.all => _repo.watchAllSummary(),
  };

  /// 切换月份
  void changeMonth(DateTime month) {
    if (month.year == _selectedMonth.year &&
        month.month == _selectedMonth.month) {
      return;
    }
    _selectedMonth = month;
    notifyListeners();
  }

  /// 切换查看模式（按月/按年/全部）
  void changePeriod(HomePeriod period) {
    if (_period == period) return;
    _period = period;
    notifyListeners();
  }

  /// 重置到默认视图（Tab 同点已在顶时用）：按月 + 当月
  void resetToDefault() {
    final now = DateTime.now();
    if (_period != HomePeriod.month ||
        _selectedMonth.year != now.year ||
        _selectedMonth.month != now.month) {
      _period = HomePeriod.month;
      _selectedMonth = now;
      notifyListeners();
    }
  }

  /// 统计页专用查询：按 StatsQuery 全部条件一次性查（数据库层过滤）
  Stream<List<Bill>> statsQueryStream(StatsQuery q) =>
      _repo.watchBillsByStatsQuery(q);

  /// 新增账单（返回新账单 id，供关联标签等后续操作使用）
  Future<int> addBill(BillsCompanion entry) => _repo.addBill(entry);

  /// 更新账单
  Future<void> updateBill(Bill bill) => _repo.updateBill(bill);

  /// 删除账单：级联清理其全部图片（记录 / 本地文件同步删，云端对象
  /// 异步删、失败留孤儿可接受）。已配置云存储就传客户端——即使开关
  /// 暂时关闭，之前传上去的对象也应一并清理
  Future<void> deleteBill(int id) async {
    await _repo.deleteBill(id);
    await _imageRepo.deleteImagesOfBill(id, client: _cloud.createClient());
  }
}
