// Prove dei codec del browser; su Windows non si usano.
export 'browser_probe_io.dart'
    if (dart.library.js_interop) 'browser_probe_web.dart';
