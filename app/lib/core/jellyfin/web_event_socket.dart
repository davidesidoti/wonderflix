// WebSocket di Jellyfin: `dart:io` con header su Windows, `package:web` nel
// browser (dove gli header non si possono impostare).
export 'web_event_socket_io.dart'
    if (dart.library.js_interop) 'web_event_socket_web.dart';
