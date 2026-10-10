import 'package:flutter/material.dart';

import 'enums.dart';

/// 单个资产分类定义：名称 + 图标 + 主题色
class AssetCategoryDef {
  const AssetCategoryDef(this.name, this.icon, this.color);

  /// 分类名（持久化到 assets.category 的是该名称）
  final String name;

  /// 列表/选择器使用的图标
  final IconData icon;

  /// 彩色圆图标的底色（0xAARRGGBB）
  final int color;
}

/// 资产组定义：钱迹式分组（组名 + 组内分类）
///
/// 组是纯展示概念（不落库）：主界面按组聚合展示，点击进组明细页；
/// [kind] 由组内分类统一决定，决定该组金额在净值中的正负方向。
class AssetGroupDef {
  const AssetGroupDef(this.name, this.kind, this.categories);

  /// 组名，如"资金账户"
  final String name;

  /// 组内资产的类型（同组内一致）
  final AssetKind kind;

  /// 组内分类列表（选择器按组分节展示）
  final List<AssetCategoryDef> categories;

  /// 组图标：取首个分类图标
  IconData get icon => categories.first.icon;

  /// 组主题色：取首个分类色
  int get color => categories.first.color;
}

/// 钱迹式资产分类体系（预设固定集，不做分类管理）
///
/// 六个组：资金账户 / 信用卡账户 / 充值账户 / 投资理财账户 / 其它资产
/// / 债务。持久化只存分类名——后续若调整图标/颜色不影响旧数据；
/// 名称即分类主键，新增分类时不可与旧名冲突。
abstract final class AssetGroups {
  // ---------- 资金账户（资产） ----------

  static const fund = AssetGroupDef('资金账户', AssetKind.asset, [
    AssetCategoryDef('现金', Icons.payments, 0xFF4CAF50),
    AssetCategoryDef('微信', Icons.chat_bubble, 0xFF07C160),
    AssetCategoryDef('微信零钱通', Icons.savings, 0xFF07C160),
    AssetCategoryDef('支付宝', Icons.account_balance_wallet, 0xFF1677FF),
    AssetCategoryDef('余额宝', Icons.trending_up, 0xFF1677FF),
    AssetCategoryDef('余利宝', Icons.show_chart, 0xFF1677FF),
    AssetCategoryDef('小荷包', Icons.inventory_2, 0xFF1677FF),
    AssetCategoryDef('云闪付', Icons.credit_card, 0xFFD32F2F),
    AssetCategoryDef('银行卡', Icons.account_balance, 0xFF5C6BC0),
    AssetCategoryDef('公积金', Icons.home_work, 0xFF26A69A),
    AssetCategoryDef('QQ钱包', Icons.forum, 0xFF12B7F5),
    AssetCategoryDef('京东金融', Icons.shopping_cart, 0xFFE93B3D),
    AssetCategoryDef('医保', Icons.local_hospital, 0xFFEF5350),
    AssetCategoryDef('数字人民币', Icons.currency_yuan, 0xFFE65100),
    AssetCategoryDef('华为钱包', Icons.smartphone, 0xFFEF6C00),
    AssetCategoryDef('多多钱包', Icons.shopping_bag, 0xFFE02E24),
    AssetCategoryDef('Paypal', Icons.public, 0xFF1565C0),
    AssetCategoryDef('其它', Icons.more_horiz, 0xFF9E9E9E),
  ]);

  // ---------- 信用卡账户（负债） ----------

  static const credit = AssetGroupDef('信用卡账户', AssetKind.liability, [
    AssetCategoryDef('信用卡', Icons.credit_score, 0xFFFF7043),
    AssetCategoryDef('花呗', Icons.account_balance_wallet, 0xFF1677FF),
    AssetCategoryDef('借呗', Icons.request_quote, 0xFF1296DB),
    AssetCategoryDef('京东白条', Icons.receipt_long, 0xFFE93B3D),
    AssetCategoryDef('美团月付', Icons.storefront, 0xFFF57C00),
    AssetCategoryDef('抖音月付', Icons.music_note, 0xFFFE2C55),
    AssetCategoryDef('微信分付', Icons.chat_bubble, 0xFF07C160),
    AssetCategoryDef('其它信用卡', Icons.credit_card, 0xFFFF7043),
  ]);

  // ---------- 充值账户（资产） ----------

  static const prepaid = AssetGroupDef('充值账户', AssetKind.asset, [
    AssetCategoryDef('话费', Icons.phone_iphone, 0xFF4CAF50),
    AssetCategoryDef('水电', Icons.water_drop, 0xFF29B6F6),
    AssetCategoryDef('饭卡', Icons.restaurant, 0xFFFF7043),
    AssetCategoryDef('押金', Icons.assignment_turned_in, 0xFF8D6E63),
    AssetCategoryDef('公交卡', Icons.directions_bus, 0xFF66BB6A),
    AssetCategoryDef('会员卡', Icons.card_membership, 0xFFAB47BC),
    AssetCategoryDef('加油卡', Icons.local_gas_station, 0xFFEF5350),
    AssetCategoryDef('石化钱包', Icons.local_shipping, 0xFFEF6C00),
    AssetCategoryDef('Apple', Icons.phone_iphone, 0xFF616161),
    AssetCategoryDef('其它充值卡', Icons.more_horiz, 0xFF9E9E9E),
  ]);

  // ---------- 投资理财账户（资产） ----------

  static const invest = AssetGroupDef('投资理财账户', AssetKind.asset, [
    AssetCategoryDef('股票', Icons.candlestick_chart, 0xFFEC407A),
    AssetCategoryDef('基金', Icons.pie_chart, 0xFF42A5F5),
    AssetCategoryDef('黄金', Icons.paid, 0xFFFFB300),
    AssetCategoryDef('外汇', Icons.currency_exchange, 0xFF26C6DA),
    AssetCategoryDef('期货', Icons.stacked_line_chart, 0xFF7E57C2),
    AssetCategoryDef('债券', Icons.description, 0xFF66BB6A),
    AssetCategoryDef('固定收益', Icons.account_balance, 0xFF5C6BC0),
    AssetCategoryDef('加密货币', Icons.currency_bitcoin, 0xFFFF7043),
    AssetCategoryDef('其它理财', Icons.trending_up, 0xFF26A69A),
  ]);

  // ---------- 其它资产（资产，承接房产/车辆等大件） ----------

  static const otherAsset = AssetGroupDef('其它资产', AssetKind.asset, [
    AssetCategoryDef('房产', Icons.home, 0xFF8D6E63),
    AssetCategoryDef('车辆', Icons.directions_car, 0xFF42A5F5),
    AssetCategoryDef('其它', Icons.more_horiz, 0xFF9E9E9E),
  ]);

  // ---------- 债务（负债，承接房贷/车贷；借出借入走借条） ----------

  static const debt = AssetGroupDef('债务', AssetKind.liability, [
    // 借出/借入是借条入口而非资产分类：选中后进借条编辑页，
    // 主界面的总借出/借入卡在添加第一条借条后才出现
    AssetCategoryDef('借出', Icons.arrow_upward, 0xFFEF5350),
    AssetCategoryDef('借入', Icons.arrow_downward, 0xFF66BB6A),
    AssetCategoryDef('房贷', Icons.real_estate_agent, 0xFFEF5350),
    AssetCategoryDef('车贷', Icons.directions_car, 0xFFEF5350),
    AssetCategoryDef('其它负债', Icons.handshake, 0xFFEF5350),
  ]);

  /// 全部组（主界面组列表与分类选择器的展示顺序）
  static const List<AssetGroupDef> all = [
    fund,
    credit,
    prepaid,
    invest,
    otherAsset,
    debt,
  ];

  /// 按分类名查定义（未命中返回 null：旧数据/异常数据兜底用）
  static AssetCategoryDef? categoryOf(String name) {
    for (final group in all) {
      for (final def in group.categories) {
        if (def.name == name) return def;
      }
    }
    return null;
  }

  /// 按分类名取图标（未命中兜底"其它"图标，防止异常数据崩溃）
  static IconData iconOf(String name) =>
      categoryOf(name)?.icon ?? Icons.more_horiz;

  /// 按分类名取主题色（未命中兜底灰色）
  static Color colorOf(String name) =>
      Color(categoryOf(name)?.color ?? 0xFF9E9E9E);

  /// 按分类名取所属组（未命中兜底资金账户组）
  static AssetGroupDef groupOf(String name) {
    for (final group in all) {
      for (final def in group.categories) {
        if (def.name == name) return group;
      }
    }
    return fund;
  }

  /// 分类名 → 净值正负方向（未命中按资产处理）
  static AssetKind kindOfCategory(String name) => groupOf(name).kind;

  // ---------- 信用卡银行列表 ----------

  /// 可选银行（选"信用卡"分类时二次选择，账户名默认取银行名）
  static const List<String> banks = [
    '中国银行',
    '工商银行',
    '农业银行',
    '建设银行',
    '交通银行',
    '招商银行',
    '邮政储蓄银行',
    '浦发银行',
    '中信银行',
    '兴业银行',
    '民生银行',
    '光大银行',
    '平安银行',
    '华夏银行',
    '广发银行',
    '浙商银行',
    '北京银行',
    '上海银行',
    '江苏银行',
    '宁波银行',
    '南京银行',
    '杭州银行',
    '成都银行',
    '重庆银行',
    '微众银行',
    '网商银行',
    '其它银行',
  ];
}
