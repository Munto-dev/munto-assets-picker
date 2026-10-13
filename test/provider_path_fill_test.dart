import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:munto_assets_picker/munto_assets_picker.dart';

/// [CLS-382] 앨범별 개수 조회가 어떻게 나가는지 기록하는 가짜 사진 라이브러리.
class _FakePathsPlugin extends PhotoManagerPlugin {
  _FakePathsPlugin({required this.pathCount, this.failingPathIds = const {}});

  final int pathCount;

  /// 개수 조회에서 예외를 던질 앨범 ID.
  final Set<String> failingPathIds;

  /// 개수 조회를 요청받은 앨범 ID (요청 순서대로).
  final List<String> countRequestedIds = <String>[];

  /// 아직 끝나지 않은 개수 조회의 동시 최대 개수.
  int maxInFlight = 0;

  int _inFlight = 0;

  @override
  Future<List<AssetPathEntity>> getAssetPathList({
    bool hasAll = true,
    bool onlyAll = false,
    RequestType type = RequestType.common,
    PMFilter? filterOption,
    required PMPathFilter pathFilterOption,
  }) async {
    return List<AssetPathEntity>.generate(
      pathCount,
      (int i) => AssetPathEntity(id: 'p$i', name: 'album$i'),
    );
  }

  @override
  Future<int> getAssetCountFromPath(AssetPathEntity path) async {
    countRequestedIds.add(path.id);
    _inFlight++;
    maxInFlight = math.max(maxInFlight, _inFlight);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (failingPathIds.contains(path.id)) {
        throw StateError('개수 조회 실패: ${path.id}');
      }
      return 5;
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<List<AssetEntity>> getAssetListRange(
    String id, {
    required RequestType type,
    required int start,
    required int end,
    required PMFilter? optionGroup,
  }) async {
    return <AssetEntity>[];
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('조건이 ${timeout.inSeconds}초 안에 충족되지 않았다');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

int? _countOf(DefaultAssetPickerProvider provider, String id) {
  return provider.paths.firstWhere((p) => p.path.id == id).assetCount;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('앨범 개수·썸네일 채우기 (getPaths)', () {
    test('앨범별 개수 조회는 동시에 1개씩만 요청한다', () async {
      final _FakePathsPlugin plugin = _FakePathsPlugin(pathCount: 5);
      PhotoManager.withPlugin(plugin);
      final DefaultAssetPickerProvider provider =
          DefaultAssetPickerProvider.forTest();
      addTearDown(provider.dispose);

      await provider.getPaths();
      await _waitUntil(() => _countOf(provider, 'p4') != null);

      expect(plugin.maxInFlight, 1);
      expect(plugin.countRequestedIds.toSet(), <String>{
        'p0',
        'p1',
        'p2',
        'p3',
        'p4',
      });
    });

    test('한 앨범의 개수 조회가 실패해도 뒤쪽 앨범이 채워진다', () async {
      final _FakePathsPlugin plugin = _FakePathsPlugin(
        pathCount: 4,
        failingPathIds: <String>{'p1'},
      );
      PhotoManager.withPlugin(plugin);
      final DefaultAssetPickerProvider provider =
          DefaultAssetPickerProvider.forTest();
      addTearDown(provider.dispose);

      await provider.getPaths();
      await _waitUntil(() => _countOf(provider, 'p3') != null);

      expect(_countOf(provider, 'p0'), 5);
      expect(_countOf(provider, 'p1'), isNull);
      expect(_countOf(provider, 'p2'), 5);
      expect(_countOf(provider, 'p3'), 5);
    });
  });
}
