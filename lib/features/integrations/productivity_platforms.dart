import 'package:flutter/painting.dart';

/// A Productivity row's look — PRODUCTIVITY_PLATFORMS in the web's
/// `(lib)/integrations/platforms.jsx`.
///
/// Only the icon and description live here, keyed by the API's provider id.
/// WHICH rows appear, their names and their state come from
/// `GET integrations/catalogue`, so a provider the backend adds or renames
/// needs no change (it gets the generic plug mark until it has an icon).
///
/// The Social / Ads rows already live in the copilot catalogue
/// (`copilotPlatforms`), and render through its `PlatformChip`.
class ProductivityPlatform {
  const ProductivityPlatform({
    required this.id,
    required this.name,
    required this.description,
    required this.colors,
    required this.svg,
  });

  final String id;
  final String name;
  final String description;

  /// The `iconBg` gradient's stops (135deg).
  final List<Color> colors;
  final String svg;
}

String _white(String body) => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white">$body</svg>';

final productivityPlatforms = <ProductivityPlatform>[
  ProductivityPlatform(
    id: 'gmail',
    name: 'Gmail',
    description: 'Read and send email from your Gmail account.',
    colors: const [Color(0xFFEA4335), Color(0xFFC5221F)],
    svg: _white(
      '<path d="M24 5.457v13.909c0 .904-.732 1.636-1.636 1.636h-3.819V11.73L12 16.64l-6.545-4.91v9.273H1.636A1.636 1.636 0 0 1 0 19.366V5.457c0-2.023 2.309-3.178 3.927-1.964L5.455 4.64 12 9.548l6.545-4.91 1.528-1.145C21.69 2.28 24 3.434 24 5.457z"/>',
    ),
  ),
  ProductivityPlatform(
    id: 'google_drive',
    name: 'Google Drive',
    description: 'List files in your Google Drive.',
    colors: const [Color(0xFF1FA463), Color(0xFF4285F4)],
    svg: _white(
      '<path d="M7.71 3.5 1.15 15l3.43 6 6.56-11.5L7.71 3.5zm1.73 0 6.57 11.5h6.84L16.28 3.5H9.44zM9.42 16.5 6 22.5h13.12l3.43-6H9.42z"/>',
    ),
  ),
  ProductivityPlatform(
    id: 'google_sheets',
    name: 'Google Sheets',
    description: 'Read and append to spreadsheets in your Google Drive.',
    colors: const [Color(0xFF0F9D58), Color(0xFF0B8043)],
    svg: _white(
      '<path d="M11.318 12.545H7.91v-1.909h3.41v1.91zM14.728 0v6h6l-6-6zm1.363 10.636h-3.41v1.91h3.41v-1.91zm0 3.273h-3.41v1.91h3.41v-1.91zM20.727 6.5v15.864c0 .904-.732 1.636-1.636 1.636H4.909a1.636 1.636 0 0 1-1.636-1.636V1.636C3.273.732 4.005 0 4.909 0h9.318v6.5h6.5zm-3.273 2.773H6.545v7.909h10.91v-7.91zm-6.136 4.636H7.91v1.91h3.41v-1.91z"/>',
    ),
  ),
  ProductivityPlatform(
    id: 'google_docs',
    name: 'Google Docs',
    description: 'Create documents in your Google Drive.',
    colors: const [Color(0xFF4285F4), Color(0xFF1A73E8)],
    svg: _white(
      '<path d="M14.727 6.727H14V0H4.91c-.905 0-1.637.732-1.637 1.636v20.728c0 .904.732 1.636 1.636 1.636h14.182c.904 0 1.636-.732 1.636-1.636V6.727h-6zm-.545 10.455H7.09v-1.364h7.09v1.364zm2.727-3.273H7.091v-1.364h9.818v1.364zm0-3.273H7.091V9.273h9.818v1.363zM14.727 6h6l-6-6v6z"/>',
    ),
  ),
  ProductivityPlatform(
    id: 'google_slides',
    name: 'Google Slides',
    description: 'Create presentations in your Google Drive.',
    colors: const [Color(0xFFF4B400), Color(0xFFE37400)],
    svg: _white(
      '<path d="M14.727 0H4.909C4.005 0 3.273.732 3.273 1.636v20.728c0 .904.732 1.636 1.636 1.636h14.182c.904 0 1.636-.732 1.636-1.636V6.545L14.727 0zM17.455 17.455H6.545V10.91h10.91v6.545zM14.727 6.545V0l6 6.545h-6z"/>',
    ),
  ),
  ProductivityPlatform(
    id: 'google_calendar',
    name: 'Google Calendar',
    description: 'List and create events on your Google Calendar.',
    colors: const [Color(0xFF4285F4), Color(0xFF1967D2)],
    svg: _white(
      '<path d="M19 3h-1V1h-2v2H8V1H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 16H5V9h14v10zM7 11h5v5H7v-5z"/>',
    ),
  ),
  ProductivityPlatform(
    id: 'google_analytics',
    name: 'Google Analytics',
    description: 'Pull reporting from your Google Analytics properties.',
    colors: const [Color(0xFFF9AB00), Color(0xFFE37400)],
    svg: _white(
      '<path d="M19.5 2A2.5 2.5 0 0 0 17 4.5v15a2.5 2.5 0 0 0 5 0v-15A2.5 2.5 0 0 0 19.5 2zM12 9a2.5 2.5 0 0 0-2.5 2.5v8a2.5 2.5 0 0 0 5 0v-8A2.5 2.5 0 0 0 12 9zm-7.5 7a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z"/>',
    ),
  ),
  // The four-colour Microsoft mark keeps its own colours on a dark tile.
  const ProductivityPlatform(
    id: 'outlook',
    name: 'Microsoft Outlook',
    description: 'Use Outlook mail and calendar from your Microsoft account.',
    colors: [Color(0xFF2F2F2F), Color(0xFF1B1B1B)],
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
        '<rect x="1" y="1" width="10.5" height="10.5" fill="#F25022"/>'
        '<rect x="12.5" y="1" width="10.5" height="10.5" fill="#7FBA00"/>'
        '<rect x="1" y="12.5" width="10.5" height="10.5" fill="#00A4EF"/>'
        '<rect x="12.5" y="12.5" width="10.5" height="10.5" fill="#FFB900"/>'
        '</svg>',
  ),
];

/// A catalogue provider the app has no icon or description for yet
/// (GENERIC_APP on the web) — drawn as a plug on slate.
const genericPlatformColors = [Color(0xFF64748B), Color(0xFF475569)];
