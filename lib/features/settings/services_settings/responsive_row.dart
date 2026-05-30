import 'package:flutter/widgets.dart';

class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.breakpoint = 525,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children
                .map((e) => [e, const SizedBox(height: 15)])
                .expand((e) => e)
                .toList()
              ..removeLast(),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children
              .map((e) => Expanded(child: e))
              .expand((e) => [e, const SizedBox(width: 10)])
              .toList()
            ..removeLast(),
        );
      },
    );
  }
}
