import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/toast.dart';
import '../../auth/auth_controller.dart';
import '../brand.dart';
import 'manage_ui.dart';
import 'members_tab.dart' show BlankFallback;

/// Port of `brand/manage/components/AllocationTab.jsx` + `ALLOCATION_CONFIG`.
///
/// One difference: the amount field starts at the current total rather than
/// "0", so saving without editing can't zero an allocation by accident.
class AllocationTab extends StatefulWidget {
  const AllocationTab({super.key, required this.brand});

  final Brand brand;

  @override
  State<AllocationTab> createState() => _AllocationTabState();
}

class _Alloc {
  const _Alloc(this.label, this.icon, this.field, this.slug, this.defaultTotal);
  final String label;
  final IconData icon;

  /// Reads `{field}_allocation` / `{field}_used` and is the PATCH body key prefix.
  final String field;

  /// PATCH /brands/{id}/allocations/{slug}
  final String slug;
  final num defaultTotal;
}

const _allocs = [
  _Alloc('Token', LucideIcons.coins, 'token', 'tokens', 10000),
  _Alloc('Team', LucideIcons.users, 'team', 'team', 5),
  _Alloc('Resell', LucideIcons.rotateCcw, 'resell', 'resells', 0),
  _Alloc('Creatives', LucideIcons.palette, 'creative', 'creatives', 0),
  _Alloc('Integration', LucideIcons.plug, 'integration', 'integrations', 0),
  _Alloc('Storage', LucideIcons.hardDrive, 'storage', 'storage', 0),
  // Backend route still 404s (per the web config) — Save works once it ships.
  _Alloc('Copilot', LucideIcons.bot, 'copilot', 'copilot', 0),
];

class _AllocationTabState extends State<AllocationTab> {
  int _index = 0;

  /// Totals saved this session, so the summary updates without a refetch.
  final _savedTotals = <String, num>{};
  final _input = TextEditingController();
  bool _saving = false;

  _Alloc get _a => _allocs[_index];
  num get _total => _savedTotals[_a.field] ?? widget.brand.allocation(_a.field) ?? _a.defaultTotal;
  num get _used => widget.brand.used(_a.field) ?? 0;

  @override
  void initState() {
    super.initState();
    _input.text = '$_total';
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() {
    _index = i;
    _input.text = '$_total';
  });

  Future<void> _save() async {
    final value = num.tryParse(_input.text.trim());
    if (value == null || value < 0) {
      Toast.error('Enter a valid allocation amount.');
      return;
    }
    if (value < _used) {
      Toast.error("Allocation can't be lower than what's already used ($_used).");
      return;
    }
    setState(() => _saving = true);
    final a = _a;
    final res = await context.read<AuthController>().brandApi.updateAllocation(widget.brand.id, a.slug, a.field, value);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.ok) _savedTotals[a.field] = value;
    });
    res.ok
        ? Toast.success('${a.label} allocation updated.')
        : Toast.error(res.message.ifBlank("Couldn't update ${a.label.toLowerCase()} allocation."));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = _a;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, x) in _allocs.indexed)
              GestureDetector(
                onTap: () => _select(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: i == _index ? c.blueTint : c.surface,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: i == _index ? const Color(0xFFBEDBFF) : c.gray200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(x.icon, size: 14, color: i == _index ? AppColors.blue600 : c.gray500),
                      const SizedBox(width: 6),
                      Text(
                        x.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: i == _index ? AppColors.blue600 : c.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Assign ${a.label.toLowerCase()} allocation to your brand.',
          style: TextStyle(fontSize: 13, color: c.gray500),
        ),
        const SizedBox(height: 10),
        ManageCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${a.label} Remaining', style: TextStyle(fontSize: 13, color: c.gray500)),
                    const SizedBox(height: 4),
                    Text(
                      '${_total - _used}',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.gray900),
                    ),
                    Text('$_used used of $_total', style: TextStyle(fontSize: 12.5, color: c.gray400)),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.blueTint, borderRadius: BorderRadius.circular(12)),
                child: Icon(a.icon, size: 20, color: AppColors.blue600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ManageCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ManageField(
                label: '${a.label} Allocation',
                child: TextField(
                  controller: _input,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: manageInput(context, '0'),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: PrimaryAction(label: 'Save Changes', loading: _saving, onPressed: _save),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
