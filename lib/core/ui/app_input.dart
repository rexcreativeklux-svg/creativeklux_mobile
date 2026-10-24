import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// Port of `(components)/ui/Input.jsx`: label (+ "(optional)" badge and an
/// optional right-aligned action), password mode with a show/hide eye, and an
/// error or hint line beneath.
class AppInput extends StatefulWidget {
  const AppInput({
    super.key,
    required this.label,
    required this.controller,
    this.placeholder,
    this.password = false,
    this.optional = false,
    this.hint,
    this.error,
    this.rightLabel,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? placeholder;
  final bool password;
  final bool optional;
  final String? hint;
  final String? error;
  final Widget? rightLabel;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Text.rich(
                TextSpan(
                  text: widget.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
                  children: [
                    if (widget.optional)
                      TextSpan(
                        text: ' (optional)',
                        style: TextStyle(color: c.gray300, fontWeight: FontWeight.w400),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              ?widget.rightLabel,
            ],
          ),
        ),
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.password && !_show,
          enableSuggestions: !widget.password,
          autocorrect: !widget.password,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          onSubmitted: widget.onSubmitted,
          style: TextStyle(fontSize: 13.5, color: c.gray900),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.placeholder,
            hintStyle: TextStyle(color: c.gray300, fontSize: 13.5),
            filled: true,
            fillColor: c.gray50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: border(widget.error != null ? AppColors.red500 : c.gray200),
            disabledBorder: border(c.gray200),
            focusedBorder: border(AppColors.primary, 1.5),
            suffixIcon: widget.password
                ? IconButton(
                    onPressed: () => setState(() => _show = !_show),
                    tooltip: _show ? 'Hide password' : 'Show password',
                    icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 17, color: c.gray400),
                  )
                : null,
          ),
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.error!, style: const TextStyle(fontSize: 11.5, color: AppColors.red500)),
          )
        else if (widget.hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.hint!, style: TextStyle(fontSize: 11, color: c.gray400, height: 1.35)),
          ),
      ],
    );
  }
}
