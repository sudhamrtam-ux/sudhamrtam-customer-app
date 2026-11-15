import 'package:flutter/material.dart';

/// One piece of a product description, as it is shown.
sealed class DescriptionBlock {
  const DescriptionBlock();
}

/// A paragraph of plain text.
class DescriptionParagraph extends DescriptionBlock {
  const DescriptionParagraph(this.text);
  final String text;
}

/// A short heading ("Why Sudhamrtam Cow Ghee?").
class DescriptionHeading extends DescriptionBlock {
  const DescriptionHeading(this.text);
  final String text;
}

/// A point in a list, with an optional bold label ("Pure & natural").
class DescriptionPoint extends DescriptionBlock {
  const DescriptionPoint(this.text, {this.label});
  final String? label;
  final String text;
}

final _labelled = RegExp(r'^([^:.]{3,50}):\s*(.+)$');
final _numbered = RegExp(r'^\d+\.\s+');

/// Splits a description (one line per paragraph, heading or point, as
/// the server sends it) into blocks:
/// - "• text" and "Label: text" lines are points;
/// - short lines without a full stop, and numbered titles, are headings;
/// - everything else is a paragraph.
List<DescriptionBlock> parseDescription(String description) {
  final blocks = <DescriptionBlock>[];
  for (final raw in description.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final bullet = line.startsWith('• ') || line.startsWith('•');
    final body = bullet ? line.substring(1).trim() : line;
    final labelled = _labelled.firstMatch(body);
    if (labelled != null && (bullet || body.length > 60)) {
      blocks.add(
        DescriptionPoint(labelled.group(2)!, label: labelled.group(1)!.trim()),
      );
    } else if (bullet) {
      blocks.add(DescriptionPoint(body));
    } else if (_numbered.hasMatch(line) ||
        (line.length <= 60 &&
            !line.endsWith('.') &&
            !line.endsWith('!') &&
            !line.contains('. '))) {
      blocks.add(DescriptionHeading(line.replaceFirst(_numbered, '')));
    } else {
      blocks.add(DescriptionParagraph(line));
    }
  }
  return blocks;
}

/// "About this product": the first paragraph, three lines at most,
/// with Read more to open the whole description (headings, points and
/// paragraphs, properly spaced) and Show less to close it.
class ProductDescription extends StatefulWidget {
  const ProductDescription({super.key, required this.description});

  final String description;

  @override
  State<ProductDescription> createState() => _ProductDescriptionState();
}

class _ProductDescriptionState extends State<ProductDescription> {
  bool _open = false;

  static const _green = Color(0xFF2E5A1C);
  static const _fresh = Color(0xFF82B440);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = parseDescription(widget.description);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final body = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 15,
      height: 1.55,
      color: const Color(0xFF33402B),
    );
    final first = blocks.firstWhere(
      (b) => b is DescriptionParagraph,
      orElse: () => blocks.first,
    );
    final summary = switch (first) {
      DescriptionParagraph(:final text) => text,
      DescriptionHeading(:final text) => text,
      DescriptionPoint(:final text) => text,
    };
    final more = blocks.length > 1 || summary.length > 160;

    return Container(
      key: const Key('productDescription'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1EBD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.eco_outlined, color: _fresh, size: 20),
              const SizedBox(width: 8),
              Text(
                'About this product',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final block in blocks)
                        _BlockView(block: block, body: body),
                    ],
                  )
                : Text(
                    summary,
                    style: body,
                    textAlign: TextAlign.justify,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          if (more)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('productDescriptionToggle'),
                style: TextButton.styleFrom(
                  foregroundColor: _green,
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
                label: Text(_open ? 'Show less' : 'Read more'),
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.body});

  final DescriptionBlock block;
  final TextStyle body;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      DescriptionParagraph(:final text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: body, textAlign: TextAlign.justify),
      ),
      DescriptionHeading(:final text) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(
          text,
          style: body.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: const Color(0xFF2E5A1C),
          ),
        ),
      ),
      DescriptionPoint(:final label, :final text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 3, right: 10),
              child: Icon(
                Icons.check_circle,
                size: 16,
                color: Color(0xFF82B440),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: body,
                  children: [
                    if (label != null)
                      TextSpan(
                        text: '$label: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    TextSpan(text: text),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    };
  }
}
