import 'package:flutter/material.dart';

/// Admin UI helpers (UI-only): shared header/card/chip styling for Admin Home tabs.
class AdminModuleHeader extends StatelessWidget {
  const AdminModuleHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.primaryActions = const [],
    this.bottom,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> primaryActions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (primaryActions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: primaryActions,
            ),
          ],
          if (bottom != null) ...[
            const SizedBox(height: 10),
            bottom!,
          ],
        ],
      ),
    );
  }
}

class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class AdminStatusChip extends StatelessWidget {
  const AdminStatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = status.trim().toLowerCase();

    Color bg;
    Color fg;
    if (s == 'active' || s == 'approved' || s == 'paid' || s == 'completed') {
      bg = Colors.green.withOpacity(0.12);
      fg = Colors.green.shade800;
    } else if (s == 'inactive' || s.contains('deactive') || s == 'disabled') {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
    } else if (s == 'rejected' || s == 'failed' || s == 'cancelled') {
      bg = Colors.red.withOpacity(0.10);
      fg = Colors.red.shade800;
    } else if (s == 'pending' || s == 'processing') {
      bg = Colors.orange.withOpacity(0.14);
      fg = Colors.orange.shade900;
    } else {
      bg = cs.secondaryContainer;
      fg = cs.onSecondaryContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.25)),
      ),
      child: Text(
        status.trim().isEmpty ? '-' : status.trim(),
        style: TextStyle(fontWeight: FontWeight.w800, color: fg, fontSize: 12),
      ),
    );
  }
}
