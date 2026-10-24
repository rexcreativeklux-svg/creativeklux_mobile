import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';

/// Port of `auth/CodeInput.jsx` — a row of single-character boxes for a
/// one-time code.
///
/// Implemented as ONE hidden text field painted as boxes rather than six
/// fields: that gives paste, SMS/email autofill and backspace across boxes for
/// free, which the web version had to hand-roll with focus juggling.
class CodeInput extends StatefulWidget {
  const CodeInput({
    super.key,
    required this.onChanged,
    this.length = 6,
    this.enabled = true,
    this.autofocus = true,
    this.onCompleted,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final int length;
  final bool enabled;
  final bool autofocus;

  @override
  State<CodeInput> createState() => CodeInputState();
}

class CodeInputState extends State<CodeInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Clear the boxes and refocus — used after a wrong code.
  void clear() {
    _controller.clear();
    widget.onChanged('');
    _focus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = _controller.text;

    return Stack(
      children: [
        // The real input: invisible, but sized over the boxes so a tap anywhere
        // focuses it and the long-press paste menu still works.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              showCursor: false,
              enableInteractiveSelection: true,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                // Strip spaces/symbols so a pasted "123-456" still works.
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(widget.length),
                _UpperCaseFormatter(),
              ],
              onChanged: (v) {
                setState(() {});
                widget.onChanged(v);
                if (v.length == widget.length) widget.onCompleted?.call(v);
              },
            ),
          ),
        ),
        IgnorePointer(
          child: Row(
            children: List.generate(widget.length * 2 - 1, (i) {
              if (i.isOdd) return const SizedBox(width: 8);
              final index = i ~/ 2;
              final char = index < value.length ? value[index] : '';
              final active =
                  _focus.hasFocus &&
                  (index == value.length || (value.length == widget.length && index == widget.length - 1));
              return Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? c.surface : c.gray50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: active ? AppColors.primary : c.gray200, width: active ? 1.5 : 1),
                      boxShadow: active
                          ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.10), spreadRadius: 3)]
                          : null,
                    ),
                    child: Opacity(
                      opacity: widget.enabled ? 1 : 0.6,
                      child: Text(
                        char,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.gray900),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
