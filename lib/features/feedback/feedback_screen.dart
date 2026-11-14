import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import '../../services/feedback_api_client.dart';
import '../../core/widgets/page_app_bar.dart';

const _brandGreen = Color(0xFF82B440);
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "9 Nov 2026" in the phone's time zone.
String feedbackDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Account → Send Feedback: stars, a topic and an optional message,
/// then the customer's earlier feedback and Sudhamrtam's replies.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.api});

  /// Override for tests; defaults to the app's (null without a server).
  final FeedbackApiClient? api;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  int _rating = 0;
  String? _topic;
  bool _sending = false;
  String? _sendError;

  /// Kept until it is sent, so a retry never sends it twice.
  String _draftId = newFeedbackId();

  List<SentFeedback>? _mine;
  String? _loadError;

  FeedbackApiClient? get _api => widget.api ?? sudhamrtamFeedback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null || !api.isSignedIn) return;
    setState(() => _loadError = null);
    try {
      final mine = await api.fetchMine();
      if (mounted) setState(() => _mine = mine);
    } on FeedbackException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    }
  }

  Future<void> _send() async {
    final api = _api!;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await api.send(
        _draftId,
        rating: _rating,
        topic: _topic!,
        message: _message.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _draftId = newFeedbackId();
        _rating = 0;
        _topic = null;
        _message.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you! Your feedback was sent.')),
      );
      await _load();
    } on FeedbackException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    return Scaffold(
      appBar: PageAppBar(title: const Text('Send Feedback')),
      body: SafeArea(
        child: api == null
            ? const _Notice('Feedback needs a connection to Sudhamrtam.')
            : !api.isSignedIn
            ? const _Notice(
                'Please sign in on the Account tab to send feedback, so we '
                'can get back to you.',
              )
            : RefreshIndicator(
                color: _brandGreen,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _form(context),
                    const SizedBox(height: 28),
                    _history(context),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _rating > 0 && _topic != null && !_sending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How are we doing?',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text('Your feedback goes straight to the Sudhamrtam team.'),
        const SizedBox(height: 16),
        Row(
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                key: Key('feedback-star-$star'),
                tooltip: star == 1 ? '1 star' : '$star stars',
                iconSize: 36,
                onPressed: _sending
                    ? null
                    : () => setState(() => _rating = star),
                icon: Icon(
                  star <= _rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: star <= _rating
                      ? Colors.amber.shade700
                      : Colors.black38,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text('What is it about?', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final MapEntry(key: id, value: label)
                in feedbackTopics.entries)
              ChoiceChip(
                label: Text(label),
                selected: _topic == id,
                selectedColor: _brandGreen.withValues(alpha: 0.25),
                onSelected: _sending
                    ? null
                    : (_) => setState(() => _topic = id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('feedback-message'),
          controller: _message,
          enabled: !_sending,
          maxLength: 1000,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Tell us more (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_sendError != null) ...[
          Text(_sendError!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brandGreen),
            onPressed: ready ? _send : null,
            child: _sending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Send Feedback'),
          ),
        ),
        if (!ready && !_sending)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Choose the stars and a topic to send.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _history(BuildContext context) {
    final theme = Theme.of(context);
    final mine = _mine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your earlier feedback', style: theme.textTheme.titleMedium),
        const Divider(),
        if (mine == null && _loadError != null)
          Row(
            children: [
              Expanded(child: Text(_loadError!)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          )
        else if (mine == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: _brandGreen)),
          )
        else if (mine.isEmpty)
          const Text('Nothing sent yet.')
        else
          for (final f in mine) _SentTile(feedback: f),
      ],
    );
  }
}

class _SentTile extends StatelessWidget {
  const _SentTile({required this.feedback});

  final SentFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = feedback;
    final handled = f.handledAt != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${'★' * f.rating}${'☆' * (5 - f.rating)}  ·  '
            '${feedbackTopics[f.topic] ?? 'Other'}  ·  ${feedbackDate(f.createdAt)}',
            semanticsLabel:
                '${f.rating} of 5 stars, ${feedbackTopics[f.topic] ?? 'Other'}, '
                '${feedbackDate(f.createdAt)}',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black87),
          ),
          if (f.message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(f.message),
          ],
          const SizedBox(height: 4),
          Text(
            handled ? 'Seen by Sudhamrtam' : 'Received',
            style: theme.textTheme.bodySmall?.copyWith(
              color: handled ? _brandGreen : Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (f.handledNote != null)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _brandGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Sudhamrtam: ${f.handledNote}'),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
