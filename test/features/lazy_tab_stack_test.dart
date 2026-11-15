import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mishkat_app/features/shell/presentation/widgets/lazy_tab_stack.dart';

void main() {
  testWidgets('tabs mount on demand, retain state and receive active changes', (
    tester,
  ) async {
    final mounts = <int>[];
    Widget app(int index) => Directionality(
      textDirection: TextDirection.ltr,
      child: LazyTabStack(
        index: index,
        children: [
          for (var tab = 0; tab < 3; tab++)
            _Probe(tab: tab, active: tab == index, mounts: mounts),
        ],
      ),
    );
    await tester.pumpWidget(app(1));
    expect(mounts, [1]);
    final original = tester.state(find.byType(_Probe));
    await tester.pumpWidget(app(2));
    expect(mounts, [1, 2]);
    expect(find.text('2:true'), findsOneWidget);
    expect(find.text('1:false', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(app(1));
    expect(mounts, [1, 2]);
    expect(identical(tester.state(find.byType(_Probe)), original), isTrue);
    expect(find.text('1:true'), findsOneWidget);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.tab, required this.active, required this.mounts});
  final int tab;
  final bool active;
  final List<int> mounts;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.mounts.add(widget.tab);
  }

  @override
  Widget build(BuildContext context) => Text('${widget.tab}:${widget.active}');
}
