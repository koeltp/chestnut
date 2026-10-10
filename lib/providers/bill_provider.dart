import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/repositories/bill_image_repository.dart';
import '../data/repositories/bill_repository.dart';
import '../models/enums.dart';
import '../models/summaries.dart';
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

  /// 指定月份账单流
  ///
  /// 月份由 UI 传入而非内部捕获：StreamBuilder 持有旧流引用，
  /// 若流内部读取 _selectedMonth，切月后仍订阅旧月份导致"点了没反应"。
  Stream<List<Bill>> billsStream(DateTime month) =>
      _repo.watchBillsInMonth(month);

  /// 指定月份收支汇总流
  Stream<MonthSummary> summaryStream(DateTime month) =>
      _repo.watchMonthSummary(month);

  /// 首页账单流：按当前查看模式分流（月/年/全部）。
  /// UI 在 build 中调用，模式或月份变化重建时重新取流。
  Stream<List<Bill>> homeBillsStream() => switch (_period) {
    HomePeriod.month => _repo.watchBillsInMonth(_selectedMonth),
    HomePeriod.year => _repo.watchBillsInYear(_selectedMonth.year),
    HomePeriod.all => _repo.watchAllBills(),
  };

  /// 首页收支汇总流：按当前查看模式分流（月/年/全部）
  Stream<MonthSummary> homeSummaryStream() => switch (_period) {
    HomePeriod.month => _repo.watchMonthSummary(_selectedMonth),
    HomePeriod.year => _repo.watchYearSummary(_selectedMonth.year),
    HomePeriod.all => _repo.watchAllSummary(),
  };

  /// 任意范围账单流（统计页用）：范围由 UI 显式传入而非内部状态，
  /// 避免统计页与首页各自维护范围状态时串流
  Stream<List<Bill>> billsInRangeStream(HomePeriod period, DateTime month) =>
      switch (period) {
        HomePeriod.month => _repo.watchBillsInMonth(month),
        HomePeriod.year => _repo.watchBillsInYear(month.year),
        HomePeriod.all => _repo.watchAllBills(),
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

  /// 某分类（含子分类）账单流：分类统计详情页
  Stream<List<Bill>> categoryBillsStream(int categoryId) =>
      _repo.watchBillsInCategory(categoryId);

  /// 单条账单流（详情弹窗用）：编辑保存后弹窗自动刷新；被删发 null
  Stream<Bill?> watchBillById(int id) => _repo.watchBillById(id);

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
