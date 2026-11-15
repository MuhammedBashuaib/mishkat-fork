import 'package:flutter/widgets.dart';

/// Mounts a tab on its first visit and retains its state on subsequent visits.
class LazyTabStack extends StatefulWidget {
  const LazyTabStack({required this.index, required this.children, super.key});

  final int index;
  final List<Widget> children;

  @override
  State<LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<LazyTabStack> {
  final Set<int> _visited = {};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _visited.contains(index)
              ? widget.children[index]
              : const SizedBox.shrink(),
      ],
    );
  }
}
