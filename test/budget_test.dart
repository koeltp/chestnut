import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/budget_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 预算数据层回归测试：预算写入（insert/upsert）与 watch 流推送链路
///
/// 背景：用户反馈"预算修改后保存没有反应"，本测试验证仓储层
/// 写入与 drift 表更新通知是否正常。
void main() {
  late AppDatabase db;
  late BudgetRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BudgetRepository(db);
    // 触发建库（含迁移与预置分类）
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  test('首次设置预算：从无到有写入成功', () async {
    final stream = repo.watchBudget('2026-10');
    expect(await stream.first, isNull);

    await repo.setBudget('2026-10', 50000);
    expect((await stream.first)?.amountCents, 50000);
  });

  test('再次修改预算：upsert 更新覆盖旧值', () async {
    await repo.setBudget('2026-10', 50000);
    final stream = repo.watchBudget('2026-10');
    expect((await stream.first)?.amountCents, 50000);

    await repo.setBudget('2026-10', 60000);
    expect((await stream.first)?.amountCents, 60000);
  });

  test('先订阅后写入：drift 表更新通知能推送到流', () async {
    final stream = repo.watchBudget('2026-10');
    // 先挂起等待 50000 的订阅，再写入——验证表更新通知触发重查
    final pending = stream.firstWhere((b) => b?.amountCents == 50000);
    await repo.setBudget('2026-10', 50000);
    expect((await pending)?.amountCents, 50000);
  });
}
