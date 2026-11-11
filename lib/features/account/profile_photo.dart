import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/sudhamrtam_app.dart';
import '../../services/profile_photo_api_client.dart';

/// Takes or chooses a photo, made small (at most 512 px) so it
/// uploads quickly; null if the customer cancelled. Tests replace it.
Future<Uint8List?> Function(ImageSource source) pickProfilePhoto =
    (source) async {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      return file?.readAsBytes();
    };

/// The signed-in customer's profile photo, saved to the account so it
/// follows them to a new phone and staff can recognise them. Kept in
/// memory; loaded on sign-in, cleared on sign-out.
class ProfilePhoto extends ChangeNotifier {
  ProfilePhoto({required this.api});

  final ProfilePhotoApiClient api;

  Uint8List? _bytes;
  bool _busy = false;
  StreamSubscription<Object?>? _authSubscription;

  /// Null when there is none (or signed out).
  Uint8List? get bytes => _bytes;
  bool get isBusy => _busy;
  bool get isSignedIn => api.isSignedIn;

  /// Loads the photo now and on every sign-in or sign-out.
  void attach(Stream<Object?> authChanges) {
    _authSubscription ??= authChanges.listen((_) => refresh());
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (!api.isSignedIn) {
      _bytes = null;
      notifyListeners();
      return;
    }
    try {
      _bytes = await api.fetch();
    } on ProfilePhotoException {
      // Offline: keep what is shown.
    }
    notifyListeners();
  }

  /// Saves [bytes] on the server first, then shows it.
  Future<void> save(Uint8List bytes) => _run(() async {
    await api.upload(bytes);
    _bytes = bytes;
  });

  Future<void> remove() => _run(() async {
    await api.remove();
    _bytes = null;
  });

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

/// The customer's photo in a circle; tap to take, choose or remove it.
/// Without a photo (or signed out) it shows the account icon.
class ProfilePhotoAvatar extends StatelessWidget {
  const ProfilePhotoAvatar({super.key, this.photo, this.radius = 44});

  /// Defaults to the app's [sudhamrtamProfilePhoto].
  final ProfilePhoto? photo;
  final double radius;

  static const _brandGreen = Color(0xFF82B440);

  Future<void> _change(BuildContext context, ProfilePhoto photo) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (photo.bytes != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'remove') {
        await photo.remove();
        say('Photo removed.');
        return;
      }
      final bytes = await pickProfilePhoto(
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (bytes == null) return;
      await photo.save(bytes);
      say('Photo saved.');
    } on ProfilePhotoException catch (e) {
      say(e.message);
    } catch (_) {
      say('Could not use this photo. Try another.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = this.photo ?? sudhamrtamProfilePhoto;
    if (photo == null) {
      return Icon(
        Icons.account_circle_outlined,
        size: radius * 1.75,
        color: _brandGreen,
      );
    }
    return ListenableBuilder(
      listenable: photo,
      builder: (context, _) {
        final bytes = photo.bytes;
        final avatar = CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFE5F0D7),
          backgroundImage: bytes == null ? null : MemoryImage(bytes),
          child: bytes == null
              ? Icon(Icons.person, size: radius * 1.1, color: _brandGreen)
              : null,
        );
        if (!photo.isSignedIn) return avatar;
        return Semantics(
          button: true,
          label: bytes == null ? 'Add a photo' : 'Change photo',
          child: InkWell(
            key: const Key('profilePhoto'),
            customBorder: const CircleBorder(),
            onTap: photo.isBusy ? null : () => _change(context, photo),
            child: Stack(
              children: [
                avatar,
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: radius * 0.3,
                    backgroundColor: _brandGreen,
                    child: photo.isBusy
                        ? SizedBox.square(
                            dimension: radius * 0.3,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.photo_camera,
                            size: radius * 0.32,
                            color: Colors.white,
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
