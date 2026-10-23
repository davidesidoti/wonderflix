import 'discord_ipc.dart';

/// Nel browser la Rich Presence è spenta (manca l'override in `main`), quindi
/// la pipe non si crea mai.
DiscordPipe createDiscordPipe() =>
    throw UnsupportedError('Discord non è disponibile nel browser');
