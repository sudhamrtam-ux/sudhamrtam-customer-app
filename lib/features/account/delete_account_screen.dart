import 'package:flutter/material.dart';

import '../../core/widgets/site_layout.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/company.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../services/account_deletion_client.dart';

/// Account → Delete my account (owner decisions 2026-11-15; required
/// by Apple and Google). Refused while money is owed or a delivery is
/// still due; otherwise deleted at once after typing DELETE.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    required this.client,
    required this.signOut,
  });

  final AccountDeletionClient client;

  /// Signs out on this phone (clears the profile, addresses and plans
  /// kept here) after the account is deleted.
  final Future<void> Function() signOut;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _red = Color(0xFFC62828);

  final _confirm = TextEditingController();
  DeletionCheck? _check;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final check = await widget.client.check();
      if (mounted) setState(() => _check = check);
    } on AccountDeletionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.client.delete();
      await widget.signOut();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.notSettled) await _load();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    return SiteScaffold(
      appBar: PageAppBar(title: const Text('Delete my account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (check == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (check == null)
              _Message(
                text: _error!,
                action: TextButton(
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              )
            else if (!check.canDelete)
              _blocked(check)
            else
              _form(),
          ],
        ),
      ),
    );
  }

  Widget _blocked(DeletionCheck check) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.info_outline, size: 40, color: Color(0xFF9A5B00)),
      const SizedBox(height: 12),
      Text(
        check.message ?? 'Your account cannot be deleted right now.',
        key: const Key('deleteBlocked'),
        style: const TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        key: const Key('deleteCallUs'),
        onPressed: () => launchUrl(
          Uri(scheme: 'tel', path: sudhamrtamSupportPhoneDial),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.call),
        label: const Text('Call $sudhamrtamSupportPhone'),
      ),
    ],
  );

  Widget _form() {
    final ready = _confirm.text.trim() == 'DELETE' && !_deleting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'This deletes your Sudhamrtam account at once. It cannot be undone.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        const _Point(
          icon: Icons.delete_outline,
          text:
              'Erased: your name, email, photo, addresses, milk plans, '
              'queries and feedback. You are signed out everywhere.',
        ),
        const _Point(
          icon: Icons.receipt_long_outlined,
          text:
              'Kept, as the law requires for tax records: your bills, '
              'orders and payments.',
        ),
        const _Point(
          icon: Icons.phone_iphone,
          text:
              'You can sign up again later with the same number, as a new '
              'customer.',
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('deleteConfirm'),
          controller: _confirm,
          enabled: !_deleting,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Type DELETE to confirm',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: _red)),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('deleteAccount'),
            style: FilledButton.styleFrom(
              backgroundColor: _red,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: ready ? _delete : null,
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_forever),
            label: Text(_deleting ? 'Deleting…' : 'Delete my account'),
          ),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.black54),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(text, textAlign: TextAlign.center),
      ?action,
    ],
  );
}
