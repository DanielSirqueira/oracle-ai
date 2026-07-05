import 'dart:async';
import 'dart:io';

/// Enforces a single running instance of a desktop app: a second launch hands
/// off to the first (focusing its window) and exits, the way VS Code / Claude
/// Code behave.
///
/// Mechanism (dependency-free): the first instance binds a fixed loopback port
/// and becomes the *primary*. A later launch fails to bind, connects to the
/// primary — which triggers [onActivate] (show + focus its window) — and then
/// bows out. A short **magic handshake** guards against a stranger holding the
/// port: if whoever owns it does not speak our protocol, we assume it is not
/// us and let this instance run rather than refuse to start.
abstract final class SingleInstance {
  /// Tries to become the primary instance on [port] (a fixed, app-unique
  /// loopback port). [magic] identifies the app so an unrelated process on the
  /// same port is not mistaken for a running instance.
  ///
  /// Returns `true` when this process is the primary and should keep running.
  /// Returns `false` when another instance is already up (it has been asked to
  /// activate) — the caller MUST exit immediately.
  ///
  /// [onActivate] runs on the primary whenever another launch pings it.
  static Future<bool> ensureSingle(
    int port,
    String magic, {
    FutureOr<void> Function()? onActivate,
  }) async {
    final banner = '$magic\n';
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      server.listen((socket) {
        // Announce who we are, then wake the window.
        try {
          socket.write(banner);
        } catch (_) {/* client may have already gone */}
        socket.destroy();
        onActivate?.call();
      });
      return true;
    } on SocketException {
      // Port busy — is it really our other instance?
      return !await _pingIsOurs(port, magic);
    }
  }

  /// Connects to [port] and checks the peer announces our [magic]. True only
  /// when a genuine sibling instance answered.
  static Future<bool> _pingIsOurs(int port, String magic) async {
    Socket? socket;
    try {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, port,
          timeout: const Duration(seconds: 2));
      final line = await socket
          .cast<List<int>>()
          .transform(const SystemEncoding().decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      return line.trimRight() == magic;
    } catch (_) {
      // Nobody answered our protocol → treat the port as a stranger's and let
      // this instance run (better than never starting).
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
