import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage finto che fallisce in lettura.
class ThrowingReadStorage extends FlutterSecureStorage {
  const ThrowingReadStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: 'boom');
  }
}

/// Storage finto che fallisce in scrittura; il resto va allo storage di prova.
class ThrowingWriteStorage extends FlutterSecureStorage {
  const ThrowingWriteStorage();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: 'boom');
  }
}

/// Storage finto che fallisce nel cancellare; il resto va allo storage di
/// prova.
class ThrowingDeleteStorage extends FlutterSecureStorage {
  const ThrowingDeleteStorage();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw PlatformException(code: 'boom');
  }
}
