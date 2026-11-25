import 'package:flutter/material.dart';

import '../../services/reminder_api_client.dart';

/// "Evening reminder · 8 PM" with a switch (owner decision 2026-11-25):
/// a phone notification about tomorrow's deliveries before the 9 PM
/// cut-off. Hidden until the server answers.
class EveningReminderTile extends StatefulWidget {
  const EveningReminderTile({super.key, required this.client});

  final ReminderApiClient client;

  @override
  State<EveningReminderTile> createState() => _EveningReminderTileState();
}

class _EveningReminderTileState extends State<EveningReminderTile> {
  bool? _on;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    widget.client.evening().then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  Future<void> _set(bool on) async {
    setState(() {
      _saving = true;
      _on = on;
    });
    final saved = await widget.client.setEvening(on);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _on = saved ?? !on;
    });
    if (saved == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Not saved. Please check your connection.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    return SwitchListTile(
      key: const Key('eveningReminder'),
      secondary: const Icon(Icons.notifications_active_outlined),
      title: const Text('Evening reminder'),
      subtitle: const Text(
        "At 8 PM: tomorrow's deliveries, so you can change or skip "
        'before the 9 PM cut-off.',
      ),
      value: on,
      onChanged: _saving ? null : _set,
    );
  }
}
