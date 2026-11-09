import 'package:flutter/material.dart';

import '../../app/sudhamrtam_app.dart';
import 'message_inbox.dart';

const _brandGreen = Color(0xFF82B440);
const _paleGreen = Color(0xFFF5F8F0);
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

/// "9 Nov 2026, 10:30 AM" in the phone's time zone.
String messageTime(DateTime time) {
  final t = time.toLocal();
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final minute = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year}, '
      '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// The bell at the top of the app, with the unread count. Hidden
/// when the app has no server.
class MessagesBell extends StatefulWidget {
  const MessagesBell({super.key, this.inbox});

  /// Override for tests; defaults to the app's.
  final MessageInbox? inbox;

  @override
  State<MessagesBell> createState() => _MessagesBellState();
}

class _MessagesBellState extends State<MessagesBell>
    with WidgetsBindingObserver {
  MessageInbox? get _inbox => widget.inbox ?? sudhamrtamMessages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _inbox?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = _inbox;
    if (inbox == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final count = inbox.unreadCount;
        return IconButton(
          key: const Key('messages-bell'),
          tooltip: count == 0 ? 'Messages' : 'Messages, $count unread',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MessagesScreen(inbox: inbox),
            ),
          ),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 9 ? '9+' : '$count'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

/// Messages from Sudhamrtam, newest first. Opening it marks them read.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.inbox});

  final MessageInbox inbox;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  /// Unread when the screen opened, so they stay marked as new here.
  Set<String> _newIds = const {};

  @override
  void initState() {
    super.initState();
    // After the first frame: refreshing notifies the bell and this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  Future<void> _open() async {
    final inbox = widget.inbox;
    _remember();
    await inbox.refresh();
    if (!mounted) return;
    _remember();
    await inbox.markAllRead();
  }

  void _remember() {
    final unread = {
      for (final m in widget.inbox.messages ?? const [])
        if (m.unread) m.id,
    };
    if (unread.isNotEmpty) setState(() => _newIds = {..._newIds, ...unread});
  }

  @override
  Widget build(BuildContext context) {
    final inbox = widget.inbox;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: inbox,
          builder: (context, _) {
            if (!inbox.isSignedIn) {
              return const _Notice(
                'Please sign in on the Account tab to see messages from '
                'Sudhamrtam.',
              );
            }
            final messages = inbox.messages;
            if (messages == null) {
              return inbox.error == null
                  ? const Center(
                      child: CircularProgressIndicator(color: _brandGreen),
                    )
                  : _Notice(inbox.error!, onRetry: inbox.refresh);
            }
            return RefreshIndicator(
              color: _brandGreen,
              onRefresh: _open,
              child: messages.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No messages yet.')),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final m = messages[i];
                        final isNew = _newIds.contains(m.id);
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isNew ? _paleGreen : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isNew
                                  ? _brandGreen
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isNew) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _brandGreen,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      m.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(m.body),
                              const SizedBox(height: 8),
                              Text(
                                messageTime(m.sentAt),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.onRetry});

  final String text;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
