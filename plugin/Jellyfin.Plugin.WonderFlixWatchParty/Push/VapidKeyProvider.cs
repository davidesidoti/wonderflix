using Jellyfin.Plugin.WonderFlixWatchParty.Configuration;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>
/// Le chiavi VAPID del server (spec V): si generano al primo uso e si salvano
/// nella configurazione del plugin, poi si riusano. Cambiarle invaliderebbe
/// tutte le iscrizioni, quindi non si rigenerano se ci sono già.
/// </summary>
/// <param name="config">La configurazione di adesso, riletta a ogni uso (la Dashboard ne sostituisce l'oggetto); null senza plugin.</param>
/// <param name="save">Salva la configurazione.</param>
public sealed class VapidKeyProvider(Func<PluginConfiguration?> config, Action save)
{
    private readonly Lock _lock = new();

    // Senza plugin (nei test) le chiavi vivono solo qui.
    private VapidKeys? _inMemory;

    public VapidKeys Get()
    {
        lock (_lock)
        {
            var current = config();
            if (current is null)
            {
                return _inMemory ??= VapidSigner.Generate();
            }

            if (current.VapidPublicKey.Length == 0 || current.VapidPrivateKey.Length == 0)
            {
                var keys = VapidSigner.Generate();
                current.VapidPublicKey = keys.PublicKey;
                current.VapidPrivateKey = keys.PrivateKey;
                save();
            }

            return new VapidKeys(current.VapidPublicKey, current.VapidPrivateKey);
        }
    }
}
