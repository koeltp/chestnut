import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/institutions.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// 机构行首圆图标（机构选择弹层与资产管理列表共用）
///
/// 机构配置了 SVG 品牌 logo（assets/images/brands/，原色图形）
/// 则渲染 logo：白圆底 + 淡灰描边兜底 + 按外圈圆形裁剪；
/// 未配置则回落首字圆标（2 字简称，按机构名稳定取色）。
/// [institutionHasLogo] 供调用方判断「有无品牌 logo」以决定
/// 是否回落分类图标。
class InstitutionLogo extends StatelessWidget {
  const InstitutionLogo({super.key, required this.name, this.size});

  /// 机构全称（落库值），如"招商银行"
  final String name;

  /// 圆的直径；缺省为全局图标底尺寸（与 [AssetCircleIcon] 一致）
  final double? size;

  @override
  Widget build(BuildContext context) {
    final d = size ?? AppDimens.iconTile;
    final svg = kInstitutionByName[name]?.svg;
    if (svg != null) {
      // 图形按下载的原色渲染、铺满整个圆（与外圈同大）
      return Container(
        width: d,
        height: d,
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
        ),
        // 撑满后按外圈圆形裁剪，方形图形（如长桥 K 线）不会溢出圆边
        child: ClipOval(child: SvgPicture.asset(svg)),
      );
    }
    // 以机构名做种子取色板下标：同名机构颜色稳定
    final color = AppColors
        .tagPalette[name.hashCode.abs() % AppColors.tagPalette.length];
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(color).withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Text(
        institutionShortName(name),
        style: TextStyle(
          fontSize: d * 11 / 36,
          fontWeight: FontWeight.w600,
          color: Color(color),
        ),
      ),
    );
  }
}

/// 机构是否配置了品牌 SVG logo
bool institutionHasLogo(String? name) =>
    name != null && kInstitutionByName[name]?.svg != null;

/// 机构首字圆标的文字：全称 → 2 字简称（"招商银行"→"招行"）
String institutionShortName(String name) {
  if (name.length <= 2) return name;
  // 特例优先：常见全称的简称映射，其余取前两字
  const special = <String, String>{
    '中国银行': '中行',
    '工商银行': '工行',
    '农业银行': '农行',
    '建设银行': '建行',
    '交通银行': '交行',
    '招商银行': '招行',
    '邮政储蓄银行': '邮储',
    '浦发银行': '浦发',
    '中信银行': '中信',
    '兴业银行': '兴业',
    '民生银行': '民生',
    '光大银行': '光大',
    '平安银行': '平安',
    '华夏银行': '华夏',
    '广发银行': '广发',
    '浙商银行': '浙商',
    '微众银行': '微众',
    '网商银行': '网商',
    '其它银行': '其它',
    '中信证券': '中信',
    '中国银河': '银河',
    '国泰海通': '国泰',
    '招商证券': '招证',
    '中信建投': '建投',
    '中金公司': '中金',
    '申万宏源': '申万',
    '东方财富': '东财',
    '国信证券': '国信',
    '上海黄金交易所': '金交',
    '腾讯理财通': '理财通',
  };
  return special[name] ?? name.substring(0, 2);
}
