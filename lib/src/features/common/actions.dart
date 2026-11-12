/// Shared plumbing for the action sheets (prompt, respond, queue job,
/// assign, release, cancel, run workflow).
///
/// A sheet runs one server call. Success closes the sheet with a
/// message the caller shows in a snackbar. Failure keeps the sheet open
/// and shows the error in a strip inside it, so the user can fix the
/// input and retry.
library;

import 'package:flutter/material.dart';

import '../../api/tower_client.dart';

/// One line for the error strip: the server's message plus its code.
String describeError(Object e) => switch (e) {
  TowerApiError(:final code, :final message) =>
    code == TowerErrorCode.unknown ? message : '$message (${code.name})',
  TowerTransportError(:final message) => 'Connection problem: $message',
  _ => '$e',
};

/// Open [sheet] as a modal bottom sheet that rises above the keyboard.
/// Returns the success message the sheet popped with, if any, and shows
/// it in a snackbar.
Future<void> showActionSheet(BuildContext context, Widget sheet) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(child: sheet),
    ),
  );
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// State mixin for a sheet: [perform] runs a call, pops with its message
/// on success, shows [errorStrip] on failure.
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

  Widget errorStrip() {
    final text = error;
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

/// Push a full-screen [page]. Like [showActionSheet], a page that pops
/// with a message has that message shown in a snackbar afterwards.
Future<void> openPage(BuildContext context, Widget page) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await Navigator.of(context)
      .push<String>(MaterialPageRoute<String>(builder: (_) => page));
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Section title inside a detail page.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// One `label: value` line in a detail page.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}
