import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Port of `(components)/ConfirmDialog.jsx`: title, message, Cancel + a
/// confirm button that turns red for `danger`.
///
/// With [onConfirm], the dialog stays open and busy while it runs, and can't
/// be dismissed halfway — a slow delete can't be fired twice or cancelled
/// mid-request (the web's own reasoning). Resolves true when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  String title = 'Are you sure?',
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
  Future<void> Function()? onConfirm,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      onConfirm: onConfirm,
    ),
  );
  return ok == true;
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.danger,
    required this.onConfirm,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final Future<void> Function()? onConfirm;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (widget.onConfirm != null) {
      setState(() => _busy = true);
      try {
        await widget.onConfirm!();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: widget.message == null ? null : Text(widget.message!),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: c.gray600),
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(backgroundColor: widget.danger ? AppColors.red600 : AppColors.blue600),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
