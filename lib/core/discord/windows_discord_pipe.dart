import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'discord_ipc.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _createFile = _kernel32.lookupFunction<
    Pointer<Void> Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>,
        Uint32, Uint32, Pointer<Void>),
    Pointer<Void> Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
        Pointer<Void>)>('CreateFileW');

final _peekNamedPipe = _kernel32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Pointer<Uint32>,
        Pointer<Uint32>, Pointer<Uint32>),
    int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint32>,
        Pointer<Uint32>, Pointer<Uint32>)>('PeekNamedPipe');

final _readFile = _kernel32.lookupFunction<
    Int32 Function(
        Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<Void>)>('ReadFile');

final _writeFile = _kernel32.lookupFunction<
    Int32 Function(
        Pointer<Void>, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<Void>)>('WriteFile');

final _closeHandle = _kernel32.lookupFunction<Int32 Function(Pointer<Void>),
    int Function(Pointer<Void>)>('CloseHandle');

const _genericReadWrite = 0x80000000 | 0x40000000;
const _openExisting = 3;
const _invalidHandle = -1;

/// [DiscordPipe] sulla named pipe di Windows `\\.\pipe\discord-ipc-N`.
class WindowsDiscordPipe implements DiscordPipe {
  Pointer<Void>? _handle;

  @override
  bool open() {
    close();
    for (var i = 0; i < 10; i++) {
      final path = '\\\\.\\pipe\\discord-ipc-$i'.toNativeUtf16();
      try {
        final handle = _createFile(path, _genericReadWrite, 0, nullptr,
            _openExisting, 0, nullptr);
        if (handle.address != _invalidHandle && handle.address != 0) {
          _handle = handle;
          return true;
        }
      } finally {
        malloc.free(path);
      }
    }
    return false;
  }

  Pointer<Void> _requireHandle() =>
      _handle ?? (throw const DiscordPipeException('pipe non aperta'));

  @override
  void write(Uint8List bytes) {
    final handle = _requireHandle();
    final buffer = malloc<Uint8>(bytes.length);
    final written = malloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final ok = _writeFile(handle, buffer, bytes.length, written, nullptr);
      if (ok == 0 || written.value != bytes.length) {
        throw const DiscordPipeException('scrittura non riuscita');
      }
    } finally {
      malloc.free(buffer);
      malloc.free(written);
    }
  }

  @override
  Uint8List read() {
    final handle = _requireHandle();
    final available = malloc<Uint32>();
    try {
      final ok =
          _peekNamedPipe(handle, nullptr, 0, nullptr, available, nullptr);
      if (ok == 0) throw const DiscordPipeException('pipe chiusa');
      final count = available.value;
      if (count == 0) return Uint8List(0);
      final buffer = malloc<Uint8>(count);
      final read = malloc<Uint32>();
      try {
        if (_readFile(handle, buffer, count, read, nullptr) == 0) {
          throw const DiscordPipeException('lettura non riuscita');
        }
        return Uint8List.fromList(buffer.asTypedList(read.value));
      } finally {
        malloc.free(buffer);
        malloc.free(read);
      }
    } finally {
      malloc.free(available);
    }
  }

  @override
  void close() {
    final handle = _handle;
    _handle = null;
    if (handle != null) _closeHandle(handle);
  }
}
