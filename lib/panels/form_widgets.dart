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
            child: Text(o, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
