import 'package:flutter/material.dart';

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

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canGoBack = ModalRoute.of(context)?.canPop ?? false;
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
