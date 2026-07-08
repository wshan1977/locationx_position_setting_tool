import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/mqtt_state.dart';
import '../widgets/mqtt_connect_bar.dart';
import 'position_live_view.dart';

/// 탭 4: MQTT 뷰어 (MQTT Explorer 유사) + 3D 위치인식 확인 서브탭.
/// 토픽 뷰어: 좌측 토픽 트리 / 우측 선택 토픽 상세 + 실시간 메시지 로그 + 발행.
/// 위치 확인: 도면 위에 angle 방향 점선과 계산된 태그 위치를 실시간 표시.
class MqttViewerTab extends StatefulWidget {
  const MqttViewerTab({super.key});

  @override
  State<MqttViewerTab> createState() => _MqttViewerTabState();
}

class _MqttViewerTabState extends State<MqttViewerTab>
    with SingleTickerProviderStateMixin {
  late final TabController _subTabs;
  /// 선택된 토픽 경로 (트리 노드). null이면 전체.
  String? _selectedPath;
  final Set<String> _expanded = {};

  final _pubTopic = TextEditingController();
  final _pubPayload = TextEditingController();

  @override
  void initState() {
    super.initState();
    _subTabs = TabController(length: 2, vsync: this);
    _subTabs.addListener(() {
      if (!_subTabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _subTabs.dispose();
    _pubTopic.dispose();
    _pubPayload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MqttConnectBar(),
        const Divider(height: 1),
        Row(
          children: [
            SizedBox(
              width: 320,
              child: TabBar(
                controller: _subTabs,
                onTap: (_) => setState(() {}),
                labelStyle: const TextStyle(fontSize: 12.5),
                tabs: const [
                  Tab(height: 36, text: '토픽 뷰어'),
                  Tab(height: 36, text: '3D 위치 확인'),
                ],
              ),
            ),
            const Expanded(child: Divider(height: 1)),
          ],
        ),
        Expanded(
          child: IndexedStack(
            index: _subTabs.index,
            children: [
              _explorerBody(),
              const PositionLiveView(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _explorerBody() {
    final mqtt = context.watch<MqttState>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 340, child: _topicTree(mqtt)),
        const VerticalDivider(width: 1),
        Expanded(child: _rightPane(mqtt)),
      ],
    );
  }

  // =========================================================
  // 좌측: 토픽 트리
  // =========================================================
  Widget _topicTree(MqttState mqtt) {
    final root = _TopicNode.build(mqtt.topics);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            children: [
              Text('토픽 (${mqtt.topics.length})',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_selectedPath != null)
                TextButton(
                  onPressed: () => setState(() => _selectedPath = null),
                  child: const Text('전체 보기', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        Expanded(
          child: mqtt.topics.isEmpty
              ? Center(
                  child: Text('수신된 토픽이 없습니다.',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 13)),
                )
              : ListView(
                  children: [
                    for (final child in root.sortedChildren)
                      ..._nodeTiles(child, 0),
                  ],
                ),
        ),
      ],
    );
  }

  List<Widget> _nodeTiles(_TopicNode node, int depth) {
    final hasChildren = node.children.isNotEmpty;
    final expanded = _expanded.contains(node.path);
    final selected = _selectedPath == node.path;

    final tile = InkWell(
      onTap: () => setState(() {
        _selectedPath = node.path;
        if (hasChildren) {
          if (!_expanded.remove(node.path)) _expanded.add(node.path);
        }
      }),
      child: Container(
        color: selected ? Colors.teal.withValues(alpha: 0.12) : null,
        padding: EdgeInsets.only(left: 8.0 + depth * 16, top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(
              hasChildren
                  ? (expanded ? Icons.expand_more : Icons.chevron_right)
                  : Icons.sell_outlined,
              size: 15,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(node.name,
                  style: const TextStyle(fontSize: 12.5),
                  overflow: TextOverflow.ellipsis),
            ),
            Text(
              node.stat != null ? '${node.stat!.count}' : '${node.totalCount}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );

    return [
      tile,
      if (hasChildren && expanded)
        for (final child in node.sortedChildren) ..._nodeTiles(child, depth + 1),
    ];
  }

  // =========================================================
  // 우측: 상세 + 로그 + 발행
  // =========================================================
  Widget _rightPane(MqttState mqtt) {
    final selected = _selectedPath;
    final stat = selected != null ? mqtt.topics[selected] : null;

    final filtered = selected == null
        ? mqtt.log.toList()
        : mqtt.log
            .where((m) =>
                m.topic == selected || m.topic.startsWith('$selected/'))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stat != null) _topicDetail(selected!, stat),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Text(
            selected == null
                ? '실시간 메시지 (전체, 최신 ${filtered.length}건)'
                : '실시간 메시지 ($selected, ${filtered.length}건)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final m = filtered[i];
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fmtTime(m.ts),
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey.shade500)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 260,
                      child: Text(m.topic,
                          style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.teal),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(m.payload.replaceAll('\n', ' '),
                          style: const TextStyle(
                              fontSize: 11, fontFamily: 'monospace'),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        _publishBar(mqtt),
      ],
    );
  }

  Widget _topicDetail(String topic, TopicStat stat) {
    final now = DateTime.now();
    String pretty = stat.lastPayload;
    try {
      pretty = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(stat.lastPayload));
    } catch (_) {
      // JSON이 아니면 원문 표시
    }
    return Card(
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SelectableText(topic,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                Text(
                  '총 ${stat.count} · ${stat.rateHz(now).toStringAsFixed(1)} msg/s'
                  '${stat.retained ? ' · retained' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: SelectableText(
                  pretty,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _publishBar(MqttState mqtt) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _pubTopic,
              decoration: const InputDecoration(
                labelText: '발행 토픽',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _pubPayload,
              decoration: const InputDecoration(
                labelText: '페이로드',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: mqtt.isConnected
                ? () {
                    final topic = _pubTopic.text.trim();
                    if (topic.isEmpty) return;
                    mqtt.publish(topic, _pubPayload.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('발행됨: $topic')));
                  }
                : null,
            icon: const Icon(Icons.send, size: 16),
            label: const Text('발행'),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 100)}';
}

/// 토픽 문자열들을 '/' 기준 트리로 구성한 노드.
class _TopicNode {
  final String name;
  final String path;
  final Map<String, _TopicNode> children = {};

  /// 이 노드 자체가 완전한 토픽이면 통계가 붙는다.
  TopicStat? stat;

  _TopicNode(this.name, this.path);

  int get totalCount {
    var sum = stat?.count ?? 0;
    for (final c in children.values) {
      sum += c.totalCount;
    }
    return sum;
  }

  List<_TopicNode> get sortedChildren =>
      children.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  static _TopicNode build(Map<String, TopicStat> topics) {
    final root = _TopicNode('', '');
    for (final entry in topics.entries) {
      var node = root;
      var path = '';
      for (final seg in entry.key.split('/')) {
        path = path.isEmpty ? seg : '$path/$seg';
        node = node.children.putIfAbsent(seg, () => _TopicNode(seg, path));
      }
      node.stat = entry.value;
    }
    return root;
  }
}
