// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 20,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconCodeMeta = const VerificationMeta(
    'iconCode',
  );
  @override
  late final GeneratedColumn<int> iconCode = GeneratedColumn<int>(
    'icon_code',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BillType, int> type =
      GeneratedColumn<int>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<BillType>($CategoriesTable.$convertertype);
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<int> parentId = GeneratedColumn<int>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    iconCode,
    colorValue,
    type,
    parentId,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon_code')) {
      context.handle(
        _iconCodeMeta,
        iconCode.isAcceptableOrUnknown(data['icon_code']!, _iconCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_iconCodeMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      iconCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}icon_code'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      type: $CategoriesTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}type'],
        )!,
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parent_id'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BillType, int, int> $convertertype =
      const EnumIndexConverter<BillType>(BillType.values);
}

class Category extends DataClass implements Insertable<Category> {
  final int id;

  /// 分类名称，如"餐饮"
  final String name;

  /// Material Icons 图标的 codePoint
  final int iconCode;

  /// 分类颜色（ARGB 整数），用于饼图与列表图标配色
  final int colorValue;

  /// 分类归属的账单类型（支出 / 收入）
  final BillType type;

  /// 父分类 id：null 表示一级分类，非空表示挂在某一级分类下的子分类
  /// （仅支持两级，避免层级过深影响选择效率）
  final int? parentId;

  /// 排序权重，越小越靠前
  final int sortOrder;
  const Category({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    required this.type,
    this.parentId,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['icon_code'] = Variable<int>(iconCode);
    map['color_value'] = Variable<int>(colorValue);
    {
      map['type'] = Variable<int>($CategoriesTable.$convertertype.toSql(type));
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<int>(parentId);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      iconCode: Value(iconCode),
      colorValue: Value(colorValue),
      type: Value(type),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      sortOrder: Value(sortOrder),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      iconCode: serializer.fromJson<int>(json['iconCode']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      type: $CategoriesTable.$convertertype.fromJson(
        serializer.fromJson<int>(json['type']),
      ),
      parentId: serializer.fromJson<int?>(json['parentId']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'iconCode': serializer.toJson<int>(iconCode),
      'colorValue': serializer.toJson<int>(colorValue),
      'type': serializer.toJson<int>(
        $CategoriesTable.$convertertype.toJson(type),
      ),
      'parentId': serializer.toJson<int?>(parentId),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  Category copyWith({
    int? id,
    String? name,
    int? iconCode,
    int? colorValue,
    BillType? type,
    Value<int?> parentId = const Value.absent(),
    int? sortOrder,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    iconCode: iconCode ?? this.iconCode,
    colorValue: colorValue ?? this.colorValue,
    type: type ?? this.type,
    parentId: parentId.present ? parentId.value : this.parentId,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      iconCode: data.iconCode.present ? data.iconCode.value : this.iconCode,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      type: data.type.present ? data.type.value : this.type,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('iconCode: $iconCode, ')
          ..write('colorValue: $colorValue, ')
          ..write('type: $type, ')
          ..write('parentId: $parentId, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, iconCode, colorValue, type, parentId, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.iconCode == this.iconCode &&
          other.colorValue == this.colorValue &&
          other.type == this.type &&
          other.parentId == this.parentId &&
          other.sortOrder == this.sortOrder);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> iconCode;
  final Value<int> colorValue;
  final Value<BillType> type;
  final Value<int?> parentId;
  final Value<int> sortOrder;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.iconCode = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.type = const Value.absent(),
    this.parentId = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int iconCode,
    required int colorValue,
    required BillType type,
    this.parentId = const Value.absent(),
    this.sortOrder = const Value.absent(),
  }) : name = Value(name),
       iconCode = Value(iconCode),
       colorValue = Value(colorValue),
       type = Value(type);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? iconCode,
    Expression<int>? colorValue,
    Expression<int>? type,
    Expression<int>? parentId,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (iconCode != null) 'icon_code': iconCode,
      if (colorValue != null) 'color_value': colorValue,
      if (type != null) 'type': type,
      if (parentId != null) 'parent_id': parentId,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? iconCode,
    Value<int>? colorValue,
    Value<BillType>? type,
    Value<int?>? parentId,
    Value<int>? sortOrder,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      iconCode: iconCode ?? this.iconCode,
      colorValue: colorValue ?? this.colorValue,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (iconCode.present) {
      map['icon_code'] = Variable<int>(iconCode.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(
        $CategoriesTable.$convertertype.toSql(type.value),
      );
    }
    if (parentId.present) {
      map['parent_id'] = Variable<int>(parentId.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('iconCode: $iconCode, ')
          ..write('colorValue: $colorValue, ')
          ..write('type: $type, ')
          ..write('parentId: $parentId, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $BillsTable extends Bills with TableInfo<$BillsTable, Bill> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BillsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<BillType, int> type =
      GeneratedColumn<int>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<BillType>($BillsTable.$convertertype);
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discountCentsMeta = const VerificationMeta(
    'discountCents',
  );
  @override
  late final GeneratedColumn<int> discountCents = GeneratedColumn<int>(
    'discount_cents',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeMinuteMeta = const VerificationMeta(
    'timeMinute',
  );
  @override
  late final GeneratedColumn<int> timeMinute = GeneratedColumn<int>(
    'time_minute',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationFullMeta = const VerificationMeta(
    'locationFull',
  );
  @override
  late final GeneratedColumn<String> locationFull = GeneratedColumn<String>(
    'location_full',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _importBatchIdMeta = const VerificationMeta(
    'importBatchId',
  );
  @override
  late final GeneratedColumn<int> importBatchId = GeneratedColumn<int>(
    'import_batch_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<int> assetId = GeneratedColumn<int>(
    'asset_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toAssetIdMeta = const VerificationMeta(
    'toAssetId',
  );
  @override
  late final GeneratedColumn<int> toAssetId = GeneratedColumn<int>(
    'to_asset_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    amountCents,
    discountCents,
    categoryId,
    note,
    date,
    timeMinute,
    location,
    locationFull,
    lat,
    lng,
    createdAt,
    importBatchId,
    assetId,
    toAssetId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bills';
  @override
  VerificationContext validateIntegrity(
    Insertable<Bill> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('discount_cents')) {
      context.handle(
        _discountCentsMeta,
        discountCents.isAcceptableOrUnknown(
          data['discount_cents']!,
          _discountCentsMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('time_minute')) {
      context.handle(
        _timeMinuteMeta,
        timeMinute.isAcceptableOrUnknown(data['time_minute']!, _timeMinuteMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('location_full')) {
      context.handle(
        _locationFullMeta,
        locationFull.isAcceptableOrUnknown(
          data['location_full']!,
          _locationFullMeta,
        ),
      );
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('import_batch_id')) {
      context.handle(
        _importBatchIdMeta,
        importBatchId.isAcceptableOrUnknown(
          data['import_batch_id']!,
          _importBatchIdMeta,
        ),
      );
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    }
    if (data.containsKey('to_asset_id')) {
      context.handle(
        _toAssetIdMeta,
        toAssetId.isAcceptableOrUnknown(data['to_asset_id']!, _toAssetIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bill map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bill(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: $BillsTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}type'],
        )!,
      ),
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      discountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}discount_cents'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      timeMinute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}time_minute'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      locationFull: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_full'],
      ),
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      ),
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      importBatchId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}import_batch_id'],
      ),
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}asset_id'],
      ),
      toAssetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}to_asset_id'],
      ),
    );
  }

  @override
  $BillsTable createAlias(String alias) {
    return $BillsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BillType, int, int> $convertertype =
      const EnumIndexConverter<BillType>(BillType.values);
}

class Bill extends DataClass implements Insertable<Bill> {
  final int id;

  /// 账单类型（支出 / 收入 / 转账）
  final BillType type;

  /// 金额，单位：分（用户实际支付的金额，统计/预算一律以此为准）
  final int amountCents;

  /// 优惠金额，单位：分；null = 该笔未使用优惠。
  /// 原价不单独存储，= amountCents + discountCents。
  /// 约束 0 < discountCents <= amountCents 由保存逻辑保证
  final int? discountCents;

  /// 所属分类；null = 转账（转账无分类语义）
  final int? categoryId;

  /// 备注，可为空
  final String? note;

  /// 账单归属日期（精确到日，统计按此分组）
  final DateTime date;

  /// 账单时间：当日 0..1439 分钟；null = 未指定（旧数据）
  final int? timeMinute;

  /// 定位地名（反地理编码得到，如"广东省 深圳市 南山区 深南大道"）；null = 未定位
  final String? location;

  /// 定位完整信息（省市区街道 + 地点名全量拼接），专供搜索：
  /// POI 选点保存的 location 可能只有店名，此字段保证任何一段
  /// （省/市/区/街道/店名）都能被搜索命中；null = 未定位或旧数据
  final String? locationFull;

  /// 定位坐标（GCJ-02 纬度/经度）：编辑账单时让地图回到当时的地点；
  /// null = 未定位或行政区类地名（无精确坐标）
  final double? lat;
  final double? lng;

  /// 创建时间，用于同一天内排序
  final DateTime createdAt;

  /// 导入批次号：null = 手动记账；非空 = 批量导入（毫秒时间戳）。
  /// 同一次导入的账单共享一个批次号，结果页据此"整批撤销"
  final int? importBatchId;

  /// 关联资产账户：
  /// · 支出 = 付款账户（余额减少，信用卡欠款增加）
  /// · 收入 = 收款账户（余额增加，信用卡欠款减少）
  /// · 转账 = 转出账户
  /// · null = 不关联账户（纯记账，余额不动；旧数据均为 null）
  final int? assetId;

  /// 转入账户（仅转账账单使用）：储蓄卡 → 信用卡即还款。
  /// 与 [assetId] 组成"转出 → 转入"对；非转账恒为 null
  final int? toAssetId;
  const Bill({
    required this.id,
    required this.type,
    required this.amountCents,
    this.discountCents,
    this.categoryId,
    this.note,
    required this.date,
    this.timeMinute,
    this.location,
    this.locationFull,
    this.lat,
    this.lng,
    required this.createdAt,
    this.importBatchId,
    this.assetId,
    this.toAssetId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['type'] = Variable<int>($BillsTable.$convertertype.toSql(type));
    }
    map['amount_cents'] = Variable<int>(amountCents);
    if (!nullToAbsent || discountCents != null) {
      map['discount_cents'] = Variable<int>(discountCents);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || timeMinute != null) {
      map['time_minute'] = Variable<int>(timeMinute);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || locationFull != null) {
      map['location_full'] = Variable<String>(locationFull);
    }
    if (!nullToAbsent || lat != null) {
      map['lat'] = Variable<double>(lat);
    }
    if (!nullToAbsent || lng != null) {
      map['lng'] = Variable<double>(lng);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || importBatchId != null) {
      map['import_batch_id'] = Variable<int>(importBatchId);
    }
    if (!nullToAbsent || assetId != null) {
      map['asset_id'] = Variable<int>(assetId);
    }
    if (!nullToAbsent || toAssetId != null) {
      map['to_asset_id'] = Variable<int>(toAssetId);
    }
    return map;
  }

  BillsCompanion toCompanion(bool nullToAbsent) {
    return BillsCompanion(
      id: Value(id),
      type: Value(type),
      amountCents: Value(amountCents),
      discountCents: discountCents == null && nullToAbsent
          ? const Value.absent()
          : Value(discountCents),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      date: Value(date),
      timeMinute: timeMinute == null && nullToAbsent
          ? const Value.absent()
          : Value(timeMinute),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      locationFull: locationFull == null && nullToAbsent
          ? const Value.absent()
          : Value(locationFull),
      lat: lat == null && nullToAbsent ? const Value.absent() : Value(lat),
      lng: lng == null && nullToAbsent ? const Value.absent() : Value(lng),
      createdAt: Value(createdAt),
      importBatchId: importBatchId == null && nullToAbsent
          ? const Value.absent()
          : Value(importBatchId),
      assetId: assetId == null && nullToAbsent
          ? const Value.absent()
          : Value(assetId),
      toAssetId: toAssetId == null && nullToAbsent
          ? const Value.absent()
          : Value(toAssetId),
    );
  }

  factory Bill.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Bill(
      id: serializer.fromJson<int>(json['id']),
      type: $BillsTable.$convertertype.fromJson(
        serializer.fromJson<int>(json['type']),
      ),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      discountCents: serializer.fromJson<int?>(json['discountCents']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      note: serializer.fromJson<String?>(json['note']),
      date: serializer.fromJson<DateTime>(json['date']),
      timeMinute: serializer.fromJson<int?>(json['timeMinute']),
      location: serializer.fromJson<String?>(json['location']),
      locationFull: serializer.fromJson<String?>(json['locationFull']),
      lat: serializer.fromJson<double?>(json['lat']),
      lng: serializer.fromJson<double?>(json['lng']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      importBatchId: serializer.fromJson<int?>(json['importBatchId']),
      assetId: serializer.fromJson<int?>(json['assetId']),
      toAssetId: serializer.fromJson<int?>(json['toAssetId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<int>($BillsTable.$convertertype.toJson(type)),
      'amountCents': serializer.toJson<int>(amountCents),
      'discountCents': serializer.toJson<int?>(discountCents),
      'categoryId': serializer.toJson<int?>(categoryId),
      'note': serializer.toJson<String?>(note),
      'date': serializer.toJson<DateTime>(date),
      'timeMinute': serializer.toJson<int?>(timeMinute),
      'location': serializer.toJson<String?>(location),
      'locationFull': serializer.toJson<String?>(locationFull),
      'lat': serializer.toJson<double?>(lat),
      'lng': serializer.toJson<double?>(lng),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'importBatchId': serializer.toJson<int?>(importBatchId),
      'assetId': serializer.toJson<int?>(assetId),
      'toAssetId': serializer.toJson<int?>(toAssetId),
    };
  }

  Bill copyWith({
    int? id,
    BillType? type,
    int? amountCents,
    Value<int?> discountCents = const Value.absent(),
    Value<int?> categoryId = const Value.absent(),
    Value<String?> note = const Value.absent(),
    DateTime? date,
    Value<int?> timeMinute = const Value.absent(),
    Value<String?> location = const Value.absent(),
    Value<String?> locationFull = const Value.absent(),
    Value<double?> lat = const Value.absent(),
    Value<double?> lng = const Value.absent(),
    DateTime? createdAt,
    Value<int?> importBatchId = const Value.absent(),
    Value<int?> assetId = const Value.absent(),
    Value<int?> toAssetId = const Value.absent(),
  }) => Bill(
    id: id ?? this.id,
    type: type ?? this.type,
    amountCents: amountCents ?? this.amountCents,
    discountCents: discountCents.present
        ? discountCents.value
        : this.discountCents,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    note: note.present ? note.value : this.note,
    date: date ?? this.date,
    timeMinute: timeMinute.present ? timeMinute.value : this.timeMinute,
    location: location.present ? location.value : this.location,
    locationFull: locationFull.present ? locationFull.value : this.locationFull,
    lat: lat.present ? lat.value : this.lat,
    lng: lng.present ? lng.value : this.lng,
    createdAt: createdAt ?? this.createdAt,
    importBatchId: importBatchId.present
        ? importBatchId.value
        : this.importBatchId,
    assetId: assetId.present ? assetId.value : this.assetId,
    toAssetId: toAssetId.present ? toAssetId.value : this.toAssetId,
  );
  Bill copyWithCompanion(BillsCompanion data) {
    return Bill(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      discountCents: data.discountCents.present
          ? data.discountCents.value
          : this.discountCents,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      note: data.note.present ? data.note.value : this.note,
      date: data.date.present ? data.date.value : this.date,
      timeMinute: data.timeMinute.present
          ? data.timeMinute.value
          : this.timeMinute,
      location: data.location.present ? data.location.value : this.location,
      locationFull: data.locationFull.present
          ? data.locationFull.value
          : this.locationFull,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      importBatchId: data.importBatchId.present
          ? data.importBatchId.value
          : this.importBatchId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      toAssetId: data.toAssetId.present ? data.toAssetId.value : this.toAssetId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Bill(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('amountCents: $amountCents, ')
          ..write('discountCents: $discountCents, ')
          ..write('categoryId: $categoryId, ')
          ..write('note: $note, ')
          ..write('date: $date, ')
          ..write('timeMinute: $timeMinute, ')
          ..write('location: $location, ')
          ..write('locationFull: $locationFull, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('createdAt: $createdAt, ')
          ..write('importBatchId: $importBatchId, ')
          ..write('assetId: $assetId, ')
          ..write('toAssetId: $toAssetId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    amountCents,
    discountCents,
    categoryId,
    note,
    date,
    timeMinute,
    location,
    locationFull,
    lat,
    lng,
    createdAt,
    importBatchId,
    assetId,
    toAssetId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Bill &&
          other.id == this.id &&
          other.type == this.type &&
          other.amountCents == this.amountCents &&
          other.discountCents == this.discountCents &&
          other.categoryId == this.categoryId &&
          other.note == this.note &&
          other.date == this.date &&
          other.timeMinute == this.timeMinute &&
          other.location == this.location &&
          other.locationFull == this.locationFull &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.createdAt == this.createdAt &&
          other.importBatchId == this.importBatchId &&
          other.assetId == this.assetId &&
          other.toAssetId == this.toAssetId);
}

class BillsCompanion extends UpdateCompanion<Bill> {
  final Value<int> id;
  final Value<BillType> type;
  final Value<int> amountCents;
  final Value<int?> discountCents;
  final Value<int?> categoryId;
  final Value<String?> note;
  final Value<DateTime> date;
  final Value<int?> timeMinute;
  final Value<String?> location;
  final Value<String?> locationFull;
  final Value<double?> lat;
  final Value<double?> lng;
  final Value<DateTime> createdAt;
  final Value<int?> importBatchId;
  final Value<int?> assetId;
  final Value<int?> toAssetId;
  const BillsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.discountCents = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.note = const Value.absent(),
    this.date = const Value.absent(),
    this.timeMinute = const Value.absent(),
    this.location = const Value.absent(),
    this.locationFull = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.importBatchId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.toAssetId = const Value.absent(),
  });
  BillsCompanion.insert({
    this.id = const Value.absent(),
    required BillType type,
    required int amountCents,
    this.discountCents = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime date,
    this.timeMinute = const Value.absent(),
    this.location = const Value.absent(),
    this.locationFull = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.importBatchId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.toAssetId = const Value.absent(),
  }) : type = Value(type),
       amountCents = Value(amountCents),
       date = Value(date);
  static Insertable<Bill> custom({
    Expression<int>? id,
    Expression<int>? type,
    Expression<int>? amountCents,
    Expression<int>? discountCents,
    Expression<int>? categoryId,
    Expression<String>? note,
    Expression<DateTime>? date,
    Expression<int>? timeMinute,
    Expression<String>? location,
    Expression<String>? locationFull,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<DateTime>? createdAt,
    Expression<int>? importBatchId,
    Expression<int>? assetId,
    Expression<int>? toAssetId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (amountCents != null) 'amount_cents': amountCents,
      if (discountCents != null) 'discount_cents': discountCents,
      if (categoryId != null) 'category_id': categoryId,
      if (note != null) 'note': note,
      if (date != null) 'date': date,
      if (timeMinute != null) 'time_minute': timeMinute,
      if (location != null) 'location': location,
      if (locationFull != null) 'location_full': locationFull,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (createdAt != null) 'created_at': createdAt,
      if (importBatchId != null) 'import_batch_id': importBatchId,
      if (assetId != null) 'asset_id': assetId,
      if (toAssetId != null) 'to_asset_id': toAssetId,
    });
  }

  BillsCompanion copyWith({
    Value<int>? id,
    Value<BillType>? type,
    Value<int>? amountCents,
    Value<int?>? discountCents,
    Value<int?>? categoryId,
    Value<String?>? note,
    Value<DateTime>? date,
    Value<int?>? timeMinute,
    Value<String?>? location,
    Value<String?>? locationFull,
    Value<double?>? lat,
    Value<double?>? lng,
    Value<DateTime>? createdAt,
    Value<int?>? importBatchId,
    Value<int?>? assetId,
    Value<int?>? toAssetId,
  }) {
    return BillsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      amountCents: amountCents ?? this.amountCents,
      discountCents: discountCents ?? this.discountCents,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      date: date ?? this.date,
      timeMinute: timeMinute ?? this.timeMinute,
      location: location ?? this.location,
      locationFull: locationFull ?? this.locationFull,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      createdAt: createdAt ?? this.createdAt,
      importBatchId: importBatchId ?? this.importBatchId,
      assetId: assetId ?? this.assetId,
      toAssetId: toAssetId ?? this.toAssetId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<int>($BillsTable.$convertertype.toSql(type.value));
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (discountCents.present) {
      map['discount_cents'] = Variable<int>(discountCents.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (timeMinute.present) {
      map['time_minute'] = Variable<int>(timeMinute.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (locationFull.present) {
      map['location_full'] = Variable<String>(locationFull.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (importBatchId.present) {
      map['import_batch_id'] = Variable<int>(importBatchId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<int>(assetId.value);
    }
    if (toAssetId.present) {
      map['to_asset_id'] = Variable<int>(toAssetId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BillsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('amountCents: $amountCents, ')
          ..write('discountCents: $discountCents, ')
          ..write('categoryId: $categoryId, ')
          ..write('note: $note, ')
          ..write('date: $date, ')
          ..write('timeMinute: $timeMinute, ')
          ..write('location: $location, ')
          ..write('locationFull: $locationFull, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('createdAt: $createdAt, ')
          ..write('importBatchId: $importBatchId, ')
          ..write('assetId: $assetId, ')
          ..write('toAssetId: $toAssetId')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTable extends Budgets with TableInfo<$BudgetsTable, Budget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _monthMeta = const VerificationMeta('month');
  @override
  late final GeneratedColumn<String> month = GeneratedColumn<String>(
    'month',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, month, amountCents, categoryId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Budget> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('month')) {
      context.handle(
        _monthMeta,
        month.isAcceptableOrUnknown(data['month']!, _monthMeta),
      );
    } else if (isInserting) {
      context.missing(_monthMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {month, categoryId},
  ];
  @override
  Budget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Budget(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      month: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}month'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      )!,
    );
  }

  @override
  $BudgetsTable createAlias(String alias) {
    return $BudgetsTable(attachedDatabase, alias);
  }
}

class Budget extends DataClass implements Insertable<Budget> {
  final int id;

  /// 预算月份，格式 `yyyy-MM`
  final String month;

  /// 预算金额，单位：分
  final int amountCents;

  /// 预算归属：0 = 月度总预算；> 0 = 该分类（一级）当月预算
  final int categoryId;
  const Budget({
    required this.id,
    required this.month,
    required this.amountCents,
    required this.categoryId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['month'] = Variable<String>(month);
    map['amount_cents'] = Variable<int>(amountCents);
    map['category_id'] = Variable<int>(categoryId);
    return map;
  }

  BudgetsCompanion toCompanion(bool nullToAbsent) {
    return BudgetsCompanion(
      id: Value(id),
      month: Value(month),
      amountCents: Value(amountCents),
      categoryId: Value(categoryId),
    );
  }

  factory Budget.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Budget(
      id: serializer.fromJson<int>(json['id']),
      month: serializer.fromJson<String>(json['month']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      categoryId: serializer.fromJson<int>(json['categoryId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'month': serializer.toJson<String>(month),
      'amountCents': serializer.toJson<int>(amountCents),
      'categoryId': serializer.toJson<int>(categoryId),
    };
  }

  Budget copyWith({
    int? id,
    String? month,
    int? amountCents,
    int? categoryId,
  }) => Budget(
    id: id ?? this.id,
    month: month ?? this.month,
    amountCents: amountCents ?? this.amountCents,
    categoryId: categoryId ?? this.categoryId,
  );
  Budget copyWithCompanion(BudgetsCompanion data) {
    return Budget(
      id: data.id.present ? data.id.value : this.id,
      month: data.month.present ? data.month.value : this.month,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Budget(')
          ..write('id: $id, ')
          ..write('month: $month, ')
          ..write('amountCents: $amountCents, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, month, amountCents, categoryId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Budget &&
          other.id == this.id &&
          other.month == this.month &&
          other.amountCents == this.amountCents &&
          other.categoryId == this.categoryId);
}

class BudgetsCompanion extends UpdateCompanion<Budget> {
  final Value<int> id;
  final Value<String> month;
  final Value<int> amountCents;
  final Value<int> categoryId;
  const BudgetsCompanion({
    this.id = const Value.absent(),
    this.month = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.categoryId = const Value.absent(),
  });
  BudgetsCompanion.insert({
    this.id = const Value.absent(),
    required String month,
    required int amountCents,
    this.categoryId = const Value.absent(),
  }) : month = Value(month),
       amountCents = Value(amountCents);
  static Insertable<Budget> custom({
    Expression<int>? id,
    Expression<String>? month,
    Expression<int>? amountCents,
    Expression<int>? categoryId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (month != null) 'month': month,
      if (amountCents != null) 'amount_cents': amountCents,
      if (categoryId != null) 'category_id': categoryId,
    });
  }

  BudgetsCompanion copyWith({
    Value<int>? id,
    Value<String>? month,
    Value<int>? amountCents,
    Value<int>? categoryId,
  }) {
    return BudgetsCompanion(
      id: id ?? this.id,
      month: month ?? this.month,
      amountCents: amountCents ?? this.amountCents,
      categoryId: categoryId ?? this.categoryId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (month.present) {
      map['month'] = Variable<String>(month.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsCompanion(')
          ..write('id: $id, ')
          ..write('month: $month, ')
          ..write('amountCents: $amountCents, ')
          ..write('categoryId: $categoryId')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, color, sortOrder, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final int id;

  /// 标签名（唯一，查重由仓储保证）
  final String name;

  /// 标签颜色（ARGB 整数），新建时自动按色板循环分配，可在管理页修改
  final int color;

  /// 排序权重（越小越靠前），新建时追加到末尾
  final int sortOrder;

  /// 创建时间
  final DateTime createdAt;
  const Tag({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
    );
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Tag copyWith({
    int? id,
    String? name,
    int? color,
    int? sortOrder,
    DateTime? createdAt,
  }) => Tag(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, color, sortOrder, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.color == this.color &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> color;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TagsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int color,
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : name = Value(name),
       color = Value(color);
  static Insertable<Tag> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? color,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TagsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? color,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $BillTagsTable extends BillTags with TableInfo<$BillTagsTable, BillTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BillTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _billIdMeta = const VerificationMeta('billId');
  @override
  late final GeneratedColumn<int> billId = GeneratedColumn<int>(
    'bill_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<int> tagId = GeneratedColumn<int>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [billId, tagId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bill_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<BillTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bill_id')) {
      context.handle(
        _billIdMeta,
        billId.isAcceptableOrUnknown(data['bill_id']!, _billIdMeta),
      );
    } else if (isInserting) {
      context.missing(_billIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {billId, tagId};
  @override
  BillTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BillTag(
      billId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bill_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tag_id'],
      )!,
    );
  }

  @override
  $BillTagsTable createAlias(String alias) {
    return $BillTagsTable(attachedDatabase, alias);
  }
}

class BillTag extends DataClass implements Insertable<BillTag> {
  final int billId;
  final int tagId;
  const BillTag({required this.billId, required this.tagId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bill_id'] = Variable<int>(billId);
    map['tag_id'] = Variable<int>(tagId);
    return map;
  }

  BillTagsCompanion toCompanion(bool nullToAbsent) {
    return BillTagsCompanion(billId: Value(billId), tagId: Value(tagId));
  }

  factory BillTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BillTag(
      billId: serializer.fromJson<int>(json['billId']),
      tagId: serializer.fromJson<int>(json['tagId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'billId': serializer.toJson<int>(billId),
      'tagId': serializer.toJson<int>(tagId),
    };
  }

  BillTag copyWith({int? billId, int? tagId}) =>
      BillTag(billId: billId ?? this.billId, tagId: tagId ?? this.tagId);
  BillTag copyWithCompanion(BillTagsCompanion data) {
    return BillTag(
      billId: data.billId.present ? data.billId.value : this.billId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BillTag(')
          ..write('billId: $billId, ')
          ..write('tagId: $tagId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(billId, tagId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BillTag &&
          other.billId == this.billId &&
          other.tagId == this.tagId);
}

class BillTagsCompanion extends UpdateCompanion<BillTag> {
  final Value<int> billId;
  final Value<int> tagId;
  final Value<int> rowid;
  const BillTagsCompanion({
    this.billId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BillTagsCompanion.insert({
    required int billId,
    required int tagId,
    this.rowid = const Value.absent(),
  }) : billId = Value(billId),
       tagId = Value(tagId);
  static Insertable<BillTag> custom({
    Expression<int>? billId,
    Expression<int>? tagId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (billId != null) 'bill_id': billId,
      if (tagId != null) 'tag_id': tagId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BillTagsCompanion copyWith({
    Value<int>? billId,
    Value<int>? tagId,
    Value<int>? rowid,
  }) {
    return BillTagsCompanion(
      billId: billId ?? this.billId,
      tagId: tagId ?? this.tagId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (billId.present) {
      map['bill_id'] = Variable<int>(billId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<int>(tagId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BillTagsCompanion(')
          ..write('billId: $billId, ')
          ..write('tagId: $tagId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BillImagesTable extends BillImages
    with TableInfo<$BillImagesTable, BillImage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BillImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _billIdMeta = const VerificationMeta('billId');
  @override
  late final GeneratedColumn<int> billId = GeneratedColumn<int>(
    'bill_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectKeyMeta = const VerificationMeta(
    'objectKey',
  );
  @override
  late final GeneratedColumn<String> objectKey = GeneratedColumn<String>(
    'object_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BillImageUploadState, int>
  uploadState = GeneratedColumn<int>(
    'upload_state',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<BillImageUploadState>($BillImagesTable.$converteruploadState);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    billId,
    objectKey,
    localPath,
    uploadState,
    createdAt,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bill_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<BillImage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('bill_id')) {
      context.handle(
        _billIdMeta,
        billId.isAcceptableOrUnknown(data['bill_id']!, _billIdMeta),
      );
    } else if (isInserting) {
      context.missing(_billIdMeta);
    }
    if (data.containsKey('object_key')) {
      context.handle(
        _objectKeyMeta,
        objectKey.isAcceptableOrUnknown(data['object_key']!, _objectKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_objectKeyMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BillImage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BillImage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      billId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bill_id'],
      )!,
      objectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_key'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      uploadState: $BillImagesTable.$converteruploadState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}upload_state'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $BillImagesTable createAlias(String alias) {
    return $BillImagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BillImageUploadState, int, int>
  $converteruploadState = const EnumIndexConverter<BillImageUploadState>(
    BillImageUploadState.values,
  );
}

class BillImage extends DataClass implements Insertable<BillImage> {
  final int id;

  /// 所属账单：删除账单时由仓储级联清理记录 / 本地文件 / 云端对象
  final int billId;

  /// 云端对象键（bucket 内唯一路径），生成规则见 BillImageRepository
  final String objectKey;

  /// 本地缓存文件绝对路径（应用支持目录 receipts/ 下）
  final String localPath;

  /// 上传状态
  final BillImageUploadState uploadState;

  /// 添加时间
  final DateTime createdAt;

  /// 同一账单内的展示顺序（按添加先后）
  final int sort;
  const BillImage({
    required this.id,
    required this.billId,
    required this.objectKey,
    required this.localPath,
    required this.uploadState,
    required this.createdAt,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['bill_id'] = Variable<int>(billId);
    map['object_key'] = Variable<String>(objectKey);
    map['local_path'] = Variable<String>(localPath);
    {
      map['upload_state'] = Variable<int>(
        $BillImagesTable.$converteruploadState.toSql(uploadState),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  BillImagesCompanion toCompanion(bool nullToAbsent) {
    return BillImagesCompanion(
      id: Value(id),
      billId: Value(billId),
      objectKey: Value(objectKey),
      localPath: Value(localPath),
      uploadState: Value(uploadState),
      createdAt: Value(createdAt),
      sort: Value(sort),
    );
  }

  factory BillImage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BillImage(
      id: serializer.fromJson<int>(json['id']),
      billId: serializer.fromJson<int>(json['billId']),
      objectKey: serializer.fromJson<String>(json['objectKey']),
      localPath: serializer.fromJson<String>(json['localPath']),
      uploadState: $BillImagesTable.$converteruploadState.fromJson(
        serializer.fromJson<int>(json['uploadState']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'billId': serializer.toJson<int>(billId),
      'objectKey': serializer.toJson<String>(objectKey),
      'localPath': serializer.toJson<String>(localPath),
      'uploadState': serializer.toJson<int>(
        $BillImagesTable.$converteruploadState.toJson(uploadState),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sort': serializer.toJson<int>(sort),
    };
  }

  BillImage copyWith({
    int? id,
    int? billId,
    String? objectKey,
    String? localPath,
    BillImageUploadState? uploadState,
    DateTime? createdAt,
    int? sort,
  }) => BillImage(
    id: id ?? this.id,
    billId: billId ?? this.billId,
    objectKey: objectKey ?? this.objectKey,
    localPath: localPath ?? this.localPath,
    uploadState: uploadState ?? this.uploadState,
    createdAt: createdAt ?? this.createdAt,
    sort: sort ?? this.sort,
  );
  BillImage copyWithCompanion(BillImagesCompanion data) {
    return BillImage(
      id: data.id.present ? data.id.value : this.id,
      billId: data.billId.present ? data.billId.value : this.billId,
      objectKey: data.objectKey.present ? data.objectKey.value : this.objectKey,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BillImage(')
          ..write('id: $id, ')
          ..write('billId: $billId, ')
          ..write('objectKey: $objectKey, ')
          ..write('localPath: $localPath, ')
          ..write('uploadState: $uploadState, ')
          ..write('createdAt: $createdAt, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    billId,
    objectKey,
    localPath,
    uploadState,
    createdAt,
    sort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BillImage &&
          other.id == this.id &&
          other.billId == this.billId &&
          other.objectKey == this.objectKey &&
          other.localPath == this.localPath &&
          other.uploadState == this.uploadState &&
          other.createdAt == this.createdAt &&
          other.sort == this.sort);
}

class BillImagesCompanion extends UpdateCompanion<BillImage> {
  final Value<int> id;
  final Value<int> billId;
  final Value<String> objectKey;
  final Value<String> localPath;
  final Value<BillImageUploadState> uploadState;
  final Value<DateTime> createdAt;
  final Value<int> sort;
  const BillImagesCompanion({
    this.id = const Value.absent(),
    this.billId = const Value.absent(),
    this.objectKey = const Value.absent(),
    this.localPath = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sort = const Value.absent(),
  });
  BillImagesCompanion.insert({
    this.id = const Value.absent(),
    required int billId,
    required String objectKey,
    required String localPath,
    required BillImageUploadState uploadState,
    this.createdAt = const Value.absent(),
    this.sort = const Value.absent(),
  }) : billId = Value(billId),
       objectKey = Value(objectKey),
       localPath = Value(localPath),
       uploadState = Value(uploadState);
  static Insertable<BillImage> custom({
    Expression<int>? id,
    Expression<int>? billId,
    Expression<String>? objectKey,
    Expression<String>? localPath,
    Expression<int>? uploadState,
    Expression<DateTime>? createdAt,
    Expression<int>? sort,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (billId != null) 'bill_id': billId,
      if (objectKey != null) 'object_key': objectKey,
      if (localPath != null) 'local_path': localPath,
      if (uploadState != null) 'upload_state': uploadState,
      if (createdAt != null) 'created_at': createdAt,
      if (sort != null) 'sort': sort,
    });
  }

  BillImagesCompanion copyWith({
    Value<int>? id,
    Value<int>? billId,
    Value<String>? objectKey,
    Value<String>? localPath,
    Value<BillImageUploadState>? uploadState,
    Value<DateTime>? createdAt,
    Value<int>? sort,
  }) {
    return BillImagesCompanion(
      id: id ?? this.id,
      billId: billId ?? this.billId,
      objectKey: objectKey ?? this.objectKey,
      localPath: localPath ?? this.localPath,
      uploadState: uploadState ?? this.uploadState,
      createdAt: createdAt ?? this.createdAt,
      sort: sort ?? this.sort,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (billId.present) {
      map['bill_id'] = Variable<int>(billId.value);
    }
    if (objectKey.present) {
      map['object_key'] = Variable<String>(objectKey.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<int>(
        $BillImagesTable.$converteruploadState.toSql(uploadState.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BillImagesCompanion(')
          ..write('id: $id, ')
          ..write('billId: $billId, ')
          ..write('objectKey: $objectKey, ')
          ..write('localPath: $localPath, ')
          ..write('uploadState: $uploadState, ')
          ..write('createdAt: $createdAt, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }
}

class $AssetsTable extends Assets with TableInfo<$AssetsTable, Asset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AssetKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<AssetKind>($AssetsTable.$converterkind);
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueCentsMeta = const VerificationMeta(
    'valueCents',
  );
  @override
  late final GeneratedColumn<int> valueCents = GeneratedColumn<int>(
    'value_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _includeInNetMeta = const VerificationMeta(
    'includeInNet',
  );
  @override
  late final GeneratedColumn<bool> includeInNet = GeneratedColumn<bool>(
    'include_in_net',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("include_in_net" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _creditLimitCentsMeta = const VerificationMeta(
    'creditLimitCents',
  );
  @override
  late final GeneratedColumn<int> creditLimitCents = GeneratedColumn<int>(
    'credit_limit_cents',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _billDayMeta = const VerificationMeta(
    'billDay',
  );
  @override
  late final GeneratedColumn<int> billDay = GeneratedColumn<int>(
    'bill_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repayDayMeta = const VerificationMeta(
    'repayDay',
  );
  @override
  late final GeneratedColumn<int> repayDay = GeneratedColumn<int>(
    'repay_day',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    kind,
    category,
    valueCents,
    note,
    sortOrder,
    archived,
    includeInNet,
    creditLimitCents,
    billDay,
    repayDay,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Asset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('value_cents')) {
      context.handle(
        _valueCentsMeta,
        valueCents.isAcceptableOrUnknown(data['value_cents']!, _valueCentsMeta),
      );
    } else if (isInserting) {
      context.missing(_valueCentsMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['archived']!, _archivedMeta),
      );
    }
    if (data.containsKey('include_in_net')) {
      context.handle(
        _includeInNetMeta,
        includeInNet.isAcceptableOrUnknown(
          data['include_in_net']!,
          _includeInNetMeta,
        ),
      );
    }
    if (data.containsKey('credit_limit_cents')) {
      context.handle(
        _creditLimitCentsMeta,
        creditLimitCents.isAcceptableOrUnknown(
          data['credit_limit_cents']!,
          _creditLimitCentsMeta,
        ),
      );
    }
    if (data.containsKey('bill_day')) {
      context.handle(
        _billDayMeta,
        billDay.isAcceptableOrUnknown(data['bill_day']!, _billDayMeta),
      );
    }
    if (data.containsKey('repay_day')) {
      context.handle(
        _repayDayMeta,
        repayDay.isAcceptableOrUnknown(data['repay_day']!, _repayDayMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Asset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Asset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: $AssetsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      valueCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value_cents'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}archived'],
      )!,
      includeInNet: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}include_in_net'],
      )!,
      creditLimitCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}credit_limit_cents'],
      ),
      billDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bill_day'],
      ),
      repayDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repay_day'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AssetsTable createAlias(String alias) {
    return $AssetsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AssetKind, int, int> $converterkind =
      const EnumIndexConverter<AssetKind>(AssetKind.values);
}

class Asset extends DataClass implements Insertable<Asset> {
  final int id;

  /// 资产名称，如"招行储蓄卡"、"婚房"
  final String name;

  /// 类型：资产 / 负债
  final AssetKind kind;

  /// 分类名（预设固定集，见 AssetGroups），如"现金"、"信用卡"
  final String category;

  /// 当前市值，单位：分（恒为正数，负债由 kind 区分）
  final int valueCents;

  /// 备注，可为空
  final String? note;

  /// 排序权重（越小越靠前），新建时追加到同类型末尾
  final int sortOrder;

  /// 归档标记：true = 已归档，不参与净值统计
  final bool archived;

  /// 是否计入总资产：false = 只在列表展示，不参与净值/占比统计
  final bool includeInNet;

  /// 信用卡总额度，单位：分；null = 非信用卡分类或未填写
  final int? creditLimitCents;

  /// 信用卡出账日（1~31）；null = 非信用卡分类或未填写
  final int? billDay;

  /// 信用卡还款日（1~31）；null = 非信用卡分类或未填写
  final int? repayDay;

  /// 创建时间
  final DateTime createdAt;

  /// 最近一次市值或信息更新时间
  final DateTime updatedAt;
  const Asset({
    required this.id,
    required this.name,
    required this.kind,
    required this.category,
    required this.valueCents,
    this.note,
    required this.sortOrder,
    required this.archived,
    required this.includeInNet,
    this.creditLimitCents,
    this.billDay,
    this.repayDay,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    {
      map['kind'] = Variable<int>($AssetsTable.$converterkind.toSql(kind));
    }
    map['category'] = Variable<String>(category);
    map['value_cents'] = Variable<int>(valueCents);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['archived'] = Variable<bool>(archived);
    map['include_in_net'] = Variable<bool>(includeInNet);
    if (!nullToAbsent || creditLimitCents != null) {
      map['credit_limit_cents'] = Variable<int>(creditLimitCents);
    }
    if (!nullToAbsent || billDay != null) {
      map['bill_day'] = Variable<int>(billDay);
    }
    if (!nullToAbsent || repayDay != null) {
      map['repay_day'] = Variable<int>(repayDay);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AssetsCompanion toCompanion(bool nullToAbsent) {
    return AssetsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      category: Value(category),
      valueCents: Value(valueCents),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      sortOrder: Value(sortOrder),
      archived: Value(archived),
      includeInNet: Value(includeInNet),
      creditLimitCents: creditLimitCents == null && nullToAbsent
          ? const Value.absent()
          : Value(creditLimitCents),
      billDay: billDay == null && nullToAbsent
          ? const Value.absent()
          : Value(billDay),
      repayDay: repayDay == null && nullToAbsent
          ? const Value.absent()
          : Value(repayDay),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Asset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Asset(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: $AssetsTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      category: serializer.fromJson<String>(json['category']),
      valueCents: serializer.fromJson<int>(json['valueCents']),
      note: serializer.fromJson<String?>(json['note']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      archived: serializer.fromJson<bool>(json['archived']),
      includeInNet: serializer.fromJson<bool>(json['includeInNet']),
      creditLimitCents: serializer.fromJson<int?>(json['creditLimitCents']),
      billDay: serializer.fromJson<int?>(json['billDay']),
      repayDay: serializer.fromJson<int?>(json['repayDay']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<int>($AssetsTable.$converterkind.toJson(kind)),
      'category': serializer.toJson<String>(category),
      'valueCents': serializer.toJson<int>(valueCents),
      'note': serializer.toJson<String?>(note),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'archived': serializer.toJson<bool>(archived),
      'includeInNet': serializer.toJson<bool>(includeInNet),
      'creditLimitCents': serializer.toJson<int?>(creditLimitCents),
      'billDay': serializer.toJson<int?>(billDay),
      'repayDay': serializer.toJson<int?>(repayDay),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Asset copyWith({
    int? id,
    String? name,
    AssetKind? kind,
    String? category,
    int? valueCents,
    Value<String?> note = const Value.absent(),
    int? sortOrder,
    bool? archived,
    bool? includeInNet,
    Value<int?> creditLimitCents = const Value.absent(),
    Value<int?> billDay = const Value.absent(),
    Value<int?> repayDay = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Asset(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    category: category ?? this.category,
    valueCents: valueCents ?? this.valueCents,
    note: note.present ? note.value : this.note,
    sortOrder: sortOrder ?? this.sortOrder,
    archived: archived ?? this.archived,
    includeInNet: includeInNet ?? this.includeInNet,
    creditLimitCents: creditLimitCents.present
        ? creditLimitCents.value
        : this.creditLimitCents,
    billDay: billDay.present ? billDay.value : this.billDay,
    repayDay: repayDay.present ? repayDay.value : this.repayDay,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Asset copyWithCompanion(AssetsCompanion data) {
    return Asset(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      category: data.category.present ? data.category.value : this.category,
      valueCents: data.valueCents.present
          ? data.valueCents.value
          : this.valueCents,
      note: data.note.present ? data.note.value : this.note,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      archived: data.archived.present ? data.archived.value : this.archived,
      includeInNet: data.includeInNet.present
          ? data.includeInNet.value
          : this.includeInNet,
      creditLimitCents: data.creditLimitCents.present
          ? data.creditLimitCents.value
          : this.creditLimitCents,
      billDay: data.billDay.present ? data.billDay.value : this.billDay,
      repayDay: data.repayDay.present ? data.repayDay.value : this.repayDay,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Asset(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('category: $category, ')
          ..write('valueCents: $valueCents, ')
          ..write('note: $note, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archived: $archived, ')
          ..write('includeInNet: $includeInNet, ')
          ..write('creditLimitCents: $creditLimitCents, ')
          ..write('billDay: $billDay, ')
          ..write('repayDay: $repayDay, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    category,
    valueCents,
    note,
    sortOrder,
    archived,
    includeInNet,
    creditLimitCents,
    billDay,
    repayDay,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Asset &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.category == this.category &&
          other.valueCents == this.valueCents &&
          other.note == this.note &&
          other.sortOrder == this.sortOrder &&
          other.archived == this.archived &&
          other.includeInNet == this.includeInNet &&
          other.creditLimitCents == this.creditLimitCents &&
          other.billDay == this.billDay &&
          other.repayDay == this.repayDay &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AssetsCompanion extends UpdateCompanion<Asset> {
  final Value<int> id;
  final Value<String> name;
  final Value<AssetKind> kind;
  final Value<String> category;
  final Value<int> valueCents;
  final Value<String?> note;
  final Value<int> sortOrder;
  final Value<bool> archived;
  final Value<bool> includeInNet;
  final Value<int?> creditLimitCents;
  final Value<int?> billDay;
  final Value<int?> repayDay;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const AssetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.category = const Value.absent(),
    this.valueCents = const Value.absent(),
    this.note = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archived = const Value.absent(),
    this.includeInNet = const Value.absent(),
    this.creditLimitCents = const Value.absent(),
    this.billDay = const Value.absent(),
    this.repayDay = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AssetsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required AssetKind kind,
    required String category,
    required int valueCents,
    this.note = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.archived = const Value.absent(),
    this.includeInNet = const Value.absent(),
    this.creditLimitCents = const Value.absent(),
    this.billDay = const Value.absent(),
    this.repayDay = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name),
       kind = Value(kind),
       category = Value(category),
       valueCents = Value(valueCents);
  static Insertable<Asset> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? kind,
    Expression<String>? category,
    Expression<int>? valueCents,
    Expression<String>? note,
    Expression<int>? sortOrder,
    Expression<bool>? archived,
    Expression<bool>? includeInNet,
    Expression<int>? creditLimitCents,
    Expression<int>? billDay,
    Expression<int>? repayDay,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (category != null) 'category': category,
      if (valueCents != null) 'value_cents': valueCents,
      if (note != null) 'note': note,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (archived != null) 'archived': archived,
      if (includeInNet != null) 'include_in_net': includeInNet,
      if (creditLimitCents != null) 'credit_limit_cents': creditLimitCents,
      if (billDay != null) 'bill_day': billDay,
      if (repayDay != null) 'repay_day': repayDay,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AssetsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<AssetKind>? kind,
    Value<String>? category,
    Value<int>? valueCents,
    Value<String?>? note,
    Value<int>? sortOrder,
    Value<bool>? archived,
    Value<bool>? includeInNet,
    Value<int?>? creditLimitCents,
    Value<int?>? billDay,
    Value<int?>? repayDay,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return AssetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      category: category ?? this.category,
      valueCents: valueCents ?? this.valueCents,
      note: note ?? this.note,
      sortOrder: sortOrder ?? this.sortOrder,
      archived: archived ?? this.archived,
      includeInNet: includeInNet ?? this.includeInNet,
      creditLimitCents: creditLimitCents ?? this.creditLimitCents,
      billDay: billDay ?? this.billDay,
      repayDay: repayDay ?? this.repayDay,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $AssetsTable.$converterkind.toSql(kind.value),
      );
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (valueCents.present) {
      map['value_cents'] = Variable<int>(valueCents.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (archived.present) {
      map['archived'] = Variable<bool>(archived.value);
    }
    if (includeInNet.present) {
      map['include_in_net'] = Variable<bool>(includeInNet.value);
    }
    if (creditLimitCents.present) {
      map['credit_limit_cents'] = Variable<int>(creditLimitCents.value);
    }
    if (billDay.present) {
      map['bill_day'] = Variable<int>(billDay.value);
    }
    if (repayDay.present) {
      map['repay_day'] = Variable<int>(repayDay.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('category: $category, ')
          ..write('valueCents: $valueCents, ')
          ..write('note: $note, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('archived: $archived, ')
          ..write('includeInNet: $includeInNet, ')
          ..write('creditLimitCents: $creditLimitCents, ')
          ..write('billDay: $billDay, ')
          ..write('repayDay: $repayDay, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AssetSnapshotsTable extends AssetSnapshots
    with TableInfo<$AssetSnapshotsTable, AssetSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AssetSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<int> assetId = GeneratedColumn<int>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueCentsMeta = const VerificationMeta(
    'valueCents',
  );
  @override
  late final GeneratedColumn<int> valueCents = GeneratedColumn<int>(
    'value_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    day,
    valueCents,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'asset_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<AssetSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('value_cents')) {
      context.handle(
        _valueCentsMeta,
        valueCents.isAcceptableOrUnknown(data['value_cents']!, _valueCentsMeta),
      );
    } else if (isInserting) {
      context.missing(_valueCentsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AssetSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AssetSnapshot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}asset_id'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      valueCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value_cents'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AssetSnapshotsTable createAlias(String alias) {
    return $AssetSnapshotsTable(attachedDatabase, alias);
  }
}

class AssetSnapshot extends DataClass implements Insertable<AssetSnapshot> {
  final int id;

  /// 所属资产
  final int assetId;

  /// 快照日期，格式 `yyyy-MM-dd`
  final String day;

  /// 快照时刻的市值，单位：分（恒为正数，负债由资产 kind 区分）
  final int valueCents;

  /// 快照时间：同一天多次更新时用于取"当天最后一条"
  final DateTime createdAt;
  const AssetSnapshot({
    required this.id,
    required this.assetId,
    required this.day,
    required this.valueCents,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['asset_id'] = Variable<int>(assetId);
    map['day'] = Variable<String>(day);
    map['value_cents'] = Variable<int>(valueCents);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AssetSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return AssetSnapshotsCompanion(
      id: Value(id),
      assetId: Value(assetId),
      day: Value(day),
      valueCents: Value(valueCents),
      createdAt: Value(createdAt),
    );
  }

  factory AssetSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AssetSnapshot(
      id: serializer.fromJson<int>(json['id']),
      assetId: serializer.fromJson<int>(json['assetId']),
      day: serializer.fromJson<String>(json['day']),
      valueCents: serializer.fromJson<int>(json['valueCents']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'assetId': serializer.toJson<int>(assetId),
      'day': serializer.toJson<String>(day),
      'valueCents': serializer.toJson<int>(valueCents),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  AssetSnapshot copyWith({
    int? id,
    int? assetId,
    String? day,
    int? valueCents,
    DateTime? createdAt,
  }) => AssetSnapshot(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    day: day ?? this.day,
    valueCents: valueCents ?? this.valueCents,
    createdAt: createdAt ?? this.createdAt,
  );
  AssetSnapshot copyWithCompanion(AssetSnapshotsCompanion data) {
    return AssetSnapshot(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      day: data.day.present ? data.day.value : this.day,
      valueCents: data.valueCents.present
          ? data.valueCents.value
          : this.valueCents,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AssetSnapshot(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('day: $day, ')
          ..write('valueCents: $valueCents, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, assetId, day, valueCents, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AssetSnapshot &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.day == this.day &&
          other.valueCents == this.valueCents &&
          other.createdAt == this.createdAt);
}

class AssetSnapshotsCompanion extends UpdateCompanion<AssetSnapshot> {
  final Value<int> id;
  final Value<int> assetId;
  final Value<String> day;
  final Value<int> valueCents;
  final Value<DateTime> createdAt;
  const AssetSnapshotsCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.day = const Value.absent(),
    this.valueCents = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  AssetSnapshotsCompanion.insert({
    this.id = const Value.absent(),
    required int assetId,
    required String day,
    required int valueCents,
    this.createdAt = const Value.absent(),
  }) : assetId = Value(assetId),
       day = Value(day),
       valueCents = Value(valueCents);
  static Insertable<AssetSnapshot> custom({
    Expression<int>? id,
    Expression<int>? assetId,
    Expression<String>? day,
    Expression<int>? valueCents,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (day != null) 'day': day,
      if (valueCents != null) 'value_cents': valueCents,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  AssetSnapshotsCompanion copyWith({
    Value<int>? id,
    Value<int>? assetId,
    Value<String>? day,
    Value<int>? valueCents,
    Value<DateTime>? createdAt,
  }) {
    return AssetSnapshotsCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      day: day ?? this.day,
      valueCents: valueCents ?? this.valueCents,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<int>(assetId.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (valueCents.present) {
      map['value_cents'] = Variable<int>(valueCents.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AssetSnapshotsCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('day: $day, ')
          ..write('valueCents: $valueCents, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $DebtNotesTable extends DebtNotes
    with TableInfo<$DebtNotesTable, DebtNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DebtNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<DebtDirection, int> direction =
      GeneratedColumn<int>(
        'direction',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<DebtDirection>($DebtNotesTable.$converterdirection);
  static const VerificationMeta _personNameMeta = const VerificationMeta(
    'personName',
  );
  @override
  late final GeneratedColumn<String> personName = GeneratedColumn<String>(
    'person_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _relatedAssetIdMeta = const VerificationMeta(
    'relatedAssetId',
  );
  @override
  late final GeneratedColumn<int> relatedAssetId = GeneratedColumn<int>(
    'related_asset_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _borrowedAtMeta = const VerificationMeta(
    'borrowedAt',
  );
  @override
  late final GeneratedColumn<DateTime> borrowedAt = GeneratedColumn<DateTime>(
    'borrowed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repayDueAtMeta = const VerificationMeta(
    'repayDueAt',
  );
  @override
  late final GeneratedColumn<DateTime> repayDueAt = GeneratedColumn<DateTime>(
    'repay_due_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _includeInTotalMeta = const VerificationMeta(
    'includeInTotal',
  );
  @override
  late final GeneratedColumn<bool> includeInTotal = GeneratedColumn<bool>(
    'include_in_total',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("include_in_total" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    direction,
    personName,
    amountCents,
    note,
    relatedAssetId,
    borrowedAt,
    repayDueAt,
    includeInTotal,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'debt_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<DebtNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('person_name')) {
      context.handle(
        _personNameMeta,
        personName.isAcceptableOrUnknown(data['person_name']!, _personNameMeta),
      );
    } else if (isInserting) {
      context.missing(_personNameMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('related_asset_id')) {
      context.handle(
        _relatedAssetIdMeta,
        relatedAssetId.isAcceptableOrUnknown(
          data['related_asset_id']!,
          _relatedAssetIdMeta,
        ),
      );
    }
    if (data.containsKey('borrowed_at')) {
      context.handle(
        _borrowedAtMeta,
        borrowedAt.isAcceptableOrUnknown(data['borrowed_at']!, _borrowedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_borrowedAtMeta);
    }
    if (data.containsKey('repay_due_at')) {
      context.handle(
        _repayDueAtMeta,
        repayDueAt.isAcceptableOrUnknown(
          data['repay_due_at']!,
          _repayDueAtMeta,
        ),
      );
    }
    if (data.containsKey('include_in_total')) {
      context.handle(
        _includeInTotalMeta,
        includeInTotal.isAcceptableOrUnknown(
          data['include_in_total']!,
          _includeInTotalMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DebtNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DebtNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      direction: $DebtNotesTable.$converterdirection.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}direction'],
        )!,
      ),
      personName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_name'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      relatedAssetId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}related_asset_id'],
      ),
      borrowedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}borrowed_at'],
      )!,
      repayDueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}repay_due_at'],
      ),
      includeInTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}include_in_total'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DebtNotesTable createAlias(String alias) {
    return $DebtNotesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<DebtDirection, int, int> $converterdirection =
      const EnumIndexConverter<DebtDirection>(DebtDirection.values);
}

class DebtNote extends DataClass implements Insertable<DebtNote> {
  final int id;

  /// 方向：借出 / 借入
  final DebtDirection direction;

  /// 借款人姓名（借出 = 对方名字；借入 = 出借人名字）
  final String personName;

  /// 金额，单位：分（恒为正数，方向由 [direction] 区分）
  final int amountCents;

  /// 备注，可为空
  final String? note;

  /// 关联的资金类账户：借出 = 钱从此账户出（编辑时提示余额变化），
  /// 借入 = 钱累加到此账户；null = 不关联
  final int? relatedAssetId;

  /// 借款日期（含时间）
  final DateTime borrowedAt;

  /// 约定还款日期；null = 未约定
  final DateTime? repayDueAt;

  /// 是否计入总借出/总借入：false = 仅台账记录，不参与净值统计
  final bool includeInTotal;

  /// 创建时间
  final DateTime createdAt;

  /// 最近一次信息更新时间
  final DateTime updatedAt;
  const DebtNote({
    required this.id,
    required this.direction,
    required this.personName,
    required this.amountCents,
    this.note,
    this.relatedAssetId,
    required this.borrowedAt,
    this.repayDueAt,
    required this.includeInTotal,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['direction'] = Variable<int>(
        $DebtNotesTable.$converterdirection.toSql(direction),
      );
    }
    map['person_name'] = Variable<String>(personName);
    map['amount_cents'] = Variable<int>(amountCents);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || relatedAssetId != null) {
      map['related_asset_id'] = Variable<int>(relatedAssetId);
    }
    map['borrowed_at'] = Variable<DateTime>(borrowedAt);
    if (!nullToAbsent || repayDueAt != null) {
      map['repay_due_at'] = Variable<DateTime>(repayDueAt);
    }
    map['include_in_total'] = Variable<bool>(includeInTotal);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DebtNotesCompanion toCompanion(bool nullToAbsent) {
    return DebtNotesCompanion(
      id: Value(id),
      direction: Value(direction),
      personName: Value(personName),
      amountCents: Value(amountCents),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      relatedAssetId: relatedAssetId == null && nullToAbsent
          ? const Value.absent()
          : Value(relatedAssetId),
      borrowedAt: Value(borrowedAt),
      repayDueAt: repayDueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(repayDueAt),
      includeInTotal: Value(includeInTotal),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DebtNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DebtNote(
      id: serializer.fromJson<int>(json['id']),
      direction: $DebtNotesTable.$converterdirection.fromJson(
        serializer.fromJson<int>(json['direction']),
      ),
      personName: serializer.fromJson<String>(json['personName']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      note: serializer.fromJson<String?>(json['note']),
      relatedAssetId: serializer.fromJson<int?>(json['relatedAssetId']),
      borrowedAt: serializer.fromJson<DateTime>(json['borrowedAt']),
      repayDueAt: serializer.fromJson<DateTime?>(json['repayDueAt']),
      includeInTotal: serializer.fromJson<bool>(json['includeInTotal']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'direction': serializer.toJson<int>(
        $DebtNotesTable.$converterdirection.toJson(direction),
      ),
      'personName': serializer.toJson<String>(personName),
      'amountCents': serializer.toJson<int>(amountCents),
      'note': serializer.toJson<String?>(note),
      'relatedAssetId': serializer.toJson<int?>(relatedAssetId),
      'borrowedAt': serializer.toJson<DateTime>(borrowedAt),
      'repayDueAt': serializer.toJson<DateTime?>(repayDueAt),
      'includeInTotal': serializer.toJson<bool>(includeInTotal),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DebtNote copyWith({
    int? id,
    DebtDirection? direction,
    String? personName,
    int? amountCents,
    Value<String?> note = const Value.absent(),
    Value<int?> relatedAssetId = const Value.absent(),
    DateTime? borrowedAt,
    Value<DateTime?> repayDueAt = const Value.absent(),
    bool? includeInTotal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DebtNote(
    id: id ?? this.id,
    direction: direction ?? this.direction,
    personName: personName ?? this.personName,
    amountCents: amountCents ?? this.amountCents,
    note: note.present ? note.value : this.note,
    relatedAssetId: relatedAssetId.present
        ? relatedAssetId.value
        : this.relatedAssetId,
    borrowedAt: borrowedAt ?? this.borrowedAt,
    repayDueAt: repayDueAt.present ? repayDueAt.value : this.repayDueAt,
    includeInTotal: includeInTotal ?? this.includeInTotal,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DebtNote copyWithCompanion(DebtNotesCompanion data) {
    return DebtNote(
      id: data.id.present ? data.id.value : this.id,
      direction: data.direction.present ? data.direction.value : this.direction,
      personName: data.personName.present
          ? data.personName.value
          : this.personName,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      note: data.note.present ? data.note.value : this.note,
      relatedAssetId: data.relatedAssetId.present
          ? data.relatedAssetId.value
          : this.relatedAssetId,
      borrowedAt: data.borrowedAt.present
          ? data.borrowedAt.value
          : this.borrowedAt,
      repayDueAt: data.repayDueAt.present
          ? data.repayDueAt.value
          : this.repayDueAt,
      includeInTotal: data.includeInTotal.present
          ? data.includeInTotal.value
          : this.includeInTotal,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DebtNote(')
          ..write('id: $id, ')
          ..write('direction: $direction, ')
          ..write('personName: $personName, ')
          ..write('amountCents: $amountCents, ')
          ..write('note: $note, ')
          ..write('relatedAssetId: $relatedAssetId, ')
          ..write('borrowedAt: $borrowedAt, ')
          ..write('repayDueAt: $repayDueAt, ')
          ..write('includeInTotal: $includeInTotal, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    direction,
    personName,
    amountCents,
    note,
    relatedAssetId,
    borrowedAt,
    repayDueAt,
    includeInTotal,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DebtNote &&
          other.id == this.id &&
          other.direction == this.direction &&
          other.personName == this.personName &&
          other.amountCents == this.amountCents &&
          other.note == this.note &&
          other.relatedAssetId == this.relatedAssetId &&
          other.borrowedAt == this.borrowedAt &&
          other.repayDueAt == this.repayDueAt &&
          other.includeInTotal == this.includeInTotal &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DebtNotesCompanion extends UpdateCompanion<DebtNote> {
  final Value<int> id;
  final Value<DebtDirection> direction;
  final Value<String> personName;
  final Value<int> amountCents;
  final Value<String?> note;
  final Value<int?> relatedAssetId;
  final Value<DateTime> borrowedAt;
  final Value<DateTime?> repayDueAt;
  final Value<bool> includeInTotal;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DebtNotesCompanion({
    this.id = const Value.absent(),
    this.direction = const Value.absent(),
    this.personName = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.note = const Value.absent(),
    this.relatedAssetId = const Value.absent(),
    this.borrowedAt = const Value.absent(),
    this.repayDueAt = const Value.absent(),
    this.includeInTotal = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DebtNotesCompanion.insert({
    this.id = const Value.absent(),
    required DebtDirection direction,
    required String personName,
    required int amountCents,
    this.note = const Value.absent(),
    this.relatedAssetId = const Value.absent(),
    required DateTime borrowedAt,
    this.repayDueAt = const Value.absent(),
    this.includeInTotal = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : direction = Value(direction),
       personName = Value(personName),
       amountCents = Value(amountCents),
       borrowedAt = Value(borrowedAt);
  static Insertable<DebtNote> custom({
    Expression<int>? id,
    Expression<int>? direction,
    Expression<String>? personName,
    Expression<int>? amountCents,
    Expression<String>? note,
    Expression<int>? relatedAssetId,
    Expression<DateTime>? borrowedAt,
    Expression<DateTime>? repayDueAt,
    Expression<bool>? includeInTotal,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (direction != null) 'direction': direction,
      if (personName != null) 'person_name': personName,
      if (amountCents != null) 'amount_cents': amountCents,
      if (note != null) 'note': note,
      if (relatedAssetId != null) 'related_asset_id': relatedAssetId,
      if (borrowedAt != null) 'borrowed_at': borrowedAt,
      if (repayDueAt != null) 'repay_due_at': repayDueAt,
      if (includeInTotal != null) 'include_in_total': includeInTotal,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DebtNotesCompanion copyWith({
    Value<int>? id,
    Value<DebtDirection>? direction,
    Value<String>? personName,
    Value<int>? amountCents,
    Value<String?>? note,
    Value<int?>? relatedAssetId,
    Value<DateTime>? borrowedAt,
    Value<DateTime?>? repayDueAt,
    Value<bool>? includeInTotal,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return DebtNotesCompanion(
      id: id ?? this.id,
      direction: direction ?? this.direction,
      personName: personName ?? this.personName,
      amountCents: amountCents ?? this.amountCents,
      note: note ?? this.note,
      relatedAssetId: relatedAssetId ?? this.relatedAssetId,
      borrowedAt: borrowedAt ?? this.borrowedAt,
      repayDueAt: repayDueAt ?? this.repayDueAt,
      includeInTotal: includeInTotal ?? this.includeInTotal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (direction.present) {
      map['direction'] = Variable<int>(
        $DebtNotesTable.$converterdirection.toSql(direction.value),
      );
    }
    if (personName.present) {
      map['person_name'] = Variable<String>(personName.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (relatedAssetId.present) {
      map['related_asset_id'] = Variable<int>(relatedAssetId.value);
    }
    if (borrowedAt.present) {
      map['borrowed_at'] = Variable<DateTime>(borrowedAt.value);
    }
    if (repayDueAt.present) {
      map['repay_due_at'] = Variable<DateTime>(repayDueAt.value);
    }
    if (includeInTotal.present) {
      map['include_in_total'] = Variable<bool>(includeInTotal.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DebtNotesCompanion(')
          ..write('id: $id, ')
          ..write('direction: $direction, ')
          ..write('personName: $personName, ')
          ..write('amountCents: $amountCents, ')
          ..write('note: $note, ')
          ..write('relatedAssetId: $relatedAssetId, ')
          ..write('borrowedAt: $borrowedAt, ')
          ..write('repayDueAt: $repayDueAt, ')
          ..write('includeInTotal: $includeInTotal, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $DebtNoteImagesTable extends DebtNoteImages
    with TableInfo<$DebtNoteImagesTable, DebtNoteImage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DebtNoteImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<int> noteId = GeneratedColumn<int>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectKeyMeta = const VerificationMeta(
    'objectKey',
  );
  @override
  late final GeneratedColumn<String> objectKey = GeneratedColumn<String>(
    'object_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BillImageUploadState, int>
  uploadState =
      GeneratedColumn<int>(
        'upload_state',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<BillImageUploadState>(
        $DebtNoteImagesTable.$converteruploadState,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    objectKey,
    localPath,
    uploadState,
    createdAt,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'debt_note_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<DebtNoteImage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('object_key')) {
      context.handle(
        _objectKeyMeta,
        objectKey.isAcceptableOrUnknown(data['object_key']!, _objectKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_objectKeyMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DebtNoteImage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DebtNoteImage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}note_id'],
      )!,
      objectKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_key'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      uploadState: $DebtNoteImagesTable.$converteruploadState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}upload_state'],
        )!,
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $DebtNoteImagesTable createAlias(String alias) {
    return $DebtNoteImagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BillImageUploadState, int, int>
  $converteruploadState = const EnumIndexConverter<BillImageUploadState>(
    BillImageUploadState.values,
  );
}

class DebtNoteImage extends DataClass implements Insertable<DebtNoteImage> {
  final int id;

  /// 所属借条：删除借条时由仓储级联清理记录 / 本地文件 / 云端对象
  final int noteId;

  /// 云端对象键（bucket 内唯一路径），生成规则见 DebtNoteRepository
  final String objectKey;

  /// 本地缓存文件绝对路径（应用支持目录 debt_photos/{noteId}/ 下）
  final String localPath;

  /// 上传状态
  final BillImageUploadState uploadState;

  /// 添加时间
  final DateTime createdAt;

  /// 同一借条内的展示顺序（按添加先后）
  final int sort;
  const DebtNoteImage({
    required this.id,
    required this.noteId,
    required this.objectKey,
    required this.localPath,
    required this.uploadState,
    required this.createdAt,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['note_id'] = Variable<int>(noteId);
    map['object_key'] = Variable<String>(objectKey);
    map['local_path'] = Variable<String>(localPath);
    {
      map['upload_state'] = Variable<int>(
        $DebtNoteImagesTable.$converteruploadState.toSql(uploadState),
      );
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  DebtNoteImagesCompanion toCompanion(bool nullToAbsent) {
    return DebtNoteImagesCompanion(
      id: Value(id),
      noteId: Value(noteId),
      objectKey: Value(objectKey),
      localPath: Value(localPath),
      uploadState: Value(uploadState),
      createdAt: Value(createdAt),
      sort: Value(sort),
    );
  }

  factory DebtNoteImage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DebtNoteImage(
      id: serializer.fromJson<int>(json['id']),
      noteId: serializer.fromJson<int>(json['noteId']),
      objectKey: serializer.fromJson<String>(json['objectKey']),
      localPath: serializer.fromJson<String>(json['localPath']),
      uploadState: $DebtNoteImagesTable.$converteruploadState.fromJson(
        serializer.fromJson<int>(json['uploadState']),
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'noteId': serializer.toJson<int>(noteId),
      'objectKey': serializer.toJson<String>(objectKey),
      'localPath': serializer.toJson<String>(localPath),
      'uploadState': serializer.toJson<int>(
        $DebtNoteImagesTable.$converteruploadState.toJson(uploadState),
      ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sort': serializer.toJson<int>(sort),
    };
  }

  DebtNoteImage copyWith({
    int? id,
    int? noteId,
    String? objectKey,
    String? localPath,
    BillImageUploadState? uploadState,
    DateTime? createdAt,
    int? sort,
  }) => DebtNoteImage(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    objectKey: objectKey ?? this.objectKey,
    localPath: localPath ?? this.localPath,
    uploadState: uploadState ?? this.uploadState,
    createdAt: createdAt ?? this.createdAt,
    sort: sort ?? this.sort,
  );
  DebtNoteImage copyWithCompanion(DebtNoteImagesCompanion data) {
    return DebtNoteImage(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      objectKey: data.objectKey.present ? data.objectKey.value : this.objectKey,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      uploadState: data.uploadState.present
          ? data.uploadState.value
          : this.uploadState,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DebtNoteImage(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('objectKey: $objectKey, ')
          ..write('localPath: $localPath, ')
          ..write('uploadState: $uploadState, ')
          ..write('createdAt: $createdAt, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    objectKey,
    localPath,
    uploadState,
    createdAt,
    sort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DebtNoteImage &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.objectKey == this.objectKey &&
          other.localPath == this.localPath &&
          other.uploadState == this.uploadState &&
          other.createdAt == this.createdAt &&
          other.sort == this.sort);
}

class DebtNoteImagesCompanion extends UpdateCompanion<DebtNoteImage> {
  final Value<int> id;
  final Value<int> noteId;
  final Value<String> objectKey;
  final Value<String> localPath;
  final Value<BillImageUploadState> uploadState;
  final Value<DateTime> createdAt;
  final Value<int> sort;
  const DebtNoteImagesCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.objectKey = const Value.absent(),
    this.localPath = const Value.absent(),
    this.uploadState = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sort = const Value.absent(),
  });
  DebtNoteImagesCompanion.insert({
    this.id = const Value.absent(),
    required int noteId,
    required String objectKey,
    required String localPath,
    required BillImageUploadState uploadState,
    this.createdAt = const Value.absent(),
    this.sort = const Value.absent(),
  }) : noteId = Value(noteId),
       objectKey = Value(objectKey),
       localPath = Value(localPath),
       uploadState = Value(uploadState);
  static Insertable<DebtNoteImage> custom({
    Expression<int>? id,
    Expression<int>? noteId,
    Expression<String>? objectKey,
    Expression<String>? localPath,
    Expression<int>? uploadState,
    Expression<DateTime>? createdAt,
    Expression<int>? sort,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (objectKey != null) 'object_key': objectKey,
      if (localPath != null) 'local_path': localPath,
      if (uploadState != null) 'upload_state': uploadState,
      if (createdAt != null) 'created_at': createdAt,
      if (sort != null) 'sort': sort,
    });
  }

  DebtNoteImagesCompanion copyWith({
    Value<int>? id,
    Value<int>? noteId,
    Value<String>? objectKey,
    Value<String>? localPath,
    Value<BillImageUploadState>? uploadState,
    Value<DateTime>? createdAt,
    Value<int>? sort,
  }) {
    return DebtNoteImagesCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      objectKey: objectKey ?? this.objectKey,
      localPath: localPath ?? this.localPath,
      uploadState: uploadState ?? this.uploadState,
      createdAt: createdAt ?? this.createdAt,
      sort: sort ?? this.sort,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<int>(noteId.value);
    }
    if (objectKey.present) {
      map['object_key'] = Variable<String>(objectKey.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (uploadState.present) {
      map['upload_state'] = Variable<int>(
        $DebtNoteImagesTable.$converteruploadState.toSql(uploadState.value),
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DebtNoteImagesCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('objectKey: $objectKey, ')
          ..write('localPath: $localPath, ')
          ..write('uploadState: $uploadState, ')
          ..write('createdAt: $createdAt, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $BillsTable bills = $BillsTable(this);
  late final $BudgetsTable budgets = $BudgetsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $BillTagsTable billTags = $BillTagsTable(this);
  late final $BillImagesTable billImages = $BillImagesTable(this);
  late final $AssetsTable assets = $AssetsTable(this);
  late final $AssetSnapshotsTable assetSnapshots = $AssetSnapshotsTable(this);
  late final $DebtNotesTable debtNotes = $DebtNotesTable(this);
  late final $DebtNoteImagesTable debtNoteImages = $DebtNoteImagesTable(this);
  late final Index billsDateCreated = Index(
    'bills_date_created',
    'CREATE INDEX bills_date_created ON bills (date, created_at)',
  );
  late final Index billsCategory = Index(
    'bills_category',
    'CREATE INDEX bills_category ON bills (category_id)',
  );
  late final Index tagsName = Index(
    'tags_name',
    'CREATE INDEX tags_name ON tags (name)',
  );
  late final Index billImagesBill = Index(
    'bill_images_bill',
    'CREATE INDEX bill_images_bill ON bill_images (bill_id)',
  );
  late final Index assetSnapshotsAssetDay = Index(
    'asset_snapshots_asset_day',
    'CREATE INDEX asset_snapshots_asset_day ON asset_snapshots (asset_id, day)',
  );
  late final Index debtNoteImagesNote = Index(
    'debt_note_images_note',
    'CREATE INDEX debt_note_images_note ON debt_note_images (note_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    bills,
    budgets,
    tags,
    billTags,
    billImages,
    assets,
    assetSnapshots,
    debtNotes,
    debtNoteImages,
    billsDateCreated,
    billsCategory,
    tagsName,
    billImagesBill,
    assetSnapshotsAssetDay,
    debtNoteImagesNote,
  ];
}

typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      required String name,
      required int iconCode,
      required int colorValue,
      required BillType type,
      Value<int?> parentId,
      Value<int> sortOrder,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> iconCode,
      Value<int> colorValue,
      Value<BillType> type,
      Value<int?> parentId,
      Value<int> sortOrder,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get iconCode => $composableBuilder(
    column: $table.iconCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BillType, BillType, int> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get iconCode => $composableBuilder(
    column: $table.iconCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get iconCode =>
      $composableBuilder(column: $table.iconCode, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<BillType, int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
          Category,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> iconCode = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<BillType> type = const Value.absent(),
                Value<int?> parentId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                iconCode: iconCode,
                colorValue: colorValue,
                type: type,
                parentId: parentId,
                sortOrder: sortOrder,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int iconCode,
                required int colorValue,
                required BillType type,
                Value<int?> parentId = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                iconCode: iconCode,
                colorValue: colorValue,
                type: type,
                parentId: parentId,
                sortOrder: sortOrder,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
      Category,
      PrefetchHooks Function()
    >;
typedef $$BillsTableCreateCompanionBuilder =
    BillsCompanion Function({
      Value<int> id,
      required BillType type,
      required int amountCents,
      Value<int?> discountCents,
      Value<int?> categoryId,
      Value<String?> note,
      required DateTime date,
      Value<int?> timeMinute,
      Value<String?> location,
      Value<String?> locationFull,
      Value<double?> lat,
      Value<double?> lng,
      Value<DateTime> createdAt,
      Value<int?> importBatchId,
      Value<int?> assetId,
      Value<int?> toAssetId,
    });
typedef $$BillsTableUpdateCompanionBuilder =
    BillsCompanion Function({
      Value<int> id,
      Value<BillType> type,
      Value<int> amountCents,
      Value<int?> discountCents,
      Value<int?> categoryId,
      Value<String?> note,
      Value<DateTime> date,
      Value<int?> timeMinute,
      Value<String?> location,
      Value<String?> locationFull,
      Value<double?> lat,
      Value<double?> lng,
      Value<DateTime> createdAt,
      Value<int?> importBatchId,
      Value<int?> assetId,
      Value<int?> toAssetId,
    });

class $$BillsTableFilterComposer extends Composer<_$AppDatabase, $BillsTable> {
  $$BillsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BillType, BillType, int> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discountCents => $composableBuilder(
    column: $table.discountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timeMinute => $composableBuilder(
    column: $table.timeMinute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationFull => $composableBuilder(
    column: $table.locationFull,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get importBatchId => $composableBuilder(
    column: $table.importBatchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get toAssetId => $composableBuilder(
    column: $table.toAssetId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BillsTableOrderingComposer
    extends Composer<_$AppDatabase, $BillsTable> {
  $$BillsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discountCents => $composableBuilder(
    column: $table.discountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timeMinute => $composableBuilder(
    column: $table.timeMinute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationFull => $composableBuilder(
    column: $table.locationFull,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get importBatchId => $composableBuilder(
    column: $table.importBatchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get toAssetId => $composableBuilder(
    column: $table.toAssetId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BillsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BillsTable> {
  $$BillsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BillType, int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discountCents => $composableBuilder(
    column: $table.discountCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get timeMinute => $composableBuilder(
    column: $table.timeMinute,
    builder: (column) => column,
  );

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get locationFull => $composableBuilder(
    column: $table.locationFull,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get importBatchId => $composableBuilder(
    column: $table.importBatchId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<int> get toAssetId =>
      $composableBuilder(column: $table.toAssetId, builder: (column) => column);
}

class $$BillsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BillsTable,
          Bill,
          $$BillsTableFilterComposer,
          $$BillsTableOrderingComposer,
          $$BillsTableAnnotationComposer,
          $$BillsTableCreateCompanionBuilder,
          $$BillsTableUpdateCompanionBuilder,
          (Bill, BaseReferences<_$AppDatabase, $BillsTable, Bill>),
          Bill,
          PrefetchHooks Function()
        > {
  $$BillsTableTableManager(_$AppDatabase db, $BillsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BillsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BillsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BillsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<BillType> type = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<int?> discountCents = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<int?> timeMinute = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> locationFull = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int?> importBatchId = const Value.absent(),
                Value<int?> assetId = const Value.absent(),
                Value<int?> toAssetId = const Value.absent(),
              }) => BillsCompanion(
                id: id,
                type: type,
                amountCents: amountCents,
                discountCents: discountCents,
                categoryId: categoryId,
                note: note,
                date: date,
                timeMinute: timeMinute,
                location: location,
                locationFull: locationFull,
                lat: lat,
                lng: lng,
                createdAt: createdAt,
                importBatchId: importBatchId,
                assetId: assetId,
                toAssetId: toAssetId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required BillType type,
                required int amountCents,
                Value<int?> discountCents = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required DateTime date,
                Value<int?> timeMinute = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> locationFull = const Value.absent(),
                Value<double?> lat = const Value.absent(),
                Value<double?> lng = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int?> importBatchId = const Value.absent(),
                Value<int?> assetId = const Value.absent(),
                Value<int?> toAssetId = const Value.absent(),
              }) => BillsCompanion.insert(
                id: id,
                type: type,
                amountCents: amountCents,
                discountCents: discountCents,
                categoryId: categoryId,
                note: note,
                date: date,
                timeMinute: timeMinute,
                location: location,
                locationFull: locationFull,
                lat: lat,
                lng: lng,
                createdAt: createdAt,
                importBatchId: importBatchId,
                assetId: assetId,
                toAssetId: toAssetId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BillsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BillsTable,
      Bill,
      $$BillsTableFilterComposer,
      $$BillsTableOrderingComposer,
      $$BillsTableAnnotationComposer,
      $$BillsTableCreateCompanionBuilder,
      $$BillsTableUpdateCompanionBuilder,
      (Bill, BaseReferences<_$AppDatabase, $BillsTable, Bill>),
      Bill,
      PrefetchHooks Function()
    >;
typedef $$BudgetsTableCreateCompanionBuilder =
    BudgetsCompanion Function({
      Value<int> id,
      required String month,
      required int amountCents,
      Value<int> categoryId,
    });
typedef $$BudgetsTableUpdateCompanionBuilder =
    BudgetsCompanion Function({
      Value<int> id,
      Value<String> month,
      Value<int> amountCents,
      Value<int> categoryId,
    });

class $$BudgetsTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BudgetsTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get month => $composableBuilder(
    column: $table.month,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BudgetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get month =>
      $composableBuilder(column: $table.month, builder: (column) => column);

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );
}

class $$BudgetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetsTable,
          Budget,
          $$BudgetsTableFilterComposer,
          $$BudgetsTableOrderingComposer,
          $$BudgetsTableAnnotationComposer,
          $$BudgetsTableCreateCompanionBuilder,
          $$BudgetsTableUpdateCompanionBuilder,
          (Budget, BaseReferences<_$AppDatabase, $BudgetsTable, Budget>),
          Budget,
          PrefetchHooks Function()
        > {
  $$BudgetsTableTableManager(_$AppDatabase db, $BudgetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> month = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<int> categoryId = const Value.absent(),
              }) => BudgetsCompanion(
                id: id,
                month: month,
                amountCents: amountCents,
                categoryId: categoryId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String month,
                required int amountCents,
                Value<int> categoryId = const Value.absent(),
              }) => BudgetsCompanion.insert(
                id: id,
                month: month,
                amountCents: amountCents,
                categoryId: categoryId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BudgetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetsTable,
      Budget,
      $$BudgetsTableFilterComposer,
      $$BudgetsTableOrderingComposer,
      $$BudgetsTableAnnotationComposer,
      $$BudgetsTableCreateCompanionBuilder,
      $$BudgetsTableUpdateCompanionBuilder,
      (Budget, BaseReferences<_$AppDatabase, $BudgetsTable, Budget>),
      Budget,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      required String name,
      required int color,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> color,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
    });

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
          Tag,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                color: color,
                sortOrder: sortOrder,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int color,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                color: color,
                sortOrder: sortOrder,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
      Tag,
      PrefetchHooks Function()
    >;
typedef $$BillTagsTableCreateCompanionBuilder =
    BillTagsCompanion Function({
      required int billId,
      required int tagId,
      Value<int> rowid,
    });
typedef $$BillTagsTableUpdateCompanionBuilder =
    BillTagsCompanion Function({
      Value<int> billId,
      Value<int> tagId,
      Value<int> rowid,
    });

class $$BillTagsTableFilterComposer
    extends Composer<_$AppDatabase, $BillTagsTable> {
  $$BillTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get billId => $composableBuilder(
    column: $table.billId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BillTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $BillTagsTable> {
  $$BillTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get billId => $composableBuilder(
    column: $table.billId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BillTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BillTagsTable> {
  $$BillTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get billId =>
      $composableBuilder(column: $table.billId, builder: (column) => column);

  GeneratedColumn<int> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);
}

class $$BillTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BillTagsTable,
          BillTag,
          $$BillTagsTableFilterComposer,
          $$BillTagsTableOrderingComposer,
          $$BillTagsTableAnnotationComposer,
          $$BillTagsTableCreateCompanionBuilder,
          $$BillTagsTableUpdateCompanionBuilder,
          (BillTag, BaseReferences<_$AppDatabase, $BillTagsTable, BillTag>),
          BillTag,
          PrefetchHooks Function()
        > {
  $$BillTagsTableTableManager(_$AppDatabase db, $BillTagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BillTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BillTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BillTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> billId = const Value.absent(),
                Value<int> tagId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  BillTagsCompanion(billId: billId, tagId: tagId, rowid: rowid),
          createCompanionCallback:
              ({
                required int billId,
                required int tagId,
                Value<int> rowid = const Value.absent(),
              }) => BillTagsCompanion.insert(
                billId: billId,
                tagId: tagId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BillTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BillTagsTable,
      BillTag,
      $$BillTagsTableFilterComposer,
      $$BillTagsTableOrderingComposer,
      $$BillTagsTableAnnotationComposer,
      $$BillTagsTableCreateCompanionBuilder,
      $$BillTagsTableUpdateCompanionBuilder,
      (BillTag, BaseReferences<_$AppDatabase, $BillTagsTable, BillTag>),
      BillTag,
      PrefetchHooks Function()
    >;
typedef $$BillImagesTableCreateCompanionBuilder =
    BillImagesCompanion Function({
      Value<int> id,
      required int billId,
      required String objectKey,
      required String localPath,
      required BillImageUploadState uploadState,
      Value<DateTime> createdAt,
      Value<int> sort,
    });
typedef $$BillImagesTableUpdateCompanionBuilder =
    BillImagesCompanion Function({
      Value<int> id,
      Value<int> billId,
      Value<String> objectKey,
      Value<String> localPath,
      Value<BillImageUploadState> uploadState,
      Value<DateTime> createdAt,
      Value<int> sort,
    });

class $$BillImagesTableFilterComposer
    extends Composer<_$AppDatabase, $BillImagesTable> {
  $$BillImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get billId => $composableBuilder(
    column: $table.billId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectKey => $composableBuilder(
    column: $table.objectKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    BillImageUploadState,
    BillImageUploadState,
    int
  >
  get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BillImagesTableOrderingComposer
    extends Composer<_$AppDatabase, $BillImagesTable> {
  $$BillImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get billId => $composableBuilder(
    column: $table.billId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectKey => $composableBuilder(
    column: $table.objectKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BillImagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BillImagesTable> {
  $$BillImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get billId =>
      $composableBuilder(column: $table.billId, builder: (column) => column);

  GeneratedColumn<String> get objectKey =>
      $composableBuilder(column: $table.objectKey, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BillImageUploadState, int> get uploadState =>
      $composableBuilder(
        column: $table.uploadState,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$BillImagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BillImagesTable,
          BillImage,
          $$BillImagesTableFilterComposer,
          $$BillImagesTableOrderingComposer,
          $$BillImagesTableAnnotationComposer,
          $$BillImagesTableCreateCompanionBuilder,
          $$BillImagesTableUpdateCompanionBuilder,
          (
            BillImage,
            BaseReferences<_$AppDatabase, $BillImagesTable, BillImage>,
          ),
          BillImage,
          PrefetchHooks Function()
        > {
  $$BillImagesTableTableManager(_$AppDatabase db, $BillImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BillImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BillImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BillImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> billId = const Value.absent(),
                Value<String> objectKey = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<BillImageUploadState> uploadState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> sort = const Value.absent(),
              }) => BillImagesCompanion(
                id: id,
                billId: billId,
                objectKey: objectKey,
                localPath: localPath,
                uploadState: uploadState,
                createdAt: createdAt,
                sort: sort,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int billId,
                required String objectKey,
                required String localPath,
                required BillImageUploadState uploadState,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> sort = const Value.absent(),
              }) => BillImagesCompanion.insert(
                id: id,
                billId: billId,
                objectKey: objectKey,
                localPath: localPath,
                uploadState: uploadState,
                createdAt: createdAt,
                sort: sort,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BillImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BillImagesTable,
      BillImage,
      $$BillImagesTableFilterComposer,
      $$BillImagesTableOrderingComposer,
      $$BillImagesTableAnnotationComposer,
      $$BillImagesTableCreateCompanionBuilder,
      $$BillImagesTableUpdateCompanionBuilder,
      (BillImage, BaseReferences<_$AppDatabase, $BillImagesTable, BillImage>),
      BillImage,
      PrefetchHooks Function()
    >;
typedef $$AssetsTableCreateCompanionBuilder =
    AssetsCompanion Function({
      Value<int> id,
      required String name,
      required AssetKind kind,
      required String category,
      required int valueCents,
      Value<String?> note,
      Value<int> sortOrder,
      Value<bool> archived,
      Value<bool> includeInNet,
      Value<int?> creditLimitCents,
      Value<int?> billDay,
      Value<int?> repayDay,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$AssetsTableUpdateCompanionBuilder =
    AssetsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<AssetKind> kind,
      Value<String> category,
      Value<int> valueCents,
      Value<String?> note,
      Value<int> sortOrder,
      Value<bool> archived,
      Value<bool> includeInNet,
      Value<int?> creditLimitCents,
      Value<int?> billDay,
      Value<int?> repayDay,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$AssetsTableFilterComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AssetKind, AssetKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get valueCents => $composableBuilder(
    column: $table.valueCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includeInNet => $composableBuilder(
    column: $table.includeInNet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get creditLimitCents => $composableBuilder(
    column: $table.creditLimitCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get billDay => $composableBuilder(
    column: $table.billDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repayDay => $composableBuilder(
    column: $table.repayDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get valueCents => $composableBuilder(
    column: $table.valueCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includeInNet => $composableBuilder(
    column: $table.includeInNet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get creditLimitCents => $composableBuilder(
    column: $table.creditLimitCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get billDay => $composableBuilder(
    column: $table.billDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repayDay => $composableBuilder(
    column: $table.repayDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssetsTable> {
  $$AssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AssetKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get valueCents => $composableBuilder(
    column: $table.valueCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<bool> get includeInNet => $composableBuilder(
    column: $table.includeInNet,
    builder: (column) => column,
  );

  GeneratedColumn<int> get creditLimitCents => $composableBuilder(
    column: $table.creditLimitCents,
    builder: (column) => column,
  );

  GeneratedColumn<int> get billDay =>
      $composableBuilder(column: $table.billDay, builder: (column) => column);

  GeneratedColumn<int> get repayDay =>
      $composableBuilder(column: $table.repayDay, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssetsTable,
          Asset,
          $$AssetsTableFilterComposer,
          $$AssetsTableOrderingComposer,
          $$AssetsTableAnnotationComposer,
          $$AssetsTableCreateCompanionBuilder,
          $$AssetsTableUpdateCompanionBuilder,
          (Asset, BaseReferences<_$AppDatabase, $AssetsTable, Asset>),
          Asset,
          PrefetchHooks Function()
        > {
  $$AssetsTableTableManager(_$AppDatabase db, $AssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<AssetKind> kind = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<int> valueCents = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> includeInNet = const Value.absent(),
                Value<int?> creditLimitCents = const Value.absent(),
                Value<int?> billDay = const Value.absent(),
                Value<int?> repayDay = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AssetsCompanion(
                id: id,
                name: name,
                kind: kind,
                category: category,
                valueCents: valueCents,
                note: note,
                sortOrder: sortOrder,
                archived: archived,
                includeInNet: includeInNet,
                creditLimitCents: creditLimitCents,
                billDay: billDay,
                repayDay: repayDay,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required AssetKind kind,
                required String category,
                required int valueCents,
                Value<String?> note = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<bool> includeInNet = const Value.absent(),
                Value<int?> creditLimitCents = const Value.absent(),
                Value<int?> billDay = const Value.absent(),
                Value<int?> repayDay = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AssetsCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                category: category,
                valueCents: valueCents,
                note: note,
                sortOrder: sortOrder,
                archived: archived,
                includeInNet: includeInNet,
                creditLimitCents: creditLimitCents,
                billDay: billDay,
                repayDay: repayDay,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssetsTable,
      Asset,
      $$AssetsTableFilterComposer,
      $$AssetsTableOrderingComposer,
      $$AssetsTableAnnotationComposer,
      $$AssetsTableCreateCompanionBuilder,
      $$AssetsTableUpdateCompanionBuilder,
      (Asset, BaseReferences<_$AppDatabase, $AssetsTable, Asset>),
      Asset,
      PrefetchHooks Function()
    >;
typedef $$AssetSnapshotsTableCreateCompanionBuilder =
    AssetSnapshotsCompanion Function({
      Value<int> id,
      required int assetId,
      required String day,
      required int valueCents,
      Value<DateTime> createdAt,
    });
typedef $$AssetSnapshotsTableUpdateCompanionBuilder =
    AssetSnapshotsCompanion Function({
      Value<int> id,
      Value<int> assetId,
      Value<String> day,
      Value<int> valueCents,
      Value<DateTime> createdAt,
    });

class $$AssetSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $AssetSnapshotsTable> {
  $$AssetSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get valueCents => $composableBuilder(
    column: $table.valueCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AssetSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $AssetSnapshotsTable> {
  $$AssetSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get valueCents => $composableBuilder(
    column: $table.valueCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AssetSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AssetSnapshotsTable> {
  $$AssetSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get valueCents => $composableBuilder(
    column: $table.valueCents,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AssetSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AssetSnapshotsTable,
          AssetSnapshot,
          $$AssetSnapshotsTableFilterComposer,
          $$AssetSnapshotsTableOrderingComposer,
          $$AssetSnapshotsTableAnnotationComposer,
          $$AssetSnapshotsTableCreateCompanionBuilder,
          $$AssetSnapshotsTableUpdateCompanionBuilder,
          (
            AssetSnapshot,
            BaseReferences<_$AppDatabase, $AssetSnapshotsTable, AssetSnapshot>,
          ),
          AssetSnapshot,
          PrefetchHooks Function()
        > {
  $$AssetSnapshotsTableTableManager(
    _$AppDatabase db,
    $AssetSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AssetSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AssetSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AssetSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> assetId = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<int> valueCents = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => AssetSnapshotsCompanion(
                id: id,
                assetId: assetId,
                day: day,
                valueCents: valueCents,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int assetId,
                required String day,
                required int valueCents,
                Value<DateTime> createdAt = const Value.absent(),
              }) => AssetSnapshotsCompanion.insert(
                id: id,
                assetId: assetId,
                day: day,
                valueCents: valueCents,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AssetSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AssetSnapshotsTable,
      AssetSnapshot,
      $$AssetSnapshotsTableFilterComposer,
      $$AssetSnapshotsTableOrderingComposer,
      $$AssetSnapshotsTableAnnotationComposer,
      $$AssetSnapshotsTableCreateCompanionBuilder,
      $$AssetSnapshotsTableUpdateCompanionBuilder,
      (
        AssetSnapshot,
        BaseReferences<_$AppDatabase, $AssetSnapshotsTable, AssetSnapshot>,
      ),
      AssetSnapshot,
      PrefetchHooks Function()
    >;
typedef $$DebtNotesTableCreateCompanionBuilder =
    DebtNotesCompanion Function({
      Value<int> id,
      required DebtDirection direction,
      required String personName,
      required int amountCents,
      Value<String?> note,
      Value<int?> relatedAssetId,
      required DateTime borrowedAt,
      Value<DateTime?> repayDueAt,
      Value<bool> includeInTotal,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$DebtNotesTableUpdateCompanionBuilder =
    DebtNotesCompanion Function({
      Value<int> id,
      Value<DebtDirection> direction,
      Value<String> personName,
      Value<int> amountCents,
      Value<String?> note,
      Value<int?> relatedAssetId,
      Value<DateTime> borrowedAt,
      Value<DateTime?> repayDueAt,
      Value<bool> includeInTotal,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$DebtNotesTableFilterComposer
    extends Composer<_$AppDatabase, $DebtNotesTable> {
  $$DebtNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<DebtDirection, DebtDirection, int>
  get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relatedAssetId => $composableBuilder(
    column: $table.relatedAssetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get borrowedAt => $composableBuilder(
    column: $table.borrowedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get repayDueAt => $composableBuilder(
    column: $table.repayDueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get includeInTotal => $composableBuilder(
    column: $table.includeInTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DebtNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $DebtNotesTable> {
  $$DebtNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relatedAssetId => $composableBuilder(
    column: $table.relatedAssetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get borrowedAt => $composableBuilder(
    column: $table.borrowedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get repayDueAt => $composableBuilder(
    column: $table.repayDueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get includeInTotal => $composableBuilder(
    column: $table.includeInTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DebtNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DebtNotesTable> {
  $$DebtNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<DebtDirection, int> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get relatedAssetId => $composableBuilder(
    column: $table.relatedAssetId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get borrowedAt => $composableBuilder(
    column: $table.borrowedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get repayDueAt => $composableBuilder(
    column: $table.repayDueAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get includeInTotal => $composableBuilder(
    column: $table.includeInTotal,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DebtNotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DebtNotesTable,
          DebtNote,
          $$DebtNotesTableFilterComposer,
          $$DebtNotesTableOrderingComposer,
          $$DebtNotesTableAnnotationComposer,
          $$DebtNotesTableCreateCompanionBuilder,
          $$DebtNotesTableUpdateCompanionBuilder,
          (DebtNote, BaseReferences<_$AppDatabase, $DebtNotesTable, DebtNote>),
          DebtNote,
          PrefetchHooks Function()
        > {
  $$DebtNotesTableTableManager(_$AppDatabase db, $DebtNotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DebtNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DebtNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DebtNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DebtDirection> direction = const Value.absent(),
                Value<String> personName = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> relatedAssetId = const Value.absent(),
                Value<DateTime> borrowedAt = const Value.absent(),
                Value<DateTime?> repayDueAt = const Value.absent(),
                Value<bool> includeInTotal = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DebtNotesCompanion(
                id: id,
                direction: direction,
                personName: personName,
                amountCents: amountCents,
                note: note,
                relatedAssetId: relatedAssetId,
                borrowedAt: borrowedAt,
                repayDueAt: repayDueAt,
                includeInTotal: includeInTotal,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DebtDirection direction,
                required String personName,
                required int amountCents,
                Value<String?> note = const Value.absent(),
                Value<int?> relatedAssetId = const Value.absent(),
                required DateTime borrowedAt,
                Value<DateTime?> repayDueAt = const Value.absent(),
                Value<bool> includeInTotal = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DebtNotesCompanion.insert(
                id: id,
                direction: direction,
                personName: personName,
                amountCents: amountCents,
                note: note,
                relatedAssetId: relatedAssetId,
                borrowedAt: borrowedAt,
                repayDueAt: repayDueAt,
                includeInTotal: includeInTotal,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DebtNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DebtNotesTable,
      DebtNote,
      $$DebtNotesTableFilterComposer,
      $$DebtNotesTableOrderingComposer,
      $$DebtNotesTableAnnotationComposer,
      $$DebtNotesTableCreateCompanionBuilder,
      $$DebtNotesTableUpdateCompanionBuilder,
      (DebtNote, BaseReferences<_$AppDatabase, $DebtNotesTable, DebtNote>),
      DebtNote,
      PrefetchHooks Function()
    >;
typedef $$DebtNoteImagesTableCreateCompanionBuilder =
    DebtNoteImagesCompanion Function({
      Value<int> id,
      required int noteId,
      required String objectKey,
      required String localPath,
      required BillImageUploadState uploadState,
      Value<DateTime> createdAt,
      Value<int> sort,
    });
typedef $$DebtNoteImagesTableUpdateCompanionBuilder =
    DebtNoteImagesCompanion Function({
      Value<int> id,
      Value<int> noteId,
      Value<String> objectKey,
      Value<String> localPath,
      Value<BillImageUploadState> uploadState,
      Value<DateTime> createdAt,
      Value<int> sort,
    });

class $$DebtNoteImagesTableFilterComposer
    extends Composer<_$AppDatabase, $DebtNoteImagesTable> {
  $$DebtNoteImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectKey => $composableBuilder(
    column: $table.objectKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    BillImageUploadState,
    BillImageUploadState,
    int
  >
  get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DebtNoteImagesTableOrderingComposer
    extends Composer<_$AppDatabase, $DebtNoteImagesTable> {
  $$DebtNoteImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get noteId => $composableBuilder(
    column: $table.noteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectKey => $composableBuilder(
    column: $table.objectKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadState => $composableBuilder(
    column: $table.uploadState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DebtNoteImagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DebtNoteImagesTable> {
  $$DebtNoteImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get noteId =>
      $composableBuilder(column: $table.noteId, builder: (column) => column);

  GeneratedColumn<String> get objectKey =>
      $composableBuilder(column: $table.objectKey, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BillImageUploadState, int> get uploadState =>
      $composableBuilder(
        column: $table.uploadState,
        builder: (column) => column,
      );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$DebtNoteImagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DebtNoteImagesTable,
          DebtNoteImage,
          $$DebtNoteImagesTableFilterComposer,
          $$DebtNoteImagesTableOrderingComposer,
          $$DebtNoteImagesTableAnnotationComposer,
          $$DebtNoteImagesTableCreateCompanionBuilder,
          $$DebtNoteImagesTableUpdateCompanionBuilder,
          (
            DebtNoteImage,
            BaseReferences<_$AppDatabase, $DebtNoteImagesTable, DebtNoteImage>,
          ),
          DebtNoteImage,
          PrefetchHooks Function()
        > {
  $$DebtNoteImagesTableTableManager(
    _$AppDatabase db,
    $DebtNoteImagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DebtNoteImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DebtNoteImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DebtNoteImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> noteId = const Value.absent(),
                Value<String> objectKey = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<BillImageUploadState> uploadState = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> sort = const Value.absent(),
              }) => DebtNoteImagesCompanion(
                id: id,
                noteId: noteId,
                objectKey: objectKey,
                localPath: localPath,
                uploadState: uploadState,
                createdAt: createdAt,
                sort: sort,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int noteId,
                required String objectKey,
                required String localPath,
                required BillImageUploadState uploadState,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> sort = const Value.absent(),
              }) => DebtNoteImagesCompanion.insert(
                id: id,
                noteId: noteId,
                objectKey: objectKey,
                localPath: localPath,
                uploadState: uploadState,
                createdAt: createdAt,
                sort: sort,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DebtNoteImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DebtNoteImagesTable,
      DebtNoteImage,
      $$DebtNoteImagesTableFilterComposer,
      $$DebtNoteImagesTableOrderingComposer,
      $$DebtNoteImagesTableAnnotationComposer,
      $$DebtNoteImagesTableCreateCompanionBuilder,
      $$DebtNoteImagesTableUpdateCompanionBuilder,
      (
        DebtNoteImage,
        BaseReferences<_$AppDatabase, $DebtNoteImagesTable, DebtNoteImage>,
      ),
      DebtNoteImage,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$BillsTableTableManager get bills =>
      $$BillsTableTableManager(_db, _db.bills);
  $$BudgetsTableTableManager get budgets =>
      $$BudgetsTableTableManager(_db, _db.budgets);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$BillTagsTableTableManager get billTags =>
      $$BillTagsTableTableManager(_db, _db.billTags);
  $$BillImagesTableTableManager get billImages =>
      $$BillImagesTableTableManager(_db, _db.billImages);
  $$AssetsTableTableManager get assets =>
      $$AssetsTableTableManager(_db, _db.assets);
  $$AssetSnapshotsTableTableManager get assetSnapshots =>
      $$AssetSnapshotsTableTableManager(_db, _db.assetSnapshots);
  $$DebtNotesTableTableManager get debtNotes =>
      $$DebtNotesTableTableManager(_db, _db.debtNotes);
  $$DebtNoteImagesTableTableManager get debtNoteImages =>
      $$DebtNoteImagesTableTableManager(_db, _db.debtNoteImages);
}
