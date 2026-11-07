import '../../core/platform/platform_info.dart';
import 'player_window.dart';
import 'tv_player_window.dart';

PlayerWindow createPlayerWindow() =>
    isAndroidTv ? TvPlayerWindow() : WindowManagerPlayerWindow();
