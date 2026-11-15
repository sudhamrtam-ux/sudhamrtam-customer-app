import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/sudhamrtam_app.dart';
import '../../core/company.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../services/support_api_client.dart';
import '../feedback/feedback_screen.dart' show feedbackDate;

const _brandGreen = Color(0xFF82B440);

/// Opens the phone's dialler or email app; false when it cannot.
typedef LinkOpener = Future<bool> Function(Uri uri);

Future<bool> _openLink(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Account → Help & Support (owner decision 2026-11-15): call or write
/// to Sudhamrtam, or raise a query. A query reaches the owner and
/// managers in the staff app and by email; their reply shows here.
class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key, this.api, this.openLink});

  /// Overrides for tests; default to the app's (null without a server).
  final SupportApiClient? api;
  final LinkOpener? openLink;

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _message = TextEditingController();
  String? _topic;
  bool _sending = false;
  String? _sendError;

  /// Kept until it is sent, so a retry never sends it twice.
  String _draftId = newSupportQueryId();

  List<SupportQuery>? _mine;
  String? _loadError;

  SupportApiClient? get _api => widget.api ?? sudhamrtamSupport;

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
    } on SupportException catch (error) {
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
      final sent = await api.send(
        _draftId,
        topic: _topic!,
        message: _message.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _draftId = newSupportQueryId();
        _topic = null;
        _message.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent.ref == null
                ? 'Your query was sent. We will get back to you soon.'
                : 'Your query ${sent.ref} was sent. We will get back to '
                      'you soon; quote ${sent.ref} if you call us.',
          ),
        ),
      );
      await _load();
    } on SupportException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _open(Uri uri, String copyText) async {
    final opened = await (widget.openLink ?? _openLink)(uri);
    if (opened || !mounted) return;
    // No dialler or email app: copy it instead.
    await Clipboard.setData(ClipboardData(text: copyText));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Copied $copyText')));
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    return Scaffold(
      appBar: PageAppBar(title: const Text('Help & Support')),
      body: SafeArea(
        child: RefreshIndicator(
          color: _brandGreen,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _contactCard(context),
              const SizedBox(height: 24),
              if (api == null)
                const _Notice(
                  'Raising a query needs a connection to Sudhamrtam. '
                  'Please call or email us.',
                )
              else if (!api.isSignedIn)
                const _Notice(
                  'Sign in on the Account tab to raise a query, so we know '
                  'who to answer. You can always call or email us.',
                )
              else ...[
                _form(context),
                const SizedBox(height: 28),
                _history(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('supportContact'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF7FAF2), Color(0xFFEDF5E1)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE8CC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact Sudhamrtam',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'We are happy to help with orders, milk plans, bills and '
            'deliveries.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.call_outlined, color: _brandGreen),
            title: const SelectableText(sudhamrtamSupportPhone),
            subtitle: const Text('Phone'),
            trailing: FilledButton.tonalIcon(
              key: const Key('supportCall'),
              onPressed: () => _open(
                Uri(scheme: 'tel', path: sudhamrtamSupportPhoneDial),
                sudhamrtamSupportPhone,
              ),
              icon: const Icon(Icons.call, size: 18),
              label: const Text('Call'),
            ),
          ),
          for (final email in sudhamrtamSupportEmails)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined, color: _brandGreen),
              title: SelectableText(email),
              subtitle: const Text('Email'),
              trailing: FilledButton.tonalIcon(
                key: Key('supportEmail-$email'),
                onPressed: () => _open(
                  Uri(
                    scheme: 'mailto',
                    path: email,
                    query: 'subject=Sudhamrtam%20query',
                  ),
                  email,
                ),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Write'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final ready =
        _topic != null && _message.text.trim().isNotEmpty && !_sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Raise a query',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'It reaches our team straight away; the answer shows below.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in supportTopics.entries)
              ChoiceChip(
                key: Key('supportTopic-${entry.key}'),
                label: Text(entry.value),
                selected: _topic == entry.key,
                selectedColor: const Color(0xFFE5F0D7),
                onSelected: _sending
                    ? null
                    : (_) => setState(() => _topic = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('supportMessage'),
          controller: _message,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          enabled: !_sending,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Tell us what happened, e.g. the date and the order.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_sendError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _sendError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('supportSend'),
            onPressed: ready ? _send : null,
            style: FilledButton.styleFrom(
              backgroundColor: _brandGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(_sending ? 'Sending…' : 'Send query'),
          ),
        ),
        if (!ready && !_sending)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Choose a topic and write your query to send.',
              style: TextStyle(color: Colors.black54, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _history(BuildContext context) {
    final mine = _mine;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your queries',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadError != null)
          Text(_loadError!, style: TextStyle(color: theme.colorScheme.error))
        else if (mine == null)
          const Center(child: CircularProgressIndicator())
        else if (mine.isEmpty)
          const Text('No queries yet.', style: TextStyle(color: Colors.black54))
        else
          for (final q in mine)
            Card(
              key: Key('supportQuery-${q.id}'),
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${supportTopics[q.topic] ?? 'Query'}  ·  '
                            '${feedbackDate(q.createdAt)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _StatusPill(answered: q.handledAt != null),
                      ],
                    ),
                    if (q.ref != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SelectableText(
                          'Query no. ${q.ref}',
                          key: Key('supportRef-${q.id}'),
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(q.message),
                    if (q.reply != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F7E8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Sudhamrtam: ${q.reply}',
                          style: const TextStyle(color: Color(0xFF3F6B17)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.answered});

  final bool answered;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: answered ? const Color(0xFFE3F1D3) : const Color(0xFFFFF1D6),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      answered ? 'Answered' : 'Open',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: answered ? const Color(0xFF3F6B17) : const Color(0xFF9A5B00),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8F0),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text),
  );
}
