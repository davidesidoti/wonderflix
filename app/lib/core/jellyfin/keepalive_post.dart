// POST che sopravvive alla chiusura della scheda (solo nel browser).
export 'keepalive_post_io.dart'
    if (dart.library.js_interop) 'keepalive_post_web.dart';
