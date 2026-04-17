import 'package:flutter/material.dart';

class InfoGrid extends StatelessWidget {
  final List<Widget> children;
  final bool cardExpanded;
  const InfoGrid({super.key, required this.children, this.cardExpanded = false});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width < 400 ? 1 : 2;

    // When card is expanded: type card fills left, all others stack on right
    if (cardExpanded && cols == 2 && children.length > 1) {
      final others = children.skip(1).toList();
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < others.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    others[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Normal 2-per-row grid
    final List<Widget> rows = [];
    for (int i = 0; i < children.length; i += cols) {
      if (cols == 1) {
        rows.add(children[i]);
      } else {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
          ],
        ));
      }
      if (i + cols < children.length) rows.add(const SizedBox(height: 10));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
