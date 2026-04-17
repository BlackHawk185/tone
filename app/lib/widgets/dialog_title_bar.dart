import 'package:flutter/material.dart';

/// Standard dialog title bar with close button.
/// Used by all AlertDialogs in the app for consistent dismiss UX.
class DialogTitleBar extends StatelessWidget {
  final String title;
  final List<Widget> leading;
  final VoidCallback? onClose;

  const DialogTitleBar({
    super.key,
    required this.title,
    this.leading = const [],
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...leading,
        Expanded(child: Text(title)),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onClose ?? () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}
