import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/message_api_client.dart';

/// The customer's messages from Sudhamrtam and the unread count for
/// the bell. Kept in memory only; refreshed on sign-in, when the app
/// comes back to the front, and every [pollEvery] while it is open.
class MessageInbox extends ChangeNotifier {
  MessageInbox({
    required this.api,
    this.pollEvery = const Duration(minutes: 15),
  });

  final MessageApiClient api;
  final Duration pollEvery;

  List<CustomerMessage>? _messages;
  int _unreadCount = 0;
  String? _error;
  bool _loading = false;
  StreamSubscription<Object?>? _authSubscription;
  Timer? _timer;

  /// Null until loaded (and after sign-out).
  List<CustomerMessage>? get messages => _messages;
  int get unreadCount => _unreadCount;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isSignedIn => api.isSignedIn;

  /// Starts refreshing; [authChanges] fires on sign-in and sign-out.
  void attach(Stream<Object?> authChanges) {
    _authSubscription ??= authChanges.listen((_) => refresh());
    _timer ??= Timer.periodic(pollEvery, (_) => refresh());
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!api.isSignedIn) {
      _clear();
      return;
    }
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final result = await api.fetchMessages();
      _messages = result.messages;
      _unreadCount = result.unreadCount;
      _error = null;
    } on MessageException catch (e) {
      if (e.unauthorized) {
        _messages = null;
        _unreadCount = 0;
      }
      // Offline: keep what is shown.
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The customer has seen the list: everything shown is read.
  Future<void> markAllRead() async {
    final messages = _messages;
    if (messages == null || messages.isEmpty || _unreadCount == 0) return;
    final shown = _unreadCount;
    _messages = [for (final m in messages) m.asRead()];
    _unreadCount = 0;
    notifyListeners();
    try {
      _unreadCount = await api.markRead(messages.first.sentAtText);
    } on MessageException {
      // Not saved: they count as unread again next time.
      _unreadCount = shown;
      _messages = messages;
    }
    notifyListeners();
  }

  void _clear() {
    final changed = _messages != null || _unreadCount != 0 || _error != null;
    _messages = null;
    _unreadCount = 0;
    _error = null;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
