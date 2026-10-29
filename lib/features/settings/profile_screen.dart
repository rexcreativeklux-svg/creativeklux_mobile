import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/app_input.dart';
import '../../core/ui/media.dart';
import '../../core/ui/toast.dart';
import '../auth/auth_controller.dart';
import 'account_sections.dart';
import 'settings_api.dart';
import 'settings_widgets.dart';

/// Port of `(settings)/profile/page.jsx` — "Account settings": profile (name +
/// photo), password, active sessions, log out / delete account.
///
/// The profile card is live (`POST /profile`; the photo goes to `POST /gallery`
/// first and only its URL is saved as `profile_pic`). Password, sessions and
/// delete still point at unconfirmed endpoints, as on the web.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  late final AuthController _auth = context.read<AuthController>();
  late final SettingsApi _api = SettingsApi(_auth.api);

  /// The freshly uploaded photo URL to save (null = unchanged).
  String? _profilePicUrl;

  /// Shown in the avatar while the upload runs (the web's FileReader preview).
  Uint8List? _localPreview;
  bool _uploading = false;
  bool _saving = false;
  Object? _syncedUserId;

  @override
  void initState() {
    super.initState();
    _syncFromUser();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Seed the editable fields when a (different) user loads — keyed on the id
  /// so a profile refresh right after a save doesn't clobber edits (the web
  /// does the same during render).
  void _syncFromUser() {
    final user = _auth.user;
    _syncedUserId = user?['id'];
    _name.text = '${user?['name'] ?? ''}';
    _profilePicUrl = null;
    _localPreview = null;
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 2 * 1024 * 1024) {
      Toast.error('Please choose an image under 2 MB.');
      return;
    }
    setState(() {
      _localPreview = bytes;
      _uploading = true;
    });
    try {
      final url = await _api.uploadImage(bytes, file.name);
      if (!mounted) return;
      if (url == null) {
        Toast.error("We couldn't get a URL for your photo. Please try again.");
        setState(() => _localPreview = null);
        return;
      }
      setState(() {
        _profilePicUrl = url;
        _localPreview = null;
      });
      Toast.success('Photo uploaded — remember to save.');
    } catch (e) {
      Toast.error(toUserMessage(e, "Couldn't upload your photo. Please try again."));
      if (mounted) setState(() => _localPreview = null);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      Toast.error('Please enter a display name.');
      return;
    }
    if (_uploading) {
      Toast.info('Please wait for the photo upload to finish.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      // Only send the picture when it changed (a fresh gallery URL).
      await _api.updateProfile({'name': name, 'profile_pic': ?_profilePicUrl});
      // Refresh the cached user so the change shows everywhere (top bar…).
      await _auth.fetchProfile();
      if (!mounted) return;
      setState(() => _profilePicUrl = null);
      Toast.success('Profile saved.');
    } catch (e) {
      Toast.error(toUserMessage(e, "Couldn't update your profile."));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.user?['id'] != _syncedUserId) {
      // Writing the controller fires its listener's setState, which isn't
      // allowed mid-build — so mark it synced now and re-seed after the frame.
      _syncedUserId = auth.user?['id'];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_syncFromUser);
      });
    }

    return SettingsScaffold(
      children: [
        const SettingsHeader('Account settings', subtitle: 'Manage your profile, security, and sessions'),
        _profileCard(context, auth),
        const SizedBox(height: 14),
        const PasswordCard(),
        const SizedBox(height: 14),
        const SessionsCard(),
        const SizedBox(height: 18),
        const AccountActions(),
      ],
    );
  }

  Widget _profileCard(BuildContext context, AuthController auth) {
    final c = context.colors;
    final name = _name.text;
    final dirty = name.trim() != '${auth.user?['name'] ?? ''}' || _profilePicUrl != null;
    final savedPic = auth.user?['profile_pic']?.toString();
    final pic = _profilePicUrl ?? (savedPic != null && savedPic.isNotEmpty ? savedPic : null);
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CardLabel('Profile'),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: c.gray100,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.gray200),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_localPreview != null)
                      Image.memory(_localPreview!, fit: BoxFit.cover)
                    else if (pic != null)
                      MediaImage(pic, fit: BoxFit.cover, cacheWidth: 160)
                    else
                      Center(
                        child: Text(
                          initials.isEmpty ? '?' : initials,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.gray500),
                        ),
                      ),
                    if (_uploading)
                      ColoredBox(
                        color: c.surface.withValues(alpha: 0.6),
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Your name' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: c.gray900),
                    ),
                    Text(
                      auth.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.gray500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _uploading ? null : _pickPhoto,
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.gray600,
                  side: BorderSide(color: c.gray300),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
                child: Text(_uploading ? 'Uploading…' : 'Change photo'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppInput(
            label: 'Display name',
            controller: _name,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.name],
          ),
          const SizedBox(height: 12),
          _ReadOnlyField(label: 'Email address', value: auth.email),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: SettingsButton(
              label: 'Save changes',
              loading: _saving,
              color: c.gray800,
              foreground: c.surface,
              onPressed: _uploading || !dirty ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// The disabled email input — shown, not editable (the web's `disabled`).
class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.gray500),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.gray50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.gray200),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: c.gray400),
          ),
        ),
      ],
    );
  }
}
