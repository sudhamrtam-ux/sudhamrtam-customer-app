import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';

import '../../app/sudhamrtam_app.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../services/support_api_client.dart';

const _brandGreen = Color(0xFF82B440);
const _darkGreen = Color(0xFF3F6B17);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "19 Nov, 7:45 PM".
String messageTime(DateTime time) {
  final t = time.toLocal();
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]}, $hour:$minute '
      '${t.hour < 12 ? 'AM' : 'PM'}';
}

/// The server's order status in words.
String supportOrderStatus(String status) => switch (status) {
  'delivered' => 'Delivered',
  'picked_up' => 'Picked up',
  'not_delivered' => 'Not delivered',
  'cancelled' => 'Cancelled',
  _ => 'Delivery pending',
};

/// The order shown at the top of a conversation before the server has
/// it (a new conversation, from My Orders).
class SupportOrderInfo {
  const SupportOrderInfo({
    required this.orderId,
    required this.title,
    required this.status,
    required this.lines,
    required this.total,
  });

  final String orderId;

  /// "Order SUD0000020".
  final String title;
  final String status;

  /// "2 × Curd (1 kg)".
  final List<String> lines;

  /// "₹240.00".
  final String total;
}

/// One Help & Support conversation: the order it is about at the top,
/// the messages, and a box to write. Opened with [queryId] for an
/// existing conversation, or with only [order] to start the order's
/// conversation (its first message creates it; when the order has one
/// already, the message goes there).
class SupportConversationScreen extends StatefulWidget {
  const SupportConversationScreen({
    super.key,
    this.queryId,
    this.order,
    this.api,
    this.pollEvery = const Duration(seconds: 30),
  }) : assert(queryId != null || order != null);

  final String? queryId;
  final SupportOrderInfo? order;

  /// Override for tests; defaults to the app's.
  final SupportApiClient? api;

  /// New replies are fetched this often while it is open (also when a
  /// "Sudhamrtam replied" notification arrives).
  final Duration pollEvery;

  @override
  State<SupportConversationScreen> createState() =>
      _SupportConversationScreenState();
}

class _SupportConversationScreenState extends State<SupportConversationScreen> {
  final _text = TextEditingController();
  String? _queryId;
  SupportConversation? _conversation;
  bool _loading = false;
  String? _error;
  bool _sending = false;
  String? _sendError;

  /// Kept until sent, so a retry is saved once.
  String _draftQueryId = newSupportQueryId();
  String _draftMessageId = newSupportQueryId();

  Timer? _poll;
  StreamSubscription<Object>? _replies;

  SupportApiClient? get _api => widget.api ?? sudhamrtamSupport;

  @override
  void initState() {
    super.initState();
    _queryId = widget.queryId;
    _load();
    _poll = Timer.periodic(widget.pollEvery, (_) => _load(quiet: true));
    _replies = sudhamrtamPush?.arrivals.listen((arrival) {
      if (arrival.tap.type == 'support_reply' && arrival.tap.id == _queryId) {
        _load(quiet: true);
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _replies?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final api = _api;
    final id = _queryId;
    if (api == null || id == null || _sending) return;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final conversation = await api.fetchConversation(id);
      if (mounted) setState(() => _conversation = conversation);
    } on SupportException catch (error) {
      if (mounted && !quiet) setState(() => _error = error.message);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final api = _api;
    final text = _text.text.trim();
    if (api == null || text.isEmpty) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      var id = _queryId;
      SupportConversation? conversation;
      if (id == null) {
        final order = widget.order!;
        try {
          final started = await api.send(
            _draftQueryId,
            topic: 'order',
            message: text,
            orderId: order.orderId,
          );
          id = started.id;
          conversation = await api.fetchConversation(id);
        } on SupportException catch (error) {
          // Started earlier (another phone, or a lost answer): write there.
          if (error.code != 'ORDER_HAS_QUERY' || error.queryId == null) {
            rethrow;
          }
          id = error.queryId!;
        }
      }
      conversation ??= await api.sendMessage(id, _draftMessageId, text);
      if (!mounted) return;
      setState(() {
        _queryId = id;
        _conversation = conversation;
        _draftQueryId = newSupportQueryId();
        _draftMessageId = newSupportQueryId();
        _text.clear();
      });
    } on SupportException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    final query = conversation?.query;
    final api = _api;
    return SiteScaffold(
      appBar: PageAppBar(
        title: Text(query?.ref == null ? 'Get help' : 'Help · ${query!.ref}'),
        actions: [
          if (_queryId != null)
            IconButton(
              tooltip: 'Check for replies',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _orderCard(conversation),
                if (query != null && query.isResolved) _resolvedNote(),
                Expanded(child: _messages(conversation)),
                if (api == null || !api.isSignedIn)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Sign in on the Account tab to write to us. You can '
                      'always call us from Help & Support.',
                    ),
                  )
                else
                  _composer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _orderCard(SupportConversation? conversation) {
    final server = conversation?.order;
    final start = widget.order;
    final String title;
    final String status;
    final List<String> lines;
    final String total;
    if (server != null) {
      title = 'Order ${server.orderRef}';
      status = supportOrderStatus(server.status);
      lines = server.items;
      total = '₹${(server.totalPaise / 100).toStringAsFixed(2)}';
    } else if (start != null) {
      title = start.title;
      status = start.status;
      lines = start.lines;
      total = start.total;
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      key: const Key('support-order'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD5D9D9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(status, style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines.take(4))
            Text(line, style: const TextStyle(fontSize: 13)),
          if (lines.length > 4)
            Text(
              '+ ${lines.length - 4} more',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          const SizedBox(height: 4),
          Text(
            'Total $total',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _resolvedNote() => Container(
    key: const Key('support-resolved'),
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFE3F1D3),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Row(
      children: [
        Icon(Icons.check_circle_outline, color: _darkGreen),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Resolved by Sudhamrtam. Still need help? Write below and '
            'it opens again.',
            style: TextStyle(color: _darkGreen),
          ),
        ),
      ],
    ),
  );

  Widget _messages(SupportConversation? conversation) {
    if (_error != null && conversation == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (conversation == null && _queryId != null) {
      return const Center(child: CircularProgressIndicator(color: _brandGreen));
    }
    final messages = conversation?.messages ?? const <SupportMessage>[];
    if (messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tell us what went wrong with this order. Sudhamrtam will '
            'reply here, and your phone will tell you.',
            key: Key('support-start-hint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    // Newest at the bottom, where the box is.
    return ListView.builder(
      key: const Key('support-messages'),
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: messages.length,
      itemBuilder: (context, i) => _bubble(messages[messages.length - 1 - i]),
    );
  }

  Widget _bubble(SupportMessage m) {
    final mine = !m.fromSudhamrtam;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          key: Key('support-message-${m.id}'),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFFE3F1D3) : Colors.white,
            border: mine ? null : Border.all(color: const Color(0xFFD5D9D9)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 2),
              bottomRight: Radius.circular(mine ? 2 : 14),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                const Text(
                  'Sudhamrtam',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: _darkGreen,
                  ),
                ),
              Text(m.body),
              const SizedBox(height: 2),
              Text(
                messageTime(m.createdAt),
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sendError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _sendError!,
                key: const Key('support-send-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('support-input'),
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _queryId == null
                        ? 'Describe the problem'
                        : 'Write a message',
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const Key('support-send'),
                tooltip: 'Send',
                style: IconButton.styleFrom(backgroundColor: _brandGreen),
                onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
