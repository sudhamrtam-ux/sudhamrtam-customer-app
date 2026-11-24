import 'package:flutter/material.dart';

import '../../features/shell/site_header.dart';
import 'site_layout.dart';

/// Every page's top bar (owner request 2026-11-14): Back on the left
/// when there is a page to go back to, and a Home button on the
/// right that closes all open pages and shows the Home tab.

/// Bumped when someone asks for Home; the tab frame listens.
final homeRequests = ValueNotifier<int>(0);

/// Closes every page opened on top and shows the Home tab.
void goHome(BuildContext context) {
  homeRequests.value++;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// The tab a page asked the tab frame to show (1 Shop, 3 Cart); the
/// frame shows it and sets this back to null.
final tabRequests = ValueNotifier<int?>(null);

/// Tab numbers for [openTab].
const shopTab = 1;
const cartTab = 3;

/// Closes every page opened on top and shows tab [tab].
void openTab(BuildContext context, int tab) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  tabRequests.value = tab;
}

class PageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PageAppBar({super.key, required this.title, this.actions = const []});

  final Widget title;
  final List<Widget> actions;

  /// The website header and the page's own bar under it.
  static const _wideHeight = 72.0 + 48.0;

  static bool get _wideWindow {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.implicitView ?? dispatcher.views.firstOrNull;
    if (view == null) return false;
    return view.physicalSize.width / view.devicePixelRatio >= siteWideFrom;
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(_wideWindow ? _wideHeight : kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
    // A website (owner, 2026-11-24): the shop's header on every page,
    // then Back and the page's name.
    if (isWideSite(context)) {
      return _WidePageBar(title: title, actions: actions, canGoBack: canGoBack);
    }
    return AppBar(
      title: title,
      actions: [
        ...actions,
        if (canGoBack)
          IconButton(
            key: const Key('goHome'),
            tooltip: 'Home',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => goHome(context),
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _WidePageBar extends StatelessWidget {
  const _WidePageBar({
    required this.title,
    required this.actions,
    required this.canGoBack,
  });

  final Widget title;
  final List<Widget> actions;
  final bool canGoBack;

  @override
  Widget build(BuildContext context) {
    final side = sitePagePadding(context).left;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 72,
          child: SiteHeader(
            selectedIndex: null,
            onSelect: (tab) =>
                tab == 0 ? goHome(context) : openTab(context, tab),
          ),
        ),
        Material(
          color: const Color(0xFFF7F9F3),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: side - 8),
              child: Row(
                children: [
                  if (canGoBack)
                    TextButton.icon(
                      key: const Key('pageBack'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2F4A14),
                      ),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                  if (canGoBack)
                    const Text('|', style: TextStyle(color: Colors.black26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2F4A14),
                      ),
                      child: title,
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
