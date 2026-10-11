import 'package:chestnut/data/database.dart';
import 'package:chestnut/data/repositories/asset_repository.dart';
import 'package:chestnut/providers/asset_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AssetProvider 的本地偏好持久化：上次记账关联账户的记忆/清除
void main() {
  late AppDatabase db;
  late AssetProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 触发建库（含迁移与预置分类）
    await db.customSelect('SELECT 1').get();
    final prefs = await SharedPreferences.getInstance();
    provider = AssetProvider(AssetRepository(db), prefs);
  });

  tearDown(() => db.close());

  test('上次记账账户：未记录过返回 null，写入后可读，传 null 清除', () async {
    expect(provider.lastBillAssetId, isNull);

    await provider.setLastBillAssetId(42);
    expect(provider.lastBillAssetId, 42);

    // 记一笔选了"不关联"保存：记忆清除，下次进页不再默认带账户
    await provider.setLastBillAssetId(null);
    expect(provider.lastBillAssetId, isNull);
  });
}
