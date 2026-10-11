/// 所属机构名单（银行卡/信用卡的「所属银行」与投资理财组的
/// 「券商/平台」选择器、数据库迁移回填共用）
///
/// 独立成纯 Dart 文件：数据层迁移需要引用该名单做旧数据回填，
/// 若放在带 Material 依赖的 asset_category.dart 会把 Flutter 依赖
/// 拖进数据库层。新增机构时改这一处即可，选择器与回填口径自动一致。
///
/// SVG logo 接入：把白色剪影 SVG 放到 assets/images/brands/ 下
/// （下载时颜色填 #FFFFFF），再给对应 [InstitutionDef] 补 svg 路径，
/// 选择器行首自动从首字圆标切换为品牌 logo；未提供 logo 的机构
/// 永远回落首字圆标，不会因缺图不可用。
library;

/// 单个机构定义：名称 + 可选品牌 logo
class InstitutionDef {
  const InstitutionDef(this.name, {this.svg});

  /// 机构全称（如"招商银行"、"华泰证券"），即落库值
  final String name;

  /// 品牌 logo 的 SVG 资源路径（assets/images/brands/ 下）；null 用首字圆标。
  /// 图形按下载的原色直接渲染（统一衬中性深灰圆底保证可见，不改色）
  final String? svg;
}

/// 机构分组（选择器弹层的分段标题 + 名单）
class InstitutionSection {
  const InstitutionSection(this.label, this.items);

  final String label;
  final List<InstitutionDef> items;
}

/// 银行名单：信用卡/储蓄卡所属银行（含兜底「其它银行」）
const List<InstitutionDef> _banks = [
  InstitutionDef('中国银行', svg: 'assets/images/brands/zhongguo_yinhang.svg'),
  InstitutionDef('工商银行', svg: 'assets/images/brands/gongshang_yinhang.svg'),
  InstitutionDef('农业银行', svg: 'assets/images/brands/nongye_yinhang.svg'),
  InstitutionDef('建设银行', svg: 'assets/images/brands/jianshe_yinhang.svg'),
  InstitutionDef('交通银行', svg: 'assets/images/brands/jiaotong_yinhang.svg'),
  InstitutionDef('招商银行', svg: 'assets/images/brands/zhaoshang_yinhang.svg'),
  InstitutionDef('邮政储蓄银行', svg: 'assets/images/brands/youzheng_yinhang.svg'),
  InstitutionDef('浦发银行', svg: 'assets/images/brands/pufa_yinhang.svg'),
  InstitutionDef('中信银行', svg: 'assets/images/brands/zhongxin_yinhang.svg'),
  InstitutionDef('兴业银行', svg: 'assets/images/brands/xingye_yinhang.svg'),
  InstitutionDef('民生银行', svg: 'assets/images/brands/minsheng_yinhang.svg'),
  InstitutionDef('光大银行', svg: 'assets/images/brands/guangda_yinhang.svg'),
  InstitutionDef('平安银行', svg: 'assets/images/brands/pingan_yinhang.svg'),
  InstitutionDef('华夏银行', svg: 'assets/images/brands/huaxia_yinhang.svg'),
  InstitutionDef('广发银行', svg: 'assets/images/brands/guangfa_yinhang.svg'),
  InstitutionDef('浙商银行', svg: 'assets/images/brands/zheshang_yinhang.svg'),
  InstitutionDef('北京银行', svg: 'assets/images/brands/beijing_yinhang.svg'),
  InstitutionDef('上海银行', svg: 'assets/images/brands/shanghai_yinhang.svg'),
  InstitutionDef('江苏银行', svg: 'assets/images/brands/jiangsu_yinhang.svg'),
  InstitutionDef('徽商银行', svg: 'assets/images/brands/huishang_yinhang.svg'),
  InstitutionDef('宁波银行', svg: 'assets/images/brands/ningbo_yinhang.svg'),
  InstitutionDef('南京银行', svg: 'assets/images/brands/nanjing_yinhang.svg'),
  InstitutionDef('杭州银行', svg: 'assets/images/brands/hangzhou_yinhang.svg'),
  InstitutionDef('成都银行', svg: 'assets/images/brands/chengdu_yinhang.svg'),
  InstitutionDef('重庆银行', svg: 'assets/images/brands/chongqing_yinhang.svg'),
  InstitutionDef('微众银行', svg: 'assets/images/brands/weizhong_yinhang.svg'),
  InstitutionDef('网商银行', svg: 'assets/images/brands/wangshang_yinhang.svg'),
  InstitutionDef('其它银行'),
];

/// 全部机构分组（选择器弹层按此分段展示）
const List<InstitutionSection> kInstitutionSections = [
  InstitutionSection('银行', _banks),
  InstitutionSection('券商', [
    InstitutionDef('华泰证券', svg: 'assets/images/brands/huatai_zhengquan.svg'),
    InstitutionDef('中信证券', svg: 'assets/images/brands/zhongxin_zhengquan.svg'),
    InstitutionDef('中国银河'),
    InstitutionDef('国泰海通'),
    InstitutionDef('招商证券', svg: 'assets/images/brands/zhaoshang_zhengquan.svg'),
    InstitutionDef('广发证券', svg: 'assets/images/brands/guangfa_zhengquan.svg'),
    InstitutionDef('中信建投', svg: 'assets/images/brands/zhongxin_jiantou.svg'),
    InstitutionDef('中金公司'),
    InstitutionDef('申万宏源'),
    InstitutionDef('东方财富', svg: 'assets/images/brands/dongfang_caifu.svg'),
    InstitutionDef('平安证券', svg: 'assets/images/brands/pingan_zhengquan.svg'),
    InstitutionDef('国信证券', svg: 'assets/images/brands/guoxin_zhengquan.svg'),
    InstitutionDef('光大证券', svg: 'assets/images/brands/guangda_zhengquan.svg'),
    InstitutionDef('兴业证券', svg: 'assets/images/brands/xingye_zhengquan.svg'),
    InstitutionDef('长江证券', svg: 'assets/images/brands/changjiang_zhengquan.svg'),
    InstitutionDef('东莞证券', svg: 'assets/images/brands/dongguan_zhengquan.svg'),
    InstitutionDef('长城证券', svg: 'assets/images/brands/changcheng_zhengquan.svg'),
    InstitutionDef('长桥证券', svg: 'assets/images/brands/changqiao_zhengquan.svg'),
  ]),
  InstitutionSection('基金/理财平台', [
    InstitutionDef('天天基金'),
    InstitutionDef('蚂蚁财富', svg: 'assets/images/brands/ant_fund.svg'),
    InstitutionDef('腾讯理财通'),
    InstitutionDef('京东金融', svg: 'assets/images/brands/jd_baitiao.svg'),
    InstitutionDef('同花顺', svg: 'assets/images/brands/tonghuashun.svg'),
    InstitutionDef('雪球', svg: 'assets/images/brands/xueqiu.svg'),
    InstitutionDef('盈米基金'),
  ]),
  InstitutionSection('其他机构', [
    InstitutionDef('上海黄金交易所'),
    InstitutionDef('币安', svg: 'assets/images/brands/binance.svg'),
    InstitutionDef('OKX'),
  ]),
];

/// 全部机构名扁平名单（数据库迁移回填用：账户名恰好等于机构名才回填）
final List<String> kAllInstitutionNames = [
  for (final s in kInstitutionSections) ...[for (final d in s.items) d.name],
];

/// 机构名 → 定义（选择器查 logo 用）
final Map<String, InstitutionDef> kInstitutionByName = {
  for (final s in kInstitutionSections) for (final d in s.items) d.name: d,
};

/// 机构弹层的分组过滤预设（集合元素对应 [kInstitutionSections] 的 label）：
/// 卡类只看银行组；投资理财组隐藏银行组——券商/平台/其他机构可跨组选
/// （股票账户开在同花顺、黄金存上海金交所都能选到），券商组排最前天然即首屏
const Set<String> kBankSectionFilter = {'银行'};
const Set<String> kInvestSectionFilter = {'券商', '基金/理财平台', '其他机构'};

/// 机构名 → 拼音首字母（弹层按字母分段排序用）
///
/// 名单固定且总量少（50 余家），手写映射即可，不引汉字转拼音库。
/// 新增机构时同步补一行；漏写回落 '#' 段（排在最后，不影响可用性）
final Map<String, String> kInstitutionInitials = {
  // 银行
  '中国银行': 'z',
  '工商银行': 'g',
  '农业银行': 'n',
  '建设银行': 'j',
  '交通银行': 'j',
  '招商银行': 'z',
  '邮政储蓄银行': 'y',
  '浦发银行': 'p',
  '中信银行': 'z',
  '兴业银行': 'x',
  '民生银行': 'm',
  '光大银行': 'g',
  '平安银行': 'p',
  '华夏银行': 'h',
  '广发银行': 'g',
  '浙商银行': 'z',
  '北京银行': 'b',
  '上海银行': 's',
  '江苏银行': 'j',
  '徽商银行': 'h',
  '宁波银行': 'n',
  '南京银行': 'n',
  '杭州银行': 'h',
  '成都银行': 'c',
  '重庆银行': 'c',
  '微众银行': 'w',
  '网商银行': 'w',
  '其它银行': 'q',
  // 券商
  '华泰证券': 'h',
  '中信证券': 'z',
  '中国银河': 'z',
  '国泰海通': 'g',
  '招商证券': 'z',
  '广发证券': 'g',
  '中信建投': 'z',
  '中金公司': 'z',
  '申万宏源': 's',
  '东方财富': 'd',
  '平安证券': 'p',
  '国信证券': 'g',
  '光大证券': 'g',
  '兴业证券': 'x',
  '长江证券': 'c',
  '东莞证券': 'd',
  '长城证券': 'c',
  '长桥证券': 'c',
  // 基金/理财平台
  '天天基金': 't',
  '蚂蚁财富': 'm',
  '腾讯理财通': 't',
  '京东金融': 'j',
  '同花顺': 't',
  '雪球': 'x',
  '盈米基金': 'y',
  // 其他机构
  '上海黄金交易所': 's',
  '币安': 'b',
  'OKX': 'o',
};

/// 按拼音首字母把机构分桶：桶按字母升序，桶内保持名单原序。
/// 弹层对条目多的分组（>= [kAlphabetThreshold]）做字母二次分段用
List<MapEntry<String, List<InstitutionDef>>> groupInstitutionsByInitial(
  List<InstitutionDef> items,
) {
  final buckets = <String, List<InstitutionDef>>{};
  for (final d in items) {
    buckets
        .putIfAbsent(kInstitutionInitials[d.name] ?? '#', () => [])
        .add(d);
  }
  final keys = buckets.keys.toList()..sort();
  return [for (final k in keys) MapEntry(k, buckets[k]!)];
}

/// 分组条目达到该数量才做字母二次分段（小组分段反而碎）
const int kAlphabetThreshold = 15;
