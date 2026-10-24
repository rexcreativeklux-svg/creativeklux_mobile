import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/brand/manage/brand_manage_screen.dart';
import '../../features/brand/screens/brand_form_screen.dart';
import '../../features/brand/screens/brand_invite_screen.dart';
import '../../features/brand/screens/brand_kits_screen.dart';
import '../../features/copilot/plugins/plugins_screen.dart';
import '../../features/copilot/screens/all_copilots_screen.dart';
import '../../features/copilot/screens/copilot_home_screen.dart';
import '../../features/copilot/workspace/conversation_screen.dart';
import '../../features/copilot/workspace/workflows_screen.dart';
import '../../features/creatives/creatives_screen.dart';
import '../../features/designs/designs_screen.dart';
import '../../features/editor/design_editor_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/magic_studio/magic_studio_screen.dart';
import '../../features/magic_studio/magic_studio_types.dart';
import '../../features/studio/ai_chat_screen.dart';
import '../../features/studio/custom/create_from_url_screen.dart';
import '../../features/studio/custom/custom_studio_screen.dart';
import '../../features/shell/dashboard_shell.dart';
import '../../features/shell/porting_screen.dart';
import '../../features/shell/splash_screen.dart';

/// Routes keep the web app's URL paths, so a page's port is easy to find from
/// either side (and deep links can match the web later).
const _authRoutes = {'/login', '/register', '/forgot-password', '/change-password', '/verify-email'};

/// Web pages not ported yet → [PortingScreen]. Swap each for its real screen
/// as it lands. Paths and titles match the web sidebar/account menu.
const _pending = <(String, String, String, IconData)>[
  ('/product-studio', 'Product Studio', '(dashboard)/(pages)/product-studio', LucideIcons.bookImage),
  ('/edit_a_photo', 'Photo Editor', '(dashboard)/(pages)/edit_a_photo', LucideIcons.image),
  ('/social-content', 'Social', '(dashboard)/(pages)/social-content', LucideIcons.share2),
  (
    '/social-content/calendar',
    'Content Calendar',
    '(dashboard)/(pages)/social-content/calendar',
    LucideIcons.calendarCheck,
  ),
  ('/ads-content', 'Ads', '(dashboard)/(pages)/ads-content', LucideIcons.megaphone),
  ('/ad-intelligence', 'Ad Intelligence', '(dashboard)/(pages)/ad-intelligence', LucideIcons.brain),
  ('/profile', 'Profile Settings', '(dashboard)/(pages)/(settings)/profile', LucideIcons.user),
  ('/gallery', 'Gallery', '(dashboard)/(pages)/gallery', LucideIcons.image),
  ('/integrations', 'Integrations', '(dashboard)/(pages)/integrations', LucideIcons.workflow),
  ('/resell', 'Resell', '(dashboard)/(pages)/(settings)/resell', LucideIcons.shoppingCart),
  ('/billing', 'Plans And Billing', '(dashboard)/(pages)/(settings)/billing', LucideIcons.creditCard),
  ('/help', 'Help', '(dashboard)/(pages)/help', LucideIcons.circleHelp),
];

GoRouter buildRouter(AuthController auth, IntroGate intro) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([auth, intro]),
    redirect: (context, state) {
      final loc = state.matchedLocation;

      // Opening animation still playing, or the session still being confirmed
      // → splash. The original target rides along in `from`, so a deep link
      // that cold-starts the app still lands where it pointed.
      if (auth.loading || !intro.done) {
        if (loc == '/splash') return null;
        return Uri(path: '/splash', queryParameters: {'from': state.uri.toString()}).toString();
      }
      if (loc == '/splash') {
        final from = state.uri.queryParameters['from'];
        return from != null && from != '/splash' && !from.startsWith('/splash?') ? from : '/';
      }

      // Invite links work signed in or out (the page handles both), like the web.
      if (loc.startsWith('/invites/')) return null;

      final onAuthRoute = _authRoutes.contains(loc);
      if (!auth.isLoggedIn) return onAuthRoute ? null : '/login';

      // Signed in but unverified → the verify gate. A missing cached user
      // (offline first launch) is let through rather than trapped.
      if (auth.user != null && !auth.isVerified) return loc == '/verify-email' ? null : '/verify-email';

      // Just signed in with an invite parked → back to it.
      if (onAuthRoute) return auth.pendingInvite != null ? '/invites/${auth.pendingInvite}' : '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, _) => NoTransitionPage(child: SplashScreen(gate: intro)),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      // Full screen (no bottom nav) — the conversation and keyboard need the room.
      GoRoute(
        path: '/studio/ai-chat-page',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return AiChatScreen(
            creative: q['creative'],
            model: q['model'],
            initialMessage: q['initialMessage'],
            images: state.uri.queryParametersAll['image'] ?? const [],
            sessionId: q['session'],
          );
        },
      ),
      // The editor is full screen on the web too — no dashboard chrome.
      GoRoute(
        path: '/design/:id',
        redirect: (_, state) => int.tryParse(state.pathParameters['id'] ?? '') == null ? '/creatives' : null,
        builder: (_, state) => DesignEditorScreen(
          designId: int.parse(state.pathParameters['id']!),
          initialPanel: state.uri.queryParameters['panel'],
        ),
      ),
      GoRoute(
        path: '/invites/:token',
        builder: (_, state) => BrandInviteScreen(token: state.pathParameters['token'] ?? ''),
      ),
      GoRoute(
        path: '/change-password',
        builder: (_, state) => ChangePasswordScreen(email: state.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) => VerifyEmailScreen(email: state.uri.queryParameters['email']),
      ),
      ShellRoute(
        builder: (context, state, child) => DashboardShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, _) => const NoTransitionPage(child: HomeScreen()),
          ),
          // ── Creatives (step 3) ──
          GoRoute(
            path: '/creatives',
            pageBuilder: (_, _) => const NoTransitionPage(child: CreativesScreen()),
          ),
          // ── Brand (step 2) ──
          GoRoute(path: '/brand/reuse', builder: (_, _) => const BrandKitsScreen()),
          GoRoute(path: '/brand/create', builder: (_, _) => const BrandFormScreen.create()),
          GoRoute(
            path: '/brand/edit/:id',
            redirect: (_, state) => int.tryParse(state.pathParameters['id'] ?? '') == null ? '/brand/reuse' : null,
            builder: (_, state) => BrandFormScreen.edit(brandId: int.parse(state.pathParameters['id']!)),
          ),
          GoRoute(path: '/brand/manage', builder: (_, _) => const BrandManageScreen()),
          // ── Magic Studio ── bare /magic-studio opens the first tool (page.jsx).
          GoRoute(path: '/magic-studio', redirect: (_, _) => firstMagicTool.path),
          GoRoute(
            path: '/magic-studio/:tool',
            redirect: (_, state) => magicToolBySlug(state.pathParameters['tool']) == null ? firstMagicTool.path : null,
            pageBuilder: (_, state) => NoTransitionPage(child: MagicStudioScreen(slug: state.pathParameters['tool'])),
          ),
          // ── Custom Creation ──
          GoRoute(path: '/studio/select', builder: (_, _) => const StudioSelectScreen()),
          GoRoute(path: '/studio/create-from-url', builder: (_, _) => const CreateFromUrlScreen()),
          GoRoute(
            path: '/studio',
            builder: (_, state) => CustomStudioScreen(creative: state.uri.queryParameters['creative']),
          ),
          // ── Templates (Klux pool + the static poster gallery) ──
          GoRoute(
            path: '/designs',
            builder: (_, state) => DesignsScreen(initialTab: state.uri.queryParameters['tab']),
          ),
          // ── Copilot ── home + catalog live in the shell; a copilot's own
          // workspace is full screen (below).
          GoRoute(
            path: '/copilot',
            pageBuilder: (_, state) =>
                NoTransitionPage(child: CopilotHomeScreen(task: state.uri.queryParameters['task'])),
          ),
          GoRoute(path: '/copilot/all', builder: (_, _) => const AllCopilotsScreen()),
          for (final (path, title, webPath, icon) in _pending)
            GoRoute(
              path: path,
              builder: (_, _) => PortingScreen(title: title, webPath: webPath, icon: icon),
            ),
        ],
      ),
      // A copilot's workspace — full screen (no bottom nav): the conversation
      // and the keyboard need the room. ⚠️ AFTER the ShellRoute, so the shell's
      // `/copilot/all` matches before `:id` could swallow "all".
      GoRoute(
        path: '/copilot/:id',
        builder: (_, state) {
          final q = state.uri.queryParameters;
          return CopilotConversationScreen(
            key: ValueKey(state.uri.toString()),
            id: state.pathParameters['id']!,
            conversationId: q['c'],
            task: q['task'] ?? '',
            send: q['send'] ?? '',
            isNew: q['new'] == '1',
          );
        },
        routes: [
          GoRoute(
            path: 'workflows',
            builder: (_, state) => CopilotWorkflowsScreen(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'plugins',
            builder: (_, state) => CopilotPluginsScreen(id: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
}
