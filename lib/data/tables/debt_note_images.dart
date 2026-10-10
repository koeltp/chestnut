import 'package:drift/drift.dart';

import '../../models/enums.dart';
import 'debt_notes.dart';

/// 借条图片表：借据照片（一借条可挂多张）
///
/// 与账单图片（bill_images）同架构：拍/选的图先压缩落本地缓存目录
/// （离线可看、秒开），再异步上传到用户自配的 S3 兼容云存储；
/// 本地路径与云端 objectKey 同时持有，读取永远本地优先，缓存缺失时
/// 按 objectKey 从云端拉回。删除借条时由仓储级联清理。
@TableIndex(name: 'debt_note_images_note', columns: {#noteId})
class DebtNoteImages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属借条：删除借条时由仓储级联清理记录 / 本地文件 / 云端对象
  IntColumn get noteId => integer().references(DebtNotes, #id)();

  /// 云端对象键（bucket 内唯一路径），生成规则见 DebtNoteRepository
  TextColumn get objectKey => text()();

  /// 本地缓存文件绝对路径（应用支持目录 debt_photos/{noteId}/ 下）
  TextColumn get localPath => text()();

  /// 上传状态
  IntColumn get uploadState => intEnum<BillImageUploadState>()();

  /// 添加时间
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// 同一借条内的展示顺序（按添加先后）
  IntColumn get sort => integer().withDefault(const Constant(0))();
}
