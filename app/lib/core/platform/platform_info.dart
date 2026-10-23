// Dati del sistema che su Windows vengono da `dart:io` e nel browser dallo
// user agent.
export 'platform_info_io.dart'
    if (dart.library.js_interop) 'platform_info_web.dart';
