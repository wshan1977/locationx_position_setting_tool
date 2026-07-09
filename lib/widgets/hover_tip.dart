import 'package:flutter/material.dart';

/// 공용 설명 툴팁: 마우스를 1초쯤 올리고 있으면 표시된다.
/// 버튼/설정 위젯을 감싸서 사용한다.
Widget hoverTip(String message, Widget child) => Tooltip(
      message: message,
      waitDuration: const Duration(seconds: 1),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
      child: child,
    );
