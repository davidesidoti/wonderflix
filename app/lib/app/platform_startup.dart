// Avvio specifico della piattaforma: su Windows finestra, libmpv, SMTC,
// Discord e log su file; nel browser niente di tutto questo (spec 1b §4.6).
export 'platform_startup_io.dart'
    if (dart.library.js_interop) 'platform_startup_web.dart';
