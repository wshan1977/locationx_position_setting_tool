import 'package:flutter/material.dart';

/// 외부에서 값이 바뀌어도(예: 마커 드래그) 동기화되는 숫자 입력 필드.
/// 포커스 중에는 사용자의 입력을 우선한다.
class NumField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final int fractionDigits;

  const NumField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.fractionDigits = 2,
  });

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  String _fmt(double v) => v.toStringAsFixed(widget.fractionDigits);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.value));
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        // 포커스를 잃으면 값 확정 + 표기 정규화
        final v = double.tryParse(_controller.text.trim());
        if (v != null) {
          widget.onChanged(v);
        }
        _controller.text = _fmt(widget.value);
      }
    });
  }

  @override
  void didUpdateWidget(NumField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 13),
      onSubmitted: (text) {
        final v = double.tryParse(text.trim());
        if (v != null) widget.onChanged(v);
      },
    );
  }
}

/// 현재 값이 목록에 없어도 표시 가능한 드롭다운.
/// 위치 계산 엔진 설정값(장비 SDK 상수 문자열) → 화면 표시 이름.
/// 값 자체는 그대로 저장·전송하고 화면에만 쓴다 (모르는 값은 원문 표시).
const _settingLabels = {
  'SL_RTL_LOC_ESTIMATION_MODE_THREE_DIM_HIGH_ACCURACY': '3D · 고정밀',
  'SL_RTL_LOC_ESTIMATION_MODE_THREE_DIM_FAST_RESPONSE': '3D · 빠른 반응',
  'SL_RTL_LOC_ESTIMATION_MODE_TWO_DIM_HIGH_ACCURACY': '2D · 고정밀 (태그 높이 고정)',
  'SL_RTL_LOC_ESTIMATION_MODE_TWO_DIM_FAST_RESPONSE': '2D · 빠른 반응 (태그 높이 고정)',
  'SL_RTL_LOC_MEASUREMENT_VALIDATION_MINIMUM': '최소 (대부분 사용)',
  'SL_RTL_LOC_MEASUREMENT_VALIDATION_MEDIUM': '중간',
  'SL_RTL_LOC_MEASUREMENT_VALIDATION_FULL': '엄격 (반사 환경)',
  'SL_RTL_AOX_MODE_REAL_TIME_BASIC': 'AoA · 기본 (권장)',
  'SL_RTL_AOX_MODE_REAL_TIME_FAST_RESPONSE': 'AoA · 빠른 반응',
  'SL_RTL_AOX_MODE_REAL_TIME_HIGH_ACCURACY': 'AoA · 고정밀',
  'SL_RTL_AOX_MODE_REAL_HIGH_ACCURACY': 'AoA · 고정밀 (구 표기)',
  'SL_RTL_AOD_MODE_REAL_TIME_FAST_RESPONSE': 'AoD · 빠른 반응',
  'SL_RTL_AOD_MODE_REAL_TIME_BASIC': 'AoD · 기본',
  'SL_RTL_AOX_ARRAY_TYPE_4x4_URA': '4×4 평면 배열 (기본)',
  'SL_RTL_AOX_ARRAY_TYPE_3x3_URA': '3×3 평면 배열',
  'SL_RTL_AOX_ARRAY_TYPE_1x4_ULA': '1×4 직선 배열',
  'SILABS': '전용 비연결 방식 (기본)',
  'CONNLESS': 'BLE 표준 비연결 (주기적 광고)',
  'CONN': 'BLE 연결 기반',
};

/// 설정값의 화면 표시 이름.
String settingLabel(String value) => _settingLabels[value] ?? value;

class SafeDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const SafeDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final items = [...options];
    if (!items.contains(value)) items.insert(0, value);
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 12, color: Colors.black87),
      items: [
        for (final o in items)
          DropdownMenuItem(
            value: o,
            child: Text(settingLabel(o), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
