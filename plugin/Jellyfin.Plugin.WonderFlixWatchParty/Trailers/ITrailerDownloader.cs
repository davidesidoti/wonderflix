namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>Esito di un download di trailer.</summary>
public enum TrailerDownloadOutcome
{
    Ok,

    /// <summary>Video vietato, tolto, troppo lungo o troppo grande: riprovare non serve.</summary>
    Unavailable,

    /// <summary>Rete, processo o tempo scaduto: può andare meglio più tardi.</summary>
    Failed,
}

public interface ITrailerDownloader
{
    /// <summary>Scarica il video YouTube in <paramref name="targetMp4Path"/>, che compare solo a download finito.</summary>
    Task<TrailerDownloadOutcome> DownloadAsync(string videoId, string targetMp4Path, CancellationToken cancellationToken);
}
