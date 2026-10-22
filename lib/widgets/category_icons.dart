import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 文字图标的约定 codePoint：0 不与任何真实 Material 图标冲突，
/// 数据库 iconCode 存 0 即为"文字图标"（显示名称首字），无需加列迁移
const int kTextIconCode = 0;

/// 分类图标库（钱迹式）：全应用分类图标的唯一来源
///
/// 码点存库、运行时读取，直接构造 IconData 会破坏 release 的图标
/// 摇树优化（Target aot_android_asset_bundle failed），因此统一通过
/// [categoryIconByCode] 查预构造映射表取 const 图标实例。
typedef CategoryIconItem = (IconData, String);

/// 图标库分组：按使用场景分组，与钱迹"分类图标"左侧组列一致
class CategoryIconGroup {
  const CategoryIconGroup(this.name, this.icons);
  final String name;
  final List<CategoryIconItem> icons;
}

/// 钱迹式图标库：左侧分组切换，右侧 4 列图标网格，支持按名称搜索
const kCategoryIconGroups = <CategoryIconGroup>[
  CategoryIconGroup('收入', [
    (Icons.work, '工资'),
    (Icons.emoji_events, '奖金'),
    (Icons.trending_up, '提成'),
    (Icons.savings, '公积金'),
    (Icons.pie_chart, '分红'),
    (Icons.school, '奖学金'),
    (Icons.card_giftcard, '收红包'),
    // 压岁钱本质是钱，用钱符号图标；礼盒(redeem)只留给人情组"礼物"，
    // 避免同图标在两组叫不同名字（点击自动填名时产生歧义）
    (Icons.currency_yen, '压岁钱'),
    (Icons.bolt, '外快'),
    (Icons.recycling, '二手置换'),
    (Icons.account_balance, '退税'),
    (Icons.more_horiz, '其它收益'),
  ]),
  CategoryIconGroup('餐饮', [
    (Icons.restaurant, '三餐'),
    (Icons.delivery_dining, '外卖'),
    (Icons.shopping_basket, '买菜'),
    (Icons.eco, '水果'),
    (Icons.free_breakfast, '早餐'),
    (Icons.rice_bowl, '午餐'),
    (Icons.ramen_dining, '晚餐'),
    (Icons.dinner_dining, '下馆子'),
    (Icons.lunch_dining, '快餐'),
    (Icons.local_cafe, '咖啡'),
    (Icons.emoji_food_beverage, '奶茶'),
    (Icons.local_drink, '饮料'),
    (Icons.icecream, '零食'),
    (Icons.bakery_dining, '烘焙'),
  ]),
  CategoryIconGroup('交通', [
    (Icons.local_taxi, '打车'),
    (Icons.commute, '顺风车'),
    (Icons.directions_bus, '公交'),
    (Icons.directions_subway, '地铁'),
    (Icons.local_gas_station, '加油'),
    (Icons.ev_station, '充电'),
    (Icons.local_parking, '停车'),
    (Icons.train, '火车'),
    (Icons.flight, '飞机'),
    (Icons.two_wheeler, '电动车'),
    (Icons.pedal_bike, '单车'),
    (Icons.directions_boat, '轮船'),
    // 汽车（购车款/配件/改装）：汽车资产相关，置于养护类条目之前
    (Icons.directions_car, '汽车'),
    (Icons.build_circle, '保养'),
    (Icons.car_repair, '修车'),
    (Icons.local_car_wash, '洗车'),
    (Icons.toll, '高速费'),
    (Icons.gavel, '违章罚款'),
    (Icons.verified_user, '汽车保险'),
  ]),
  CategoryIconGroup('住房', [
    (Icons.home, '房租'),
    (Icons.real_estate_agent, '房贷'),
    (Icons.home_work, '物业'),
    (Icons.bolt, '电费'),
    (Icons.water_drop, '水费'),
    (Icons.local_fire_department, '天燃气'),
    (Icons.construction, '装修'),
    (Icons.build, '维修'),
    (Icons.cleaning_services, '保洁'),
    (Icons.kitchen, '家电'),
    (Icons.chair, '家居'),
  ]),
  CategoryIconGroup('日常', [
    (Icons.content_cut, '理发'),
    (Icons.smartphone, '话费'),
    (Icons.wifi, '网费'),
    (Icons.local_shipping, '快递'),
    (Icons.subscriptions, '会员订阅'),
    (Icons.local_laundry_service, '洗衣'),
    (Icons.print, '打印复印'),
    (Icons.vpn_key, '配钥匙'),
    (Icons.security, '保险'),
    (Icons.wb_sunny, '日常'),
  ]),
  CategoryIconGroup('购物', [
    (Icons.shopping_cart, '购物'),
    (Icons.shopping_bag, '日用品'),
    (Icons.checkroom, '服饰'),
    (Icons.face_retouching_natural, '美妆'),
    (Icons.devices, '数码'),
    (Icons.tv, '电器'),
    (Icons.backpack, '箱包'),
    (Icons.watch, '饰品'),
  ]),
  CategoryIconGroup('医疗', [
    (Icons.local_hospital, '门诊'),
    (Icons.medication, '药品'),
    (Icons.medical_services, '医疗'),
    (Icons.health_and_safety, '体检'),
    (Icons.vaccines, '疫苗'),
    (Icons.hearing, '配镜'),
  ]),
  CategoryIconGroup('教育', [
    (Icons.school, '学费'),
    (Icons.menu_book, '书本'),
    (Icons.cast_for_education, '培训'),
    (Icons.edit, '文具'),
    (Icons.language, '网课'),
    (Icons.science, '实验'),
  ]),
  CategoryIconGroup('娱乐', [
    (Icons.theaters, '电影'),
    (Icons.sports_esports, '游戏'),
    (Icons.theater_comedy, '演出'),
    (Icons.attractions, '景点'),
    (Icons.luggage, '旅行'),
    (Icons.hotel, '住宿'),
    (Icons.music_note, 'KTV'),
    (Icons.local_bar, '酒吧'),
  ]),
  CategoryIconGroup('宠物', [
    (Icons.pets, '宠物'),
    (Icons.cruelty_free, '猫'),
    (Icons.flutter_dash, '鸟'),
    (Icons.set_meal, '鱼'),
    (Icons.grain, '宠物粮'),
    (Icons.bathtub, '宠物美容'),
    (Icons.monitor_heart, '宠物医疗'),
  ]),
  CategoryIconGroup('运动', [
    (Icons.fitness_center, '健身'),
    (Icons.directions_run, '跑步'),
    (Icons.pool, '游泳'),
    (Icons.directions_bike, '骑行'),
    (Icons.sports_basketball, '篮球'),
    (Icons.sports_soccer, '足球'),
    (Icons.sports_tennis, '羽毛球'),
    (Icons.sports_volleyball, '排球'),
    (Icons.self_improvement, '瑜伽'),
    (Icons.downhill_skiing, '滑雪'),
  ]),
  CategoryIconGroup('兴趣', [
    (Icons.auto_stories, '阅读'),
    (Icons.photo_camera, '摄影'),
    (Icons.piano, '乐器'),
    (Icons.local_florist, '养花'),
    (Icons.phishing, '钓鱼'),
    (Icons.palette, '绘画'),
    (Icons.handyman, '手工'),
    (Icons.bookmarks, '收藏'),
  ]),
  CategoryIconGroup('人情', [
    (Icons.volunteer_activism, '孝敬'),
    (Icons.elderly, '赡养'),
    (Icons.favorite, '结婚'),
    (Icons.child_care, '育儿'),
    (Icons.redeem, '礼物'),
    (Icons.restaurant_menu, '请客'),
    (Icons.connect_without_contact, '份子钱'),
  ]),
  CategoryIconGroup('理财', [
    (Icons.account_balance_wallet, '储蓄'),
    (Icons.candlestick_chart, '股票'),
    (Icons.currency_yen, '基金'),
    (Icons.currency_exchange, '换汇'),
    (Icons.credit_score, '信用'),
    (Icons.request_quote, '账单'),
    (Icons.payments, '现金'),
    (Icons.money_off, '手续费'),
    (Icons.savings, '利息'),
    (Icons.credit_card, '信用卡'),
  ]),
  // 科技组：程序员/站长典型开销（域名、服务器等为用户举例，
  // 按独立开发者场景补全）；插在"其他"之前，兜底组保持收尾
  CategoryIconGroup('科技', [
    (Icons.public, '域名'),
    (Icons.dns, '服务器'),
    (Icons.cloud, '云服务'),
    (Icons.storage, '数据库'),
    (Icons.web, '网站'),
    (Icons.https, 'SSL证书'),
    (Icons.fact_check, '备案'),
    (Icons.speed, 'CDN'),
    (Icons.api, 'API'),
    (Icons.code, '代码'),
    (Icons.terminal, '终端'),
    (Icons.smart_toy, 'AI'),
  ]),
  CategoryIconGroup('其他', [
    (Icons.category, '杂项'),
    (Icons.more_horiz, '其它'),
    (Icons.help_outline, '待分类'),
  ]),
];

/// 可选色板：与标签共用 [AppColors.tagPalette]（20 色同一常量），
/// 既用于图标固定映射，也用于手动选色弹层
const List<int> kCategoryColorChoices = AppColors.tagPalette;

/// 全部图标的扁平列表（按分组顺序）
final List<CategoryIconItem> kCategoryIcons = [
  for (final g in kCategoryIconGroups) ...g.icons,
];

/// 图标 → 分类色固定映射：按全表顺序循环取色。
/// 同一图标颜色恒定，图标网格因此五彩缤纷，且保存后的
/// 分类色与图标网格/预览显示一致。
final Map<int, int> kCategoryIconColorMap = {
  for (final (i, item) in kCategoryIcons.indexed)
    item.$1.codePoint: kCategoryColorChoices[i % kCategoryColorChoices.length],
};

/// 码点 → 图标映射：全表 icons 均为 const 实例，摇树优化据此裁剪字体
final Map<int, IconData> _iconDataByCode = {
  for (final (icon, _) in kCategoryIcons) icon.codePoint: icon,
};

/// 图标码点查表：文字图标（[kTextIconCode]）返回 null 由调用方显示
/// 名称首字；库中不存在的码点（脏数据）兜底"其它"图标
IconData? categoryIconByCode(int code) =>
    code == kTextIconCode ? null : (_iconDataByCode[code] ?? Icons.more_horiz);
