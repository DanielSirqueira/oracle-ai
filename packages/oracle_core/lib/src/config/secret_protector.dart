import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Encrypts secrets at rest using the OS-native key store, so the database
/// password and LLM API key never sit in plaintext on disk.
///
/// **Windows — DPAPI (`CryptProtectData`, CurrentUser scope).** This is the
/// Microsoft-recommended way to protect application secrets on the desktop: the
/// OS derives the key from the logged-in user's credentials, so there is no
/// master key for us to generate, store or rotate, and only the *same Windows
/// user on the same machine* can decrypt. It defends exactly against the threats
/// that matter here — a leaked/synced `.env`, offline exfiltration, or another
/// user on the box reading the file. (It does not protect against code already
/// running as that user; that is DPAPI's documented hard limit.)
///
/// Crucially, DPAPI works from **both** processes that need the secret: the
/// Flutter installer that writes it and the pure-Dart `oracle_ai` CLI/MCP that
/// reads it — they run as the same user, so no shared key material is needed.
///
/// **Other platforms.** DPAPI is Windows-only, so [protect] is a no-op there
/// (the value stays as-is) and [unprotect] passes plaintext through. macOS
/// (Keychain) / Linux (Secret Service) can be layered in later behind the same
/// API without touching callers.
///
/// Protected values are stored as `enc:v1:<base64>` — [isProtected] detects the
/// marker so [unprotect] is safe to call on any value (encrypted or not).
abstract final class SecretProtector {
  static const _marker = 'enc:v1:';

  /// App-specific secondary entropy mixed into the DPAPI blob. Binds the
  /// ciphertext to Oracle AI: another app running as the same user cannot
  /// decrypt it without knowing this value.
  static const _entropy = 'OracleAI::secrets::v1';

  /// `CRYPTPROTECT_UI_FORBIDDEN` — never pop UI (we run headless/CLI).
  static const _uiForbidden = 0x1;

  /// True when at-rest encryption is available on this platform (Windows only).
  static bool get available => Platform.isWindows;

  /// True when [value] is an encrypted token this class produced.
  static bool isProtected(String value) => value.startsWith(_marker);

  /// Encrypts [plaintext] to an `enc:v1:<base64>` token. Returns the input
  /// unchanged when encryption is unavailable (non-Windows), when the value is
  /// empty, or already protected — so it is safe to call unconditionally.
  ///
  /// Never throws: a crypto hiccup must not block an install, so it falls back
  /// to the plaintext value.
  static String protect(String plaintext) {
    if (!available || plaintext.isEmpty || isProtected(plaintext)) {
      return plaintext;
    }
    try {
      final out = _transform(utf8.encode(plaintext), encrypt: true);
      return '$_marker${base64.encode(out)}';
    } catch (_) {
      return plaintext;
    }
  }

  /// Decrypts an `enc:v1:` token back to plaintext. Any non-protected value is
  /// returned verbatim, so this is the single read path for every secret.
  static String unprotect(String value) {
    if (!isProtected(value) || !available) return value;
    try {
      final bytes = base64.decode(value.substring(_marker.length));
      return utf8.decode(_transform(bytes, encrypt: false));
    } catch (_) {
      return value;
    }
  }

  /// Runs one DPAPI call (protect or unprotect) over [input], copying the
  /// result out of the DPAPI-owned buffer before freeing it. All scratch
  /// memory is released via the [Arena]; the output buffer, allocated by DPAPI
  /// with `LocalAlloc`, is freed with `LocalFree`.
  static Uint8List _transform(List<int> input, {required bool encrypt}) {
    return using((arena) {
      Pointer<_DataBlob> blobFor(List<int> bytes) {
        final buf = arena<Uint8>(bytes.isEmpty ? 1 : bytes.length);
        buf.asTypedList(bytes.length).setAll(0, bytes);
        return arena<_DataBlob>()
          ..ref.cbData = bytes.length
          ..ref.pbData = buf;
      }

      final inBlob = blobFor(input);
      final entBlob = blobFor(utf8.encode(_entropy));
      final outBlob = arena<_DataBlob>();

      final fn = encrypt ? _protect : _unprotect;
      final ok = fn(inBlob, nullptr, entBlob, nullptr, nullptr, _uiForbidden, outBlob);
      if (ok == 0) {
        throw StateError('DPAPI ${encrypt ? 'protect' : 'unprotect'} failed');
      }
      try {
        return Uint8List.fromList(
            outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
      } finally {
        _localFree(outBlob.ref.pbData.cast());
      }
    });
  }

  // ── native bindings (resolved lazily, Windows only) ──

  static final DynamicLibrary _crypt32 = DynamicLibrary.open('Crypt32.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('Kernel32.dll');

  static final _CryptProtectDart _protect = _crypt32
      .lookupFunction<_CryptProtectC, _CryptProtectDart>('CryptProtectData');
  static final _CryptProtectDart _unprotect = _crypt32
      .lookupFunction<_CryptProtectC, _CryptProtectDart>('CryptUnprotectData');
  static final _LocalFreeDart _localFree = _kernel32
      .lookupFunction<_LocalFreeC, _LocalFreeDart>('LocalFree');
}

/// Win32 `DATA_BLOB { DWORD cbData; BYTE* pbData; }`.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptProtectC = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);
typedef _CryptProtectDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Utf16> szDataDescr,
  Pointer<_DataBlob> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeC = Pointer<Void> Function(Pointer<Void> hMem);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);
