import 'browser_profile.dart';

/// Su Windows il profilo è quello di mpv: le prove del browser non servono.
BrowserCapabilities probeBrowser() =>
    throw UnsupportedError('probeBrowser solo nel browser');
