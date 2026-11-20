/// Shared plumbing for action sheets, detail cards, and segmented lists.
///
/// Modal sheets run one server call via [ActionState.perform]: success closes
/// the sheet with a message shown in a snackbar; failure keeps the sheet open
/// with [ActionState.errorStrip]. In-page actions use [ActionState.performInline]
/// so the detail page stays open and refreshes in place.
library;

import 'dart:math' as math;

import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../api/tower_client.dart';

/// One line for the error strip: the server's message plus its code.
String describeError(Object e) => switch (e) {
  TowerApiError(:final code, :final message) =>
    code == TowerErrorCode.unknown ? message : '$message (${code.name})',
  TowerTransportError(:final message) => 'Connection problem: $message',
  _ => '$e',
};

/// Open [sheet] as a modal bottom sheet that clears both the keyboard and
/// the system gesture bar, returning any typed result [R].
Future<R?> showTypedSheet<R>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final mq = MediaQuery.of(context);
      final bottomInset = math.max(mq.viewInsets.bottom, mq.viewPadding.bottom);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: SingleChildScrollView(child: sheet),
      );
    },
  );
}

/// Open [sheet] as a modal bottom sheet; when it pops with a message,
/// display that message in a snackbar.
Future<void> showActionSheet(BuildContext context, Widget sheet) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await showTypedSheet<String>(context, sheet);
  if (message != null && message.isNotEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// State mixin for action widgets:
/// - [perform] pops the enclosing sheet/page with a snackbar message.
/// - [performInline] stays on the current page, shows a snackbar, and
///   invokes [onSuccess] so the page can refetch in place.
mixin ActionState<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<void> perform(Future<String> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final message = await action();
      if (mounted) Navigator.of(context).pop(message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = describeError(e);
      });
    }
  }

  Future<void> performInline(
    Future<String> Function() action, {
    Future<void> Function()? onSuccess,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final message = await action();
      if (onSuccess != null) await onSuccess();
      if (!mounted) return;
      setState(() => busy = false);
      if (message.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = describeError(e);
      });
    }
  }

  Widget errorStrip() {
    final text = error;
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

/// Push a full-screen [page]. Like [showActionSheet], a page that pops
/// with a message has that message shown in a snackbar afterwards.
Future<void> openPage(BuildContext context, Widget page) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await Navigator.of(context)
      .push<String>(MaterialPageRoute<String>(builder: (_) => page));
  if (message != null && message.isNotEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Section title inside a list or detail page.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Expressive filled surface card wrapping a group of [InfoRow]s.
class InfoCard extends StatelessWidget {
  const InfoCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        focusable: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// Expressive filled surface card for multi-line prose (Description, Result).
class ContentCard extends StatelessWidget {
  const ContentCard(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: M3ECard(
        variant: M3ECardVariant.filled,
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        focusable: false,
        padding: const EdgeInsets.all(14),
        width: double.infinity,
        child: SelectableText(text),
      ),
    );
  }
}

/// Shared segmented M3 Expressive card list (`16dp` outer, `4dp` inner corners).
class SegmentedCardList extends StatelessWidget {
  const SegmentedCardList({
    required this.itemCount,
    required this.itemBuilder,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return M3EList(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      variant: M3ECardVariant.filled,
      color: scheme.surfaceContainerLow,
      margin: margin,
    );
  }
}

/// One `label: value` line inside an [InfoCard].
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
