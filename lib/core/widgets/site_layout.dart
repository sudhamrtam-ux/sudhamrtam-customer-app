import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../company.dart';

/// The website look (owner, 2026-11-24): on a wide screen (a computer's
/// browser, a tablet on its side) the app looks like a shop's website,
/// with a header, pages in a centred column and a footer. Phones keep
/// the app layout with the bottom tabs.
const siteWideFrom = 900.0;

/// Widest the page content gets on a big screen.
const siteContentWidth = 1200.0;

bool isWideSite(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= siteWideFrom;

/// Padding that keeps a full-width scroll view's content in the centred
/// column on a wide screen (16 on phones).
EdgeInsets sitePagePadding(
  BuildContext context, {
  double top = 16,
  double bottom = 16,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = width >= siteWideFrom
      ? ((width - siteContentWidth) / 2).clamp(32.0, double.infinity)
      : 16.0;
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// Opens [url] in the browser; tests replace it.
Future<bool> Function(Uri url) openSiteLink = (url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

const _footerGreen = Color(0xFF2F4A14);
const _footerText = Color(0xFFDCE8C8);

/// The website's footer: what Sudhamrtam is, the shop's categories,
/// help and policy pages, and the company's contact details.
class SiteFooter extends StatelessWidget {
  const SiteFooter({
    super.key,
    this.categories = const [],
    this.onOpenCategory,
    this.year = 2026,
  });

  final List<String> categories;
  final void Function(String category)? onOpenCategory;
  final int year;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = ((width - siteContentWidth) / 2).clamp(32.0, double.infinity);
    final columns = <Widget>[
      _FooterColumn(
        title: 'Sudhamrtam',
        flex: 3,
        children: const [
          Text(
            'Fresh milk, curd, paneer, ghee, wood-pressed oils and honey '
            'from our farm, delivered to your door in Hyderabad every '
            'morning.',
            style: TextStyle(color: _footerText, height: 1.5),
          ),
          SizedBox(height: 10),
          Text(
            'Order by 9 PM for next-morning delivery.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      if (categories.isNotEmpty)
        _FooterColumn(
          title: 'Shop',
          children: [
            for (final category in categories)
              _FooterLink(
                category,
                key: Key('footer-category-$category'),
                onTap: onOpenCategory == null
                    ? null
                    : () => onOpenCategory!(category),
              ),
          ],
        ),
      _FooterColumn(
        title: 'Help',
        children: [
          _FooterLink(
            'Contact us',
            key: const Key('footer-contact'),
            onTap: () => openSiteLink(Uri.parse(sudhamrtamContactUrl)),
          ),
          _FooterLink(
            'Refunds and Cancellations',
            key: const Key('footer-refunds'),
            onTap: () => openSiteLink(Uri.parse(sudhamrtamRefundsUrl)),
          ),
          _FooterLink(
            'Terms and Conditions',
            key: const Key('footer-terms'),
            onTap: () => openSiteLink(Uri.parse(sudhamrtamTermsUrl)),
          ),
          _FooterLink(
            'Privacy Policy',
            key: const Key('footer-privacy'),
            onTap: () => openSiteLink(Uri.parse(sudhamrtamPrivacyUrl)),
          ),
        ],
      ),
      _FooterColumn(
        title: 'Contact',
        flex: 2,
        children: [
          _FooterLink(
            sudhamrtamSupportPhone,
            icon: Icons.call_outlined,
            onTap: () =>
                openSiteLink(Uri.parse('tel:$sudhamrtamSupportPhoneDial')),
          ),
          _FooterLink(
            sudhamrtamSupportEmails.first,
            icon: Icons.mail_outline,
            onTap: () => openSiteLink(
              Uri.parse('mailto:${sudhamrtamSupportEmails.first}'),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '1-47, Donthi Village, Shivampet Mandal, Medak Dist, '
            'Telangana - 502334',
            style: TextStyle(color: _footerText, height: 1.5),
          ),
        ],
      ),
    ];

    return Container(
      key: const Key('site-footer'),
      width: double.infinity,
      color: _footerGreen,
      padding: EdgeInsets.fromLTRB(side, 40, side, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, column) in columns.indexed) ...[
                if (i > 0) const SizedBox(width: 32),
                column,
              ],
            ],
          ),
          const SizedBox(height: 28),
          const Divider(color: Color(0x33FFFFFF), height: 1),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              Text(
                '© $year $sudhamrtamCompanyName',
                style: const TextStyle(color: _footerText, fontSize: 13),
              ),
              const Text(
                'FSSAI Lic. No. $sudhamrtamFssai',
                style: TextStyle(color: _footerText, fontSize: 13),
              ),
              const Text(
                'GSTIN $sudhamrtamGstin',
                style: TextStyle(color: _footerText, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({
    required this.title,
    required this.children,
    this.flex = 2,
  });

  final String title;
  final List<Widget> children;
  final int flex;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class _FooterLink extends StatelessWidget {
  const _FooterLink(this.label, {super.key, this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: _footerText),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label, style: const TextStyle(color: _footerText)),
          ),
        ],
      ),
    ),
  );
}

/// A page opened from the shop (orders, bills, addresses...): on a wide
/// screen its content sits in a readable column in the middle; on a
/// phone it is a plain [Scaffold].
class SiteScaffold extends Scaffold {
  SiteScaffold({
    super.key,
    super.appBar,
    Widget? body,
    super.floatingActionButton,
    super.bottomNavigationBar,
    super.backgroundColor,
    super.resizeToAvoidBottomInset,
    double maxWidth = 900,
  }) : super(
         body: body == null
             ? null
             : SiteColumn(maxWidth: maxWidth, child: body),
       );
}

/// [child] in a centred column at most [maxWidth] wide, on a wide
/// screen only.
class SiteColumn extends StatelessWidget {
  const SiteColumn({super.key, required this.child, this.maxWidth = 900});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isWideSite(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
