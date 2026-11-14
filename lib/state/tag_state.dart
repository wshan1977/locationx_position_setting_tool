import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../services/locator_ble_api.dart';

/// 태그에 접속하는 경로.
enum TagLink {
  pc, // 이 PC의 블루투스 (universal_ble)
  locator, // 로케이터 카드 내장 블루투스 (태그 에이전트 :8081)
}

/// 태그 검색에 쓸 로케이터 카드 (IP + 목록 표시용 짧은 이름).
typedef LocatorCard = ({String ip, String name});

/// PC(또는 폰) 블루투스 스캔으로 들은 태그 1개.
class BleTag {
  final String mac; // 대문자 "60:B7:63:26:5A:89"
  String name;
  int rssi;
  bool appLoader = false; // OTA 부트로더(AppLoader)로 광고 중
  // AppLoader가 광고하는 주소: 부트로더 빌드에 따라 태그 주소 그대로이거나
  // 주소 + 1 (폰의 오래된 GATT 캐시를 피하려는 설정).
  String? otaAddr;
  DateTime seen = DateTime.now();
  // 로케이터 경로로 찾은 태그: 가장 크게 들은 카드 (이후 접속·OTA도 이 카드로).
  LocatorCard? via;
  // 로케이터 경로: 이번 검색에서 이 태그를 들은 카드 이름 -> RSSI.
  final heardBy = <String, int>{};
  BleTag(this.mac, this.name, this.rssi);

  /// positioning 서비스가 쓰는 태그 ID (`ble-pd-` + MAC, 구분자 제거).
  String get tagId => 'ble-pd-${mac.replaceAll(':', '')}';
}

/// 접속해서 읽은 태그 정보 (Device Information 서비스).
class BleTagInfo {
  final String manufacturer;
  final String model;
  final String hw;
  final String fw;
  final bool otaCapable; // 앱 펌웨어에 OTA control(in_place_ota_dfu)이 있는지
  const BleTagInfo({
    this.manufacturer = '',
    this.model = '',
    this.hw = '',
    this.fw = '',
    this.otaCapable = false,
  });
}

/// 펌웨어 업데이트 진행 상황 (UI 표시용).
class OtaProgress {
  final String step; // 작업자에게 보여줄 단계
  final double fraction; // 전체 업데이트 중 0..1
  const OtaProgress(this.step, this.fraction);
}

/// Tag 설정 탭: PC 블루투스(Windows WinRT · universal_ble)로 태그에 직접
/// 접속해 검색, 상태 읽기, Silicon Labs in-place OTA(AN1086)를 수행한다.
/// 175_BDCI bdci_manager의 TokenBle에서 가져온 절차:
///   앱:        OTA control <- 0x00  => 태그가 AppLoader로 재부팅
///   AppLoader: OTA control <- 0x00, OTA data <- .gbl 조각,
///              OTA control <- 0x03  => 검증 후 새 펌웨어로 부팅
/// 태그 펌웨어에 in_place_ota_dfu + bootloader_interface 컴포넌트와
/// AppLoader 부트로더(bootloader_apploader_tag)가 있어야 한다.
class TagState extends ChangeNotifier {
  // Device Information (16비트 SIG UUID 전체 형식).
  static String _sig(String s) => '0000$s-0000-1000-8000-00805f9b34fb';
  static final disSvc = _sig('180a');
  static final mfrChr = _sig('2a29');
  static final modelChr = _sig('2a24');
  static final hwRevChr = _sig('2a27');
  static final fwRevChr = _sig('2a26');
  // Silicon Labs OTA (in_place_ota_dfu / AppLoader).
  static const otaSvc = '1d14d6ee-fd63-4fa1-bfa4-8f47b42119f0';
  static const otaCtrl = 'f7bf3564-fb6d-4e53-88a4-5e37e0326063';
  static const otaData = '984227f3-34fc-4045-a5d0-2c581f81a153';
  // SDK Constant Tone Extension 서비스 (gatt_service_cte_adv): CTE 확장 광고
  // 간격 (uint16, 0.625 ms 단위, 최소 32 = 20 ms). 로케이터가 위치 계산에 쓰는
  // 송신 주기 — 태그 FW 1.2.0+는 NVM3에 저장해 재부팅 후에도 유지한다.
  static final cteSvc = _sig('184a');
  static final cteIntervalChr = _sig('2bb1');
  static const cteIntervalMinMs = 20;
  static const cteIntervalMaxMs = 10000;

  /// 태그 펌웨어의 GAP Device Name (gatt_configuration.btconf).
  static const tagName = 'assettag';

  static const _connectTimeout = Duration(seconds: 15);

  final tags = <String, BleTag>{};
  bool scanning = false;

  /// 태그 접속 경로 (검색·상태 읽기·송신 주기·OTA 모두).
  TagLink link = TagLink.pc;

  /// 로케이터 경로 검색에서 응답하지 않은 카드 (이름 -> 오류).
  final locatorErrors = <String, String>{};

  void setLink(TagLink v) {
    if (link == v) return;
    link = v;
    tags.clear(); // 경로마다 RSSI·접속 카드가 달라 목록을 새로 받는다
    locatorErrors.clear();
    notifyListeners();
  }

  /// 로케이터 경로로 들은 태그면 그 카드의 API.
  LocatorBleApi? _remote(String mac) {
    final v = tags[mac.toUpperCase()]?.via;
    return link == TagLink.locator && v != null ? LocatorBleApi(v.ip) : null;
  }

  /// 로케이터 카드들의 내장 블루투스로 [secs]초 동안 동시에 검색하고, 태그마다
  /// 가장 크게 들은 카드를 기억한다. 태그는 이름 광고를 ~1.1초마다 보내고 Pi
  /// 블루투스는 듣는 비율이 낮아 8초면 놓칠 때가 있어 15초 (실측 2026-11-12).
  Future<void> scanViaLocators(List<LocatorCard> cards, {int secs = 15}) async {
    if (scanning) return;
    scanning = true;
    tags.clear();
    locatorErrors.clear();
    setStatus('로케이터 ${cards.length}대(${cards.map((c) => c.name).join(', ')})로 '
        '$secs초 동안 검색 중...');
    try {
      await Future.wait([
        for (final c in cards)
          LocatorBleApi(c.ip).scan(secs: secs, all: showAll).then((list) {
            for (final j in list) {
              final mac = (j['mac'] as String).toUpperCase();
              final rssi = (j['rssi'] as num?)?.toInt() ?? -127;
              final name = j['name']?.toString() ?? '';
              final t = tags.putIfAbsent(mac, () => BleTag(mac, name, rssi));
              if (name.isNotEmpty) t.name = name;
              if (name.toLowerCase().contains(tagName)) knownMacs.add(mac);
              t.heardBy[c.name] = rssi;
              if (t.via == null || rssi > t.rssi || t.via == c) {
                t
                  ..rssi = rssi
                  ..via = c;
              }
              t.appLoader = j['appLoader'] == true;
              if (t.appLoader) t.otaAddr = mac;
            }
            notifyListeners();
          }).catchError((Object e) {
            locatorErrors[c.name] = '$e';
          }),
      ]);
      final n = visibleTags.length;
      final bad = locatorErrors.keys.join(', ');
      setStatus('검색 완료 · 태그 $n개 · 응답 ${cards.length - locatorErrors.length}/${cards.length}대'
          '${bad.isEmpty ? '' : ' (실패: $bad)'}',
          error: locatorErrors.length == cards.length);
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// false면 태그(AssetTag)와 AppLoader만, true면 들리는 BLE 기기 전부.
  bool showAll = false;

  /// 태그로 확인된 MAC: 이름(AssetTag)을 한 번이라도 들었거나 MQTT 각도·위치
  /// 토픽(`ble-pd-<MAC>`)에 나온 것. 태그는 이름 없는 CTE 광고를 25 ms마다,
  /// 이름 광고는 ~1.1초마다 보내므로 짧은 검색에서 이름을 못 들어도 목록에 둔다.
  final knownMacs = <String>{};

  /// MQTT 토픽 등에서 얻은 태그 ID(`ble-pd-30FB10657F77`)를 태그로 등록.
  void addKnownTagIds(Iterable<String> ids) {
    for (final id in ids) {
      final m = RegExp(r'ble-pd-([0-9A-Fa-f]{12})$').firstMatch(id);
      if (m == null) continue;
      final h = m.group(1)!.toUpperCase();
      knownMacs.add([for (var i = 0; i < 12; i += 2) h.substring(i, i + 2)].join(':'));
    }
  }

  bool _isTag(BleTag t) =>
      t.appLoader || t.name.toLowerCase().contains(tagName) || knownMacs.contains(t.mac);

  /// OTA·상태 읽기로 지금 접속 중인 태그 MAC (UI 버튼 잠금용).
  String? busyMac;

  /// 화면 아래 상태줄: 지금 하는 일 / 마지막 결과.
  String status = '대기 중';
  bool statusError = false;
  DateTime statusAt = DateTime.now();

  void setStatus(String s, {bool error = false}) {
    status = s;
    statusError = error;
    statusAt = DateTime.now();
    notifyListeners();
  }

  /// 업데이트 모드(AppLoader)를 못 찾은 실패에 붙이는 안내: 대부분 태그가
  /// AppLoader로 재부팅하는 순간 전원이 꺼진 경우다 (BAT_HOLD 래치 풀림).
  static String otaHint(Object e) {
    final m = '$e';
    if (!m.contains('업데이트 모드')) return m;
    return '$m\n→ 태그가 업데이트 모드로 재부팅하면서 전원이 꺼졌을 가능성이 큽니다. '
        '전원 버튼을 누른 채로 다시 시도하거나, BAT_HOLD 부트로더(flash_tag.bat)를 '
        '기록한 태그로 하세요.';
  }

  static String _id(String mac) => mac.toLowerCase();

  void setShowAll(bool v) {
    showAll = v;
    notifyListeners();
  }

  /// 목록에 보일 태그: AppLoader 먼저, 이후 RSSI 강한 순.
  List<BleTag> get visibleTags {
    final l = tags.values
        .where((t) => showAll || _isTag(t))
        .toList()
      ..sort((a, b) {
        if (a.appLoader != b.appLoader) return a.appLoader ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });
    return l;
  }

  Future<AvailabilityState> availability() =>
      UniversalBle.getBluetoothAvailabilityState();

  /// [secs]초 동안 광고를 듣는다. [tags]는 광고가 들어오는 대로 채워진다.
  Future<void> scan({int secs = 8}) async {
    if (scanning) return;
    // Android 12+는 BLUETOOTH_SCAN/CONNECT 런타임 권한 (Windows는 바로 통과).
    await UniversalBle.requestPermissions();
    scanning = true;
    tags.removeWhere((_, t) => DateTime.now().difference(t.seen).inMinutes > 2);
    setStatus('PC 블루투스로 $secs초 동안 검색 중...');
    UniversalBle.onScanResult = _onScan;
    try {
      await UniversalBle.startScan();
      await Future.delayed(Duration(seconds: secs));
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      scanning = false;
      setStatus('검색 완료 · 태그 ${visibleTags.length}개 (PC 블루투스)');
    }
  }

  void _onScan(BleDevice d) {
    final addr = d.deviceId.toUpperCase();
    final name = d.name ?? '';
    // OTA 부트로더에서 대기 중인 태그: "AppLoader" 이름 또는 OTA 서비스,
    // 태그 주소 그대로 또는 주소 + 1.
    if (_isAppLoader(d)) {
      _appLoaders[addr] = DateTime.now();
      final owner = tags.containsKey(addr)
          ? addr
          : tags.containsKey(macOffset(addr, -1))
              ? macOffset(addr, -1)
              : null;
      // 주인을 모르면(이번 실행 전부터 업데이트 모드에 멈춤) 부트로더
      // 자체를 목록에 올려 업데이트를 마칠 수 있게 한다.
      tags.putIfAbsent(owner ?? addr, () => BleTag(addr, name, d.rssi ?? -127))
        ..appLoader = true
        ..otaAddr = addr
        ..rssi = d.rssi ?? -127
        ..seen = DateTime.now();
      notifyListeners();
      return;
    }
    final t = tags.putIfAbsent(addr, () => BleTag(addr, name, d.rssi ?? -127));
    if (name.isNotEmpty) t.name = name;
    if (name.toLowerCase().contains(tagName)) knownMacs.add(addr);
    t
      ..appLoader = false
      ..rssi = d.rssi ?? t.rssi
      ..seen = DateTime.now();
    notifyListeners();
  }

  // 최근 본 AppLoader 광고 (주소 -> 시각).
  final _appLoaders = <String, DateTime>{};

  /// 마지막 펌웨어 업데이트의 단계 기록 ("+12.3s connect ...") — 실패 원인 확인용.
  final otaTrace = <String>[];
  DateTime _t0 = DateTime.now();
  void _tr(String s) {
    final dt = DateTime.now().difference(_t0).inMilliseconds / 1000;
    otaTrace.add('+${dt.toStringAsFixed(1)}s $s');
    setStatus('펌웨어 업데이트 · $s');
  }

  static String _svcList(List<BleService> s) => s
      .map((x) => '${x.uuid.substring(0, 8)}(${x.characteristics.length})')
      .join(' ');

  static bool _isAppLoader(BleDevice d) =>
      (d.name ?? '').toLowerCase().contains('apploader') ||
      d.services.any((s) => s.toLowerCase() == otaSvc);

  /// "60:B7:63:27:A8:0C" + 1 -> "60:B7:63:27:A8:0D" (48비트 주소 전체).
  static String macOffset(String mac, int delta) {
    final hex = mac.replaceAll(':', '');
    final v = (int.parse(hex, radix: 16) + delta) & 0xFFFFFFFFFFFF;
    final s = v.toRadixString(16).toUpperCase().padLeft(12, '0');
    return [for (var i = 0; i < 12; i += 2) s.substring(i, i + 2)].join(':');
  }

  /// 태그 [mac]의 AppLoader(주소 또는 + 1)를 최대 [max] 동안 찾는다.
  Future<String?> _findAppLoader(String mac, Duration max) async {
    final want = {mac.toUpperCase(), macOffset(mac.toUpperCase(), 1)};
    final since = DateTime.now();
    String? hit() {
      for (final e in _appLoaders.entries) {
        if (want.contains(e.key) && !e.value.isBefore(since)) return e.key;
      }
      return null;
    }

    UniversalBle.onScanResult = _onScan;
    try {
      await UniversalBle.startScan();
      final until = since.add(max);
      while (DateTime.now().isBefore(until) && hit() == null) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (_) {
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    }
    return hit();
  }

  Future<List<BleService>> _connect(String mac) async {
    await UniversalBle.connect(_id(mac), timeout: _connectTimeout);
    return UniversalBle.discoverServices(_id(mac));
  }

  static bool _has(List<BleService> s, String svc, String chr) => s.any((x) =>
      x.uuid.toLowerCase() == svc &&
      x.characteristics.any((c) => c.uuid.toLowerCase() == chr));

  /// [mac] 링크가 실제로 끊길 때까지 기다린 뒤(태그가 AppLoader로 재부팅하기
  /// 전에 스스로 끊는다) 우리 쪽도 정리한다.
  Future<void> _waitDisconnected(String mac, Duration max) async {
    final id = _id(mac);
    final until = DateTime.now().add(max);
    while (DateTime.now().isBefore(until)) {
      try {
        if (await UniversalBle.getConnectionState(id) ==
            BleConnectionState.disconnected) {
          break;
        }
      } catch (_) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _disconnect(mac);
  }

  /// 태그 [mac]의 AppLoader에 접속하고 사용한 주소를 돌려준다. 부트로더는
  /// 태그 주소 또는 주소 + 1로 광고하므로 광고부터 찾는다. 여전히 앱의
  /// 서비스가 보이는 세션(남은 링크 / Windows 캐시)은 OTA data가 없어 버린다.
  Future<String> _connectAppLoader(String mac) async {
    Object? last;
    final up = mac.toUpperCase();
    for (var i = 0; i < 4; i++) {
      final seen = await _findAppLoader(up, const Duration(seconds: 6));
      _tr('AppLoader advert: ${seen ?? 'none'} '
          '(seen: ${_appLoaders.keys.join(',')})');
      final tryAddrs = seen != null ? [seen] : [up, macOffset(up, 1)];
      for (final a in tryAddrs) {
        try {
          final s = await _connect(a);
          _tr('connect $a ok: ${_svcList(s)}');
          if (_has(s, otaSvc, otaData)) return a;
          last = '태그가 아직 업데이트 모드가 아님 (일반 펌웨어 서비스가 보임)';
          if (a == up && _has(s, otaSvc, otaCtrl)) {
            // 아직 앱: 부트로더 요청이 먹히지 않았다(바로 앱으로 돌아간
            // 경우). 새 연결에서 다시 요청한다.
            try {
              await UniversalBle.write(
                  _id(a), otaSvc, otaCtrl, Uint8List.fromList([0x00]));
              _tr('OTA control 0x00 re-sent');
            } catch (e) {
              _tr('OTA control 0x00 re-send: $e');
            }
            await _waitDisconnected(a, const Duration(seconds: 8));
            _tr('app link down (retry)');
            break; // AppLoader를 다시 찾는다
          }
        } catch (e) {
          _tr('connect $a failed: $e');
          last = seen == null
              ? '업데이트 모드 광고를 찾지 못함 ($e)'
              : '업데이트 모드($a) 연결 실패: $e';
        }
        await _disconnect(a);
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    throw '업데이트 모드 연결 실패: $last';
  }

  Future<void> _disconnect(String mac) async {
    try {
      await UniversalBle.disconnect(_id(mac),
          timeout: const Duration(seconds: 5));
    } catch (_) {}
  }

  static String _str(Uint8List v) =>
      String.fromCharCodes(v.where((c) => c != 0)).trim();

  void _setBusy(String? mac) {
    busyMac = mac;
    notifyListeners();
  }

  /// 접속해서 Device Information을 읽고 끊는다.
  Future<BleTagInfo> readStatus(String mac) async {
    final r = await _op('상태 읽기', mac, () => _readStatus(mac));
    setStatus('상태 읽기 완료 · $mac · FW ${r.fw.isEmpty ? '?' : r.fw}');
    return r;
  }

  /// 태그 작업 하나를 상태줄에 "진행 중 → 실패" 로 표시하며 실행.
  Future<T> _op<T>(String what, String mac, Future<T> Function() f) async {
    final v = tags[mac.toUpperCase()]?.via;
    setStatus('$what 중 · $mac (${v == null || link == TagLink.pc ? 'PC 블루투스' : '로케이터 ${v.name}'})...');
    try {
      return await f();
    } catch (e) {
      setStatus('$what 실패 · $mac · $e', error: true);
      rethrow;
    }
  }

  Future<BleTagInfo> _readStatus(String mac) async {
    final id = _id(mac);
    _setBusy(mac.toUpperCase());
    final remote = _remote(mac);
    if (remote != null) {
      try {
        final d = await remote.info(mac.toUpperCase());
        return BleTagInfo(
          manufacturer: d['manufacturer']?.toString() ?? '',
          model: d['model']?.toString() ?? '',
          hw: d['hw']?.toString() ?? '',
          fw: d['fw']?.toString() ?? '',
          otaCapable: d['otaCapable'] == true,
        );
      } finally {
        _setBusy(null);
      }
    }
    try {
      final s = await _connect(mac);
      Future<Uint8List> rd(String svc, String c) async {
        try {
          return await UniversalBle.read(id, svc, c);
        } catch (_) {
          return Uint8List(0);
        }
      }

      return BleTagInfo(
        manufacturer: _str(await rd(disSvc, mfrChr)),
        model: _str(await rd(disSvc, modelChr)),
        hw: _str(await rd(disSvc, hwRevChr)),
        fw: _str(await rd(disSvc, fwRevChr)),
        otaCapable: _has(s, otaSvc, otaCtrl) || _has(s, otaSvc, otaData),
      );
    } finally {
      await _disconnect(mac);
      _setBusy(null);
    }
  }

  /// CTE 송신 주기(ms) 설정. 0.625 ms 단위로 반올림해 쓰고, 실제 적용된 ms를
  /// 돌려준다. 태그에 CTE 서비스가 없으면 작업자용 메시지로 throw.
  Future<double> setCteIntervalMs(String mac, int ms) async {
    final r = await _op('송신 주기 설정', mac, () => _setCteIntervalMs(mac, ms));
    setStatus('송신 주기 적용 · $mac · ${r.toStringAsFixed(1)} ms');
    return r;
  }

  Future<double> _setCteIntervalMs(String mac, int ms) async {
    final units = (ms / 0.625).round().clamp(32, 0xFFFF);
    _setBusy(mac.toUpperCase());
    final remote = _remote(mac);
    if (remote != null) {
      try {
        return await remote.interval(mac.toUpperCase(), ms);
      } finally {
        _setBusy(null);
      }
    }
    try {
      final s = await _connect(mac);
      if (!_has(s, cteSvc, cteIntervalChr)) {
        throw '이 태그에는 CTE 송신 주기 설정(0x184A/0x2BB1)이 없습니다';
      }
      await UniversalBle.write(_id(mac), cteSvc, cteIntervalChr,
          Uint8List.fromList([units & 0xFF, units >> 8]));
      return units * 0.625;
    } finally {
      await _disconnect(mac);
      _setBusy(null);
    }
  }

  /// OTA data 특성에 쓸 .gbl 조각.
  static List<Uint8List> chunks(Uint8List gbl, int size) => [
        for (var i = 0; i < gbl.length; i += size)
          Uint8List.sublistView(
              gbl, i, i + size > gbl.length ? gbl.length : i + size),
      ];

  /// 태그 1개를 [gbl]로 펌웨어 업데이트한다. 실패 시 작업자용 메시지로
  /// throw, 성공 시 업데이트 후 읽은 펌웨어 리비전을 돌려준다.
  Future<String> otaUpdate(String mac, Uint8List gbl,
      void Function(OtaProgress) onProgress) async {
    try {
      final fw = await _otaUpdate(mac, gbl, (p) {
        setStatus('펌웨어 업데이트 · ${p.step}');
        onProgress(p);
      });
      setStatus('펌웨어 업데이트 완료 · $mac${fw.isEmpty ? '' : ' · FW $fw'}');
      return fw;
    } catch (e) {
      final m = otaHint(e);
      setStatus('펌웨어 업데이트 실패 · $mac · $m', error: true);
      throw m;
    }
  }

  Future<String> _otaUpdate(String mac, Uint8List gbl,
      void Function(OtaProgress) onProgress) async {
    final up = mac.toUpperCase();
    final remote = _remote(mac);
    if (remote != null) return _otaViaLocator(remote, up, gbl, onProgress);
    final id = _id(mac);
    _setBusy(up);
    String ota = up; // AppLoader가 응답하는 주소
    otaTrace.clear();
    _t0 = DateTime.now();
    try {
      final tg = tags[up];
      if (tg != null && tg.appLoader) {
        // 이미 부트로더에서 대기 중 (이전 시도가 중단됨).
        _tr('tag already in AppLoader (${tg.otaAddr})');
        onProgress(const OtaProgress('업데이트 모드 연결 중', 0.05));
        ota = await _connectAppLoader(up);
      } else {
        // 1) 앱: 부트로더 진입 요청. 태그가 응답 후 스스로 링크를 끊고
        //    AppLoader로 리셋한다 (in_place_ota_dfu).
        onProgress(const OtaProgress('태그 연결 중', 0.01));
        final s0 = await _connect(up);
        _tr('app connect ok: ${_svcList(s0)}');
        if (!_has(s0, otaSvc, otaCtrl)) {
          await _disconnect(up);
          throw '이 태그 펌웨어는 OTA를 지원하지 않습니다 (OTA 서비스 없음). '
              'in_place_ota_dfu·bootloader_interface 컴포넌트를 넣은 펌웨어를 '
              'SWD(J-Link)로 한 번 기록해야 이후 OTA가 가능합니다.';
        }
        onProgress(const OtaProgress('업데이트 모드로 재부팅 중', 0.03));
        try {
          await UniversalBle.write(
              id, otaSvc, otaCtrl, Uint8List.fromList([0x00]));
          _tr('OTA control 0x00 written');
        } catch (e) {
          // 태그가 쓰기 응답 전에 링크를 끊을 수 있다.
          _tr('OTA control 0x00 write: $e');
        }
        await _waitDisconnected(up, const Duration(seconds: 8));
        _tr('app link down');
        // 2) AppLoader: 광고를 찾아 접속하고 이미지를 보낸다.
        onProgress(const OtaProgress('업데이트 모드 연결 중', 0.05));
        ota = await _connectAppLoader(up);
      }
      final oid = _id(ota);

      var mtu = 23;
      try {
        mtu = await UniversalBle.requestMtu(oid, 247);
      } catch (_) {}
      final size = (mtu - 3).clamp(20, 244);
      _tr('AppLoader $ota: mtu $mtu, chunk $size, ${gbl.length} B');
      await UniversalBle.write(oid, otaSvc, otaCtrl, Uint8List.fromList([0x00]));
      final parts = chunks(gbl, size);
      for (var i = 0; i < parts.length; i++) {
        // 16번째 조각마다 응답 있는 쓰기: 흐름 제어 + 링크가 끊겼으면 허공에
        // 쓰지 않고 바로 에러.
        await UniversalBle.write(oid, otaSvc, otaData, parts[i],
            withoutResponse: i % 16 != 15);
        if (i % 8 == 0 || i == parts.length - 1) {
          final f = (i + 1) / parts.length;
          onProgress(OtaProgress(
              '전송 중 ${(f * 100).round()}% (${((i + 1) * size / 1024).round()} / ${(gbl.length / 1024).round()} KB)',
              0.05 + 0.85 * f));
        }
      }
      _tr('image sent (${parts.length} writes)');
      onProgress(const OtaProgress('검증 후 재부팅 중', 0.92));
      try {
        await UniversalBle.write(
            oid, otaSvc, otaCtrl, Uint8List.fromList([0x03]));
      } catch (_) {
        // AppLoader가 바로 재부팅할 수 있다.
      }
      await _disconnect(ota);
      tags[up]
        ?..appLoader = false
        ..otaAddr = null;

      // 3) 새 앱(태그 원래 주소): 버전 확인. 부팅 + BT 시작에 몇 초 걸리므로
      //    ~30초 동안 재시도.
      onProgress(const OtaProgress('새 펌웨어 확인 중', 0.95));
      await Future.delayed(const Duration(seconds: 5));
      String fw = '';
      for (var i = 0; i < 6 && fw.isEmpty; i++) {
        try {
          final s = await _connect(up);
          if (_has(s, disSvc, fwRevChr)) {
            fw = _str(await UniversalBle.read(id, disSvc, fwRevChr));
          }
        } catch (_) {
        } finally {
          await _disconnect(up);
        }
        if (fw.isEmpty) await Future.delayed(const Duration(seconds: 3));
      }
      _tr('new FW revision: ${fw.isEmpty ? '(not read)' : fw}');
      onProgress(OtaProgress(
          fw.isEmpty
              ? '전송 완료 · 새 버전 확인 못 함 ([상태 읽기]로 확인하세요)'
              : '완료 · FW $fw',
          1));
      return fw;
    } catch (e) {
      _tr('FAILED: $e');
      rethrow;
    } finally {
      await _disconnect(ota);
      if (ota != up) await _disconnect(up);
      _setBusy(null);
    }
  }

  /// 로케이터 카드가 OTA를 수행하고(같은 AN1086 절차) 여기서는 진행을 폴링한다.
  Future<String> _otaViaLocator(LocatorBleApi api, String mac, Uint8List gbl,
      void Function(OtaProgress) onProgress) async {
    _setBusy(mac);
    otaTrace
      ..clear()
      ..add('via locator ${api.ip}');
    try {
      onProgress(const OtaProgress('로케이터로 펌웨어 전송 중', 0));
      await api.startOta(mac, gbl);
      var fails = 0;
      while (true) {
        await Future.delayed(const Duration(seconds: 1));
        Map<String, dynamic> d;
        try {
          d = await api.otaStatus();
          fails = 0;
        } catch (e) {
          // 카드가 잠깐 바쁘거나 네트워크가 흔들려도 OTA는 카드에서 계속 돈다.
          if (++fails >= 30) throw '로케이터 응답 없음 ($e)';
          continue;
        }
        otaTrace
          ..clear()
          ..add('via locator ${api.ip}')
          ..addAll([for (final t in (d['trace'] as List? ?? const [])) '$t']);
        final tr = d['trace'] as List? ?? const [];
        onProgress(OtaProgress(
            '${d['step'] ?? ''}${tr.isEmpty ? '' : ' — ${tr.last}'}',
            (d['fraction'] as num?)?.toDouble() ?? 0));
        final st = d['state'];
        if (st == 'done') {
          tags[mac]
            ?..appLoader = false
            ..otaAddr = null;
          return d['fw']?.toString() ?? '';
        }
        if (st == 'failed') throw d['error']?.toString() ?? '실패';
      }
    } finally {
      _setBusy(null);
    }
  }

  /// 점 표기 버전 비교 ("1.1.0" vs "1.2.0"); 숫자가 아닌 부분은 0. <0, 0, >0.
  static int compareVersion(String a, String b) {
    List<int> p(String v) =>
        v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d;
    }
    return 0;
  }

  /// 파일 이름 locationx_tag_v1.2.3.gbl 에서 "1.2.3" (없으면 '').
  static String versionOf(String fileName) =>
      RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(fileName)?.group(1) ?? '';
}
