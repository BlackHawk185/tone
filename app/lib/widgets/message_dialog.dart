import 'package:flutter/material.dart';
import 'package:tone/services/incident_service.dart';
import 'package:tone/widgets/dialog_title_bar.dart';
import 'package:tone/widgets/settings_menu.dart' show SettingsMenu;

void showMessageDialog(BuildContext context, {String initialText = '', List<String>? selectedUnits}) async {
  // Get unit codes the user is subscribed to for messages
  final subscribedCodes = await SettingsMenu.getMessageSubscribedUnitCodes();
  if (subscribedCodes.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Subscribe to a messaging channel in Settings first')),
    );
    return;
  }

  // Default to all subscribed codes
  final selected = Set<String>.from(selectedUnits ?? subscribedCodes);
  final showPicker = subscribedCodes.length > 1;

  if (!context.mounted) return;
  final controller = TextEditingController(text: initialText);
  showDialog(
    context: context,
    useRootNavigator: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: DialogTitleBar(
          title: 'Broadcast Message',
          onClose: () => Navigator.pop(ctx),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPicker) ...[
              const Text('Send to:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: subscribedCodes.map((code) {
                  final label = SettingsMenu.labelFor(code);
                  final isSelected = selected.contains(code);
                  return FilterChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (v) {
                      setDialogState(() {
                        if (v) {
                          selected.add(code);
                        } else if (selected.length > 1) {
                          selected.remove(code);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Message to responders...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          _SendSplitButton(
            onSend: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              _confirmSend(context, text, priority: false, unitCodes: selected.toList());
            },
            onPriority: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              _confirmSend(context, text, priority: true, unitCodes: selected.toList());
            },
          ),
        ],
      ),
    ),
  );
}

void _confirmSend(BuildContext context, String text, {required bool priority, required List<String> unitCodes}) {
  final color = priority ? const Color(0xFFFF6D00) : Theme.of(context).colorScheme.primary;
  final unitLabel = unitCodes.length == 1
      ? SettingsMenu.labelFor(unitCodes.first)
      : '${unitCodes.length} channels';
  showDialog(
    context: context,
    useRootNavigator: false,
    builder: (ctx) => AlertDialog(
      title: DialogTitleBar(
        title: priority ? 'Confirm Priority' : 'Confirm Message',
        leading: [
          if (priority) const Icon(Icons.priority_high, color: Color(0xFFFF6D00)),
          if (priority) const SizedBox(width: 8),
        ],
        onClose: () => Navigator.pop(ctx),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            priority ? 'This will alert responders on $unitLabel:' : 'Send to $unitLabel?',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              border: Border.all(color: color.withAlpha(80)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            showMessageDialog(context, initialText: text, selectedUnits: unitCodes);
          },
          child: const Text('Edit'),
        ),
        FilledButton(
          style: priority ? FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)) : null,
          onPressed: () {
            IncidentService.sendMessage(text, priority: priority, unitCodes: unitCodes);
            Navigator.pop(ctx);
          },
          child: Text(priority ? 'Send Priority' : 'Send'),
        ),
      ],
    ),
  );
}

class _SendSplitButton extends StatefulWidget {
  final VoidCallback onSend;
  final VoidCallback onPriority;
  const _SendSplitButton({required this.onSend, required this.onPriority});

  @override
  State<_SendSplitButton> createState() => _SendSplitButtonState();
}

class _SendSplitButtonState extends State<_SendSplitButton> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.primary;
    final fg = theme.colorScheme.onPrimary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: bg,
              child: InkWell(
                onTap: widget.onSend,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text('Send', style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
            Container(width: 1, color: fg.withOpacity(0.3)),
            Material(
              color: bg,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.arrow_drop_down, color: fg, size: 20),
                  ),
                ),
              ),
            ),
            if (_expanded) ...[
              Container(width: 1, color: fg.withOpacity(0.3)),
              Material(
                color: const Color(0xFFFF6D00),
                child: InkWell(
                  onTap: widget.onPriority,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.priority_high, color: fg, size: 16),
                        const SizedBox(width: 4),
                        Text('Priority', style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
