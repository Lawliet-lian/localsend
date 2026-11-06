// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'conversation_models.dart';

class ConversationDirectionMapper extends EnumMapper<ConversationDirection> {
  ConversationDirectionMapper._();

  static ConversationDirectionMapper? _instance;
  static ConversationDirectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ConversationDirectionMapper._());
    }
    return _instance!;
  }

  static ConversationDirection fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ConversationDirection decode(dynamic value) {
    switch (value) {
      case r'send':
        return ConversationDirection.send;
      case r'receive':
        return ConversationDirection.receive;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ConversationDirection self) {
    switch (self) {
      case ConversationDirection.send:
        return r'send';
      case ConversationDirection.receive:
        return r'receive';
    }
  }
}

extension ConversationDirectionMapperExtension on ConversationDirection {
  String toValue() {
    ConversationDirectionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ConversationDirection>(this)
        as String;
  }
}

class ConversationEntryKindMapper extends EnumMapper<ConversationEntryKind> {
  ConversationEntryKindMapper._();

  static ConversationEntryKindMapper? _instance;
  static ConversationEntryKindMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ConversationEntryKindMapper._());
    }
    return _instance!;
  }

  static ConversationEntryKind fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ConversationEntryKind decode(dynamic value) {
    switch (value) {
      case r'text':
        return ConversationEntryKind.text;
      case r'file':
        return ConversationEntryKind.file;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ConversationEntryKind self) {
    switch (self) {
      case ConversationEntryKind.text:
        return r'text';
      case ConversationEntryKind.file:
        return r'file';
    }
  }
}

extension ConversationEntryKindMapperExtension on ConversationEntryKind {
  String toValue() {
    ConversationEntryKindMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ConversationEntryKind>(this)
        as String;
  }
}

class ConversationOutcomeMapper extends EnumMapper<ConversationOutcome> {
  ConversationOutcomeMapper._();

  static ConversationOutcomeMapper? _instance;
  static ConversationOutcomeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ConversationOutcomeMapper._());
    }
    return _instance!;
  }

  static ConversationOutcome fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ConversationOutcome decode(dynamic value) {
    switch (value) {
      case r'preparing':
        return ConversationOutcome.preparing;
      case r'waiting':
        return ConversationOutcome.waiting;
      case r'transferring':
        return ConversationOutcome.transferring;
      case r'finished':
        return ConversationOutcome.finished;
      case r'partialFailure':
        return ConversationOutcome.partialFailure;
      case r'declined':
        return ConversationOutcome.declined;
      case r'busy':
        return ConversationOutcome.busy;
      case r'tooManyAttempts':
        return ConversationOutcome.tooManyAttempts;
      case r'canceledBySender':
        return ConversationOutcome.canceledBySender;
      case r'canceledByReceiver':
        return ConversationOutcome.canceledByReceiver;
      case r'failed':
        return ConversationOutcome.failed;
      case r'incomplete':
        return ConversationOutcome.incomplete;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ConversationOutcome self) {
    switch (self) {
      case ConversationOutcome.preparing:
        return r'preparing';
      case ConversationOutcome.waiting:
        return r'waiting';
      case ConversationOutcome.transferring:
        return r'transferring';
      case ConversationOutcome.finished:
        return r'finished';
      case ConversationOutcome.partialFailure:
        return r'partialFailure';
      case ConversationOutcome.declined:
        return r'declined';
      case ConversationOutcome.busy:
        return r'busy';
      case ConversationOutcome.tooManyAttempts:
        return r'tooManyAttempts';
      case ConversationOutcome.canceledBySender:
        return r'canceledBySender';
      case ConversationOutcome.canceledByReceiver:
        return r'canceledByReceiver';
      case ConversationOutcome.failed:
        return r'failed';
      case ConversationOutcome.incomplete:
        return r'incomplete';
    }
  }
}

extension ConversationOutcomeMapperExtension on ConversationOutcome {
  String toValue() {
    ConversationOutcomeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ConversationOutcome>(this) as String;
  }
}

class ConversationFileOutcomeMapper
    extends EnumMapper<ConversationFileOutcome> {
  ConversationFileOutcomeMapper._();

  static ConversationFileOutcomeMapper? _instance;
  static ConversationFileOutcomeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ConversationFileOutcomeMapper._(),
      );
    }
    return _instance!;
  }

  static ConversationFileOutcome fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ConversationFileOutcome decode(dynamic value) {
    switch (value) {
      case r'pending':
        return ConversationFileOutcome.pending;
      case r'skipped':
        return ConversationFileOutcome.skipped;
      case r'success':
        return ConversationFileOutcome.success;
      case r'failure':
        return ConversationFileOutcome.failure;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ConversationFileOutcome self) {
    switch (self) {
      case ConversationFileOutcome.pending:
        return r'pending';
      case ConversationFileOutcome.skipped:
        return r'skipped';
      case ConversationFileOutcome.success:
        return r'success';
      case ConversationFileOutcome.failure:
        return r'failure';
    }
  }
}

extension ConversationFileOutcomeMapperExtension on ConversationFileOutcome {
  String toValue() {
    ConversationFileOutcomeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ConversationFileOutcome>(this)
        as String;
  }
}

class ConversationPeerMapper extends ClassMapperBase<ConversationPeer> {
  ConversationPeerMapper._();

  static ConversationPeerMapper? _instance;
  static ConversationPeerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ConversationPeerMapper._());
      DeviceTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ConversationPeer';

  static String _$peerKey(ConversationPeer v) => v.peerKey;
  static const Field<ConversationPeer, String> _f$peerKey = Field(
    'peerKey',
    _$peerKey,
  );
  static String? _$fingerprint(ConversationPeer v) => v.fingerprint;
  static const Field<ConversationPeer, String> _f$fingerprint = Field(
    'fingerprint',
    _$fingerprint,
  );
  static String _$alias(ConversationPeer v) => v.alias;
  static const Field<ConversationPeer, String> _f$alias = Field(
    'alias',
    _$alias,
  );
  static DeviceType _$deviceType(ConversationPeer v) => v.deviceType;
  static const Field<ConversationPeer, DeviceType> _f$deviceType = Field(
    'deviceType',
    _$deviceType,
  );

  @override
  final MappableFields<ConversationPeer> fields = const {
    #peerKey: _f$peerKey,
    #fingerprint: _f$fingerprint,
    #alias: _f$alias,
    #deviceType: _f$deviceType,
  };

  static ConversationPeer _instantiate(DecodingData data) {
    return ConversationPeer(
      peerKey: data.dec(_f$peerKey),
      fingerprint: data.dec(_f$fingerprint),
      alias: data.dec(_f$alias),
      deviceType: data.dec(_f$deviceType),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ConversationPeer fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ConversationPeer>(map);
  }

  static ConversationPeer deserialize(String json) {
    return ensureInitialized().decodeJson<ConversationPeer>(json);
  }
}

mixin ConversationPeerMappable {
  String serialize() {
    return ConversationPeerMapper.ensureInitialized()
        .encodeJson<ConversationPeer>(this as ConversationPeer);
  }

  Map<String, dynamic> toJson() {
    return ConversationPeerMapper.ensureInitialized()
        .encodeMap<ConversationPeer>(this as ConversationPeer);
  }

  ConversationPeerCopyWith<ConversationPeer, ConversationPeer, ConversationPeer>
  get copyWith =>
      _ConversationPeerCopyWithImpl<ConversationPeer, ConversationPeer>(
        this as ConversationPeer,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ConversationPeerMapper.ensureInitialized().stringifyValue(
      this as ConversationPeer,
    );
  }

  @override
  bool operator ==(Object other) {
    return ConversationPeerMapper.ensureInitialized().equalsValue(
      this as ConversationPeer,
      other,
    );
  }

  @override
  int get hashCode {
    return ConversationPeerMapper.ensureInitialized().hashValue(
      this as ConversationPeer,
    );
  }
}

extension ConversationPeerValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ConversationPeer, $Out> {
  ConversationPeerCopyWith<$R, ConversationPeer, $Out>
  get $asConversationPeer =>
      $base.as((v, t, t2) => _ConversationPeerCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class ConversationPeerCopyWith<$R, $In extends ConversationPeer, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? peerKey,
    String? fingerprint,
    String? alias,
    DeviceType? deviceType,
  });
  ConversationPeerCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ConversationPeerCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ConversationPeer, $Out>
    implements ConversationPeerCopyWith<$R, ConversationPeer, $Out> {
  _ConversationPeerCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ConversationPeer> $mapper =
      ConversationPeerMapper.ensureInitialized();
  @override
  $R call({
    String? peerKey,
    Object? fingerprint = $none,
    String? alias,
    DeviceType? deviceType,
  }) => $apply(
    FieldCopyWithData({
      if (peerKey != null) #peerKey: peerKey,
      if (fingerprint != $none) #fingerprint: fingerprint,
      if (alias != null) #alias: alias,
      if (deviceType != null) #deviceType: deviceType,
    }),
  );
  @override
  ConversationPeer $make(CopyWithData data) => ConversationPeer(
    peerKey: data.get(#peerKey, or: $value.peerKey),
    fingerprint: data.get(#fingerprint, or: $value.fingerprint),
    alias: data.get(#alias, or: $value.alias),
    deviceType: data.get(#deviceType, or: $value.deviceType),
  );

  @override
  ConversationPeerCopyWith<$R2, ConversationPeer, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ConversationPeerCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ConversationEntryMapper extends ClassMapperBase<ConversationEntry> {
  ConversationEntryMapper._();

  static ConversationEntryMapper? _instance;
  static ConversationEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ConversationEntryMapper._());
      ConversationDirectionMapper.ensureInitialized();
      ConversationEntryKindMapper.ensureInitialized();
      ConversationOutcomeMapper.ensureInitialized();
      ConversationFileSummaryMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ConversationEntry';

  static String _$entryId(ConversationEntry v) => v.entryId;
  static const Field<ConversationEntry, String> _f$entryId = Field(
    'entryId',
    _$entryId,
  );
  static String _$peerKey(ConversationEntry v) => v.peerKey;
  static const Field<ConversationEntry, String> _f$peerKey = Field(
    'peerKey',
    _$peerKey,
  );
  static ConversationDirection _$direction(ConversationEntry v) => v.direction;
  static const Field<ConversationEntry, ConversationDirection> _f$direction =
      Field('direction', _$direction);
  static String _$localSessionId(ConversationEntry v) => v.localSessionId;
  static const Field<ConversationEntry, String> _f$localSessionId = Field(
    'localSessionId',
    _$localSessionId,
  );
  static ConversationEntryKind _$kind(ConversationEntry v) => v.kind;
  static const Field<ConversationEntry, ConversationEntryKind> _f$kind = Field(
    'kind',
    _$kind,
  );
  static ConversationOutcome _$outcome(ConversationEntry v) => v.outcome;
  static const Field<ConversationEntry, ConversationOutcome> _f$outcome = Field(
    'outcome',
    _$outcome,
  );
  static DateTime _$createdAt(ConversationEntry v) => v.createdAt;
  static const Field<ConversationEntry, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime? _$finishedAt(ConversationEntry v) => v.finishedAt;
  static const Field<ConversationEntry, DateTime> _f$finishedAt = Field(
    'finishedAt',
    _$finishedAt,
  );
  static List<ConversationFileSummary> _$files(ConversationEntry v) => v.files;
  static const Field<ConversationEntry, List<ConversationFileSummary>>
  _f$files = Field('files', _$files);
  static String? _$text(ConversationEntry v) => v.text;
  static const Field<ConversationEntry, String> _f$text = Field('text', _$text);
  static String? _$error(ConversationEntry v) => v.error;
  static const Field<ConversationEntry, String> _f$error = Field(
    'error',
    _$error,
  );

  @override
  final MappableFields<ConversationEntry> fields = const {
    #entryId: _f$entryId,
    #peerKey: _f$peerKey,
    #direction: _f$direction,
    #localSessionId: _f$localSessionId,
    #kind: _f$kind,
    #outcome: _f$outcome,
    #createdAt: _f$createdAt,
    #finishedAt: _f$finishedAt,
    #files: _f$files,
    #text: _f$text,
    #error: _f$error,
  };

  static ConversationEntry _instantiate(DecodingData data) {
    return ConversationEntry(
      entryId: data.dec(_f$entryId),
      peerKey: data.dec(_f$peerKey),
      direction: data.dec(_f$direction),
      localSessionId: data.dec(_f$localSessionId),
      kind: data.dec(_f$kind),
      outcome: data.dec(_f$outcome),
      createdAt: data.dec(_f$createdAt),
      finishedAt: data.dec(_f$finishedAt),
      files: data.dec(_f$files),
      text: data.dec(_f$text),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ConversationEntry fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ConversationEntry>(map);
  }

  static ConversationEntry deserialize(String json) {
    return ensureInitialized().decodeJson<ConversationEntry>(json);
  }
}

mixin ConversationEntryMappable {
  String serialize() {
    return ConversationEntryMapper.ensureInitialized()
        .encodeJson<ConversationEntry>(this as ConversationEntry);
  }

  Map<String, dynamic> toJson() {
    return ConversationEntryMapper.ensureInitialized()
        .encodeMap<ConversationEntry>(this as ConversationEntry);
  }

  ConversationEntryCopyWith<
    ConversationEntry,
    ConversationEntry,
    ConversationEntry
  >
  get copyWith =>
      _ConversationEntryCopyWithImpl<ConversationEntry, ConversationEntry>(
        this as ConversationEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return ConversationEntryMapper.ensureInitialized().stringifyValue(
      this as ConversationEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return ConversationEntryMapper.ensureInitialized().equalsValue(
      this as ConversationEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return ConversationEntryMapper.ensureInitialized().hashValue(
      this as ConversationEntry,
    );
  }
}

extension ConversationEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ConversationEntry, $Out> {
  ConversationEntryCopyWith<$R, ConversationEntry, $Out>
  get $asConversationEntry => $base.as(
    (v, t, t2) => _ConversationEntryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ConversationEntryCopyWith<
  $R,
  $In extends ConversationEntry,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    ConversationFileSummary,
    ConversationFileSummaryCopyWith<
      $R,
      ConversationFileSummary,
      ConversationFileSummary
    >
  >
  get files;
  $R call({
    String? entryId,
    String? peerKey,
    ConversationDirection? direction,
    String? localSessionId,
    ConversationEntryKind? kind,
    ConversationOutcome? outcome,
    DateTime? createdAt,
    DateTime? finishedAt,
    List<ConversationFileSummary>? files,
    String? text,
    String? error,
  });
  ConversationEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ConversationEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ConversationEntry, $Out>
    implements ConversationEntryCopyWith<$R, ConversationEntry, $Out> {
  _ConversationEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ConversationEntry> $mapper =
      ConversationEntryMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    ConversationFileSummary,
    ConversationFileSummaryCopyWith<
      $R,
      ConversationFileSummary,
      ConversationFileSummary
    >
  >
  get files => ListCopyWith(
    $value.files,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(files: v),
  );
  @override
  $R call({
    String? entryId,
    String? peerKey,
    ConversationDirection? direction,
    String? localSessionId,
    ConversationEntryKind? kind,
    ConversationOutcome? outcome,
    DateTime? createdAt,
    Object? finishedAt = $none,
    List<ConversationFileSummary>? files,
    Object? text = $none,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (entryId != null) #entryId: entryId,
      if (peerKey != null) #peerKey: peerKey,
      if (direction != null) #direction: direction,
      if (localSessionId != null) #localSessionId: localSessionId,
      if (kind != null) #kind: kind,
      if (outcome != null) #outcome: outcome,
      if (createdAt != null) #createdAt: createdAt,
      if (finishedAt != $none) #finishedAt: finishedAt,
      if (files != null) #files: files,
      if (text != $none) #text: text,
      if (error != $none) #error: error,
    }),
  );
  @override
  ConversationEntry $make(CopyWithData data) => ConversationEntry(
    entryId: data.get(#entryId, or: $value.entryId),
    peerKey: data.get(#peerKey, or: $value.peerKey),
    direction: data.get(#direction, or: $value.direction),
    localSessionId: data.get(#localSessionId, or: $value.localSessionId),
    kind: data.get(#kind, or: $value.kind),
    outcome: data.get(#outcome, or: $value.outcome),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    finishedAt: data.get(#finishedAt, or: $value.finishedAt),
    files: data.get(#files, or: $value.files),
    text: data.get(#text, or: $value.text),
    error: data.get(#error, or: $value.error),
  );

  @override
  ConversationEntryCopyWith<$R2, ConversationEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _ConversationEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class ConversationFileSummaryMapper
    extends ClassMapperBase<ConversationFileSummary> {
  ConversationFileSummaryMapper._();

  static ConversationFileSummaryMapper? _instance;
  static ConversationFileSummaryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = ConversationFileSummaryMapper._(),
      );
      FileTypeMapper.ensureInitialized();
      ConversationFileOutcomeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'ConversationFileSummary';

  static String _$fileId(ConversationFileSummary v) => v.fileId;
  static const Field<ConversationFileSummary, String> _f$fileId = Field(
    'fileId',
    _$fileId,
  );
  static String _$fileName(ConversationFileSummary v) => v.fileName;
  static const Field<ConversationFileSummary, String> _f$fileName = Field(
    'fileName',
    _$fileName,
  );
  static FileType _$fileType(ConversationFileSummary v) => v.fileType;
  static const Field<ConversationFileSummary, FileType> _f$fileType = Field(
    'fileType',
    _$fileType,
  );
  static int _$size(ConversationFileSummary v) => v.size;
  static const Field<ConversationFileSummary, int> _f$size = Field(
    'size',
    _$size,
  );
  static ConversationFileOutcome _$outcome(ConversationFileSummary v) =>
      v.outcome;
  static const Field<ConversationFileSummary, ConversationFileOutcome>
  _f$outcome = Field('outcome', _$outcome);
  static String? _$path(ConversationFileSummary v) => v.path;
  static const Field<ConversationFileSummary, String> _f$path = Field(
    'path',
    _$path,
  );
  static bool _$savedToGallery(ConversationFileSummary v) => v.savedToGallery;
  static const Field<ConversationFileSummary, bool> _f$savedToGallery = Field(
    'savedToGallery',
    _$savedToGallery,
  );
  static String? _$error(ConversationFileSummary v) => v.error;
  static const Field<ConversationFileSummary, String> _f$error = Field(
    'error',
    _$error,
  );

  @override
  final MappableFields<ConversationFileSummary> fields = const {
    #fileId: _f$fileId,
    #fileName: _f$fileName,
    #fileType: _f$fileType,
    #size: _f$size,
    #outcome: _f$outcome,
    #path: _f$path,
    #savedToGallery: _f$savedToGallery,
    #error: _f$error,
  };

  static ConversationFileSummary _instantiate(DecodingData data) {
    return ConversationFileSummary(
      fileId: data.dec(_f$fileId),
      fileName: data.dec(_f$fileName),
      fileType: data.dec(_f$fileType),
      size: data.dec(_f$size),
      outcome: data.dec(_f$outcome),
      path: data.dec(_f$path),
      savedToGallery: data.dec(_f$savedToGallery),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static ConversationFileSummary fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<ConversationFileSummary>(map);
  }

  static ConversationFileSummary deserialize(String json) {
    return ensureInitialized().decodeJson<ConversationFileSummary>(json);
  }
}

mixin ConversationFileSummaryMappable {
  String serialize() {
    return ConversationFileSummaryMapper.ensureInitialized()
        .encodeJson<ConversationFileSummary>(this as ConversationFileSummary);
  }

  Map<String, dynamic> toJson() {
    return ConversationFileSummaryMapper.ensureInitialized()
        .encodeMap<ConversationFileSummary>(this as ConversationFileSummary);
  }

  ConversationFileSummaryCopyWith<
    ConversationFileSummary,
    ConversationFileSummary,
    ConversationFileSummary
  >
  get copyWith =>
      _ConversationFileSummaryCopyWithImpl<
        ConversationFileSummary,
        ConversationFileSummary
      >(this as ConversationFileSummary, $identity, $identity);
  @override
  String toString() {
    return ConversationFileSummaryMapper.ensureInitialized().stringifyValue(
      this as ConversationFileSummary,
    );
  }

  @override
  bool operator ==(Object other) {
    return ConversationFileSummaryMapper.ensureInitialized().equalsValue(
      this as ConversationFileSummary,
      other,
    );
  }

  @override
  int get hashCode {
    return ConversationFileSummaryMapper.ensureInitialized().hashValue(
      this as ConversationFileSummary,
    );
  }
}

extension ConversationFileSummaryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, ConversationFileSummary, $Out> {
  ConversationFileSummaryCopyWith<$R, ConversationFileSummary, $Out>
  get $asConversationFileSummary => $base.as(
    (v, t, t2) => _ConversationFileSummaryCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class ConversationFileSummaryCopyWith<
  $R,
  $In extends ConversationFileSummary,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? fileId,
    String? fileName,
    FileType? fileType,
    int? size,
    ConversationFileOutcome? outcome,
    String? path,
    bool? savedToGallery,
    String? error,
  });
  ConversationFileSummaryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _ConversationFileSummaryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, ConversationFileSummary, $Out>
    implements
        ConversationFileSummaryCopyWith<$R, ConversationFileSummary, $Out> {
  _ConversationFileSummaryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<ConversationFileSummary> $mapper =
      ConversationFileSummaryMapper.ensureInitialized();
  @override
  $R call({
    String? fileId,
    String? fileName,
    FileType? fileType,
    int? size,
    ConversationFileOutcome? outcome,
    Object? path = $none,
    bool? savedToGallery,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (fileId != null) #fileId: fileId,
      if (fileName != null) #fileName: fileName,
      if (fileType != null) #fileType: fileType,
      if (size != null) #size: size,
      if (outcome != null) #outcome: outcome,
      if (path != $none) #path: path,
      if (savedToGallery != null) #savedToGallery: savedToGallery,
      if (error != $none) #error: error,
    }),
  );
  @override
  ConversationFileSummary $make(CopyWithData data) => ConversationFileSummary(
    fileId: data.get(#fileId, or: $value.fileId),
    fileName: data.get(#fileName, or: $value.fileName),
    fileType: data.get(#fileType, or: $value.fileType),
    size: data.get(#size, or: $value.size),
    outcome: data.get(#outcome, or: $value.outcome),
    path: data.get(#path, or: $value.path),
    savedToGallery: data.get(#savedToGallery, or: $value.savedToGallery),
    error: data.get(#error, or: $value.error),
  );

  @override
  ConversationFileSummaryCopyWith<$R2, ConversationFileSummary, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _ConversationFileSummaryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

