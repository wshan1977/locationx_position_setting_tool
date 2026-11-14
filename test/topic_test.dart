import 'package:flutter_test/flutter_test.dart';
import 'package:locationx_install_tool/state/mqtt_state.dart';

void main() {
  test('aoaRest: 루트 이름과 무관하게 위치·각도 토픽을 알아본다', () {
    expect(MqttState.aoaRest('controlbit/aoa/position/room/ble-pd-1', 'position'), 'room/ble-pd-1');
    expect(MqttState.aoaRest('acme/aoa/position/room/ble-pd-1', 'position'), 'room/ble-pd-1');
    expect(MqttState.aoaRest('acme/aoa/angle/loc/tag', 'angle'), 'loc/tag');
    expect(MqttState.aoaRest('acme/aoa/angle/loc/tag', 'position'), isNull);
    // 루트는 한 단계만 (외부 프리픽스는 MqttState가 먼저 떼어냄)
    expect(MqttState.aoaRest('locationx/site/acme/aoa/position/r/t', 'position'), isNull);
    expect(MqttState.aoaRest('/aoa/position/r/t', 'position'), isNull);
  });
}
