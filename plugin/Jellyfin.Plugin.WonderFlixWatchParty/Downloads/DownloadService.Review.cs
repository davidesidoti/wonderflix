using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Downloads;

/// <summary>
/// "Da ripassare" (spec T §6): i film e le stagioni già scaricati sotto l'obiettivo del profilo, rifatto una volta al giorno;
/// e l'import manuale di una release scelta dall'admin che Radarr/Sonarr non importerebbero (decisione 9).
/// </summary>
public sealed partial class DownloadService
{
    // Una release dell'admin bloccata in coda, da importare a mano fuori dal lock: un download, una chiamata.
    private sealed record ManualImport(string Key, ArrKind Service, string DownloadId, int QueueId);

    /// <summary>
    /// Rifà l'elenco da ripassare (spec T §6), anche con i download automatici spenti. Un servizio in errore tiene le sue
    /// righe di prima; la data cambia solo se almeno uno ha risposto.
    /// </summary>
    public async Task BuildReviewAsync(CancellationToken cancellationToken)
    {
        var movies = await ReadAsync(ArrKind.Radarr, ReadMovieReviewAsync, cancellationToken).ConfigureAwait(false);
        var seasons = await ReadAsync(ArrKind.Sonarr, ReadSeasonReviewAsync, cancellationToken).ConfigureAwait(false);
        if (movies.Value is null && seasons.Value is null)
        {
            return;
        }

        lock (_lock)
        {
            var old = Book.Review;
            var rows = (movies.Value ?? old.Where(r => r.Key.StartsWith("movie:", StringComparison.Ordinal)))
                .Concat(seasons.Value ?? old.Where(r => r.Key.StartsWith("season:", StringComparison.Ordinal)));

            // Un titolo con una voce lo segue già il giro.
            Book.SetReview(
                [.. rows.Where(r => !Book.IsAccepted(r.Key) && Book.Get(r.Key) is null).OrderBy(r => r.Score).ThenByDescending(r => r.SizeBytes)],
                time.GetUtcNow());
            store.Save(Book);
        }
    }

    // Fuori dal lock: i film con un file e il loro file.
    private async Task<List<ReviewItem>> ReadMovieReviewAsync(CancellationToken cancellationToken)
    {
        var movies = (await arr.GetLibraryMoviesAsync(cancellationToken).ConfigureAwait(false))
            .OfType<RadarrMovie>().Where(m => m.MovieFile?.Id > 0).ToList();
        var profiles = await ProfileNamesAsync(ArrKind.Radarr, cancellationToken).ConfigureAwait(false);
        var files = ByKey(
            (await arr.GetMovieFilesAsync([.. movies.Select(m => m.MovieFile!.Id)], cancellationToken).ConfigureAwait(false)).OfType<ArrFile>(),
            f => f.MovieId);
        var rows = new List<ReviewItem>();
        foreach (var movie in movies)
        {
            var title = MovieTitleOf(movie);
            if (files.GetValueOrDefault(movie.Id) is { } file
                && BelowTarget(ArrKind.Radarr, movie.QualityProfileId, profiles, [file], title.Key, title.Kind, title.Title, title.PosterUrl) is { } row)
            {
                rows.Add(row);
            }
        }

        return rows;
    }

    // Fuori dal lock: le serie con file, una lettura dei file per serie, una riga per stagione (> 0).
    private async Task<List<ReviewItem>> ReadSeasonReviewAsync(CancellationToken cancellationToken)
    {
        var series = (await arr.GetSeriesAsync(cancellationToken).ConfigureAwait(false))
            .OfType<SonarrSeries>().Where(s => s.Statistics?.EpisodeFileCount > 0).ToList();
        var profiles = await ProfileNamesAsync(ArrKind.Sonarr, cancellationToken).ConfigureAwait(false);
        var rows = new List<ReviewItem>();
        foreach (var show in series)
        {
            var files = (await arr.GetEpisodeFilesAsync(show.Id, cancellationToken).ConfigureAwait(false)).OfType<ArrFile>();
            foreach (var season in files.Where(f => f.SeasonNumber > 0).GroupBy(f => f.SeasonNumber))
            {
                var key = new DownloadKey(DownloadKinds.Season, show.Id, season.Key).ToString();
                if (BelowTarget(ArrKind.Sonarr, show.QualityProfileId, profiles, [.. season], key, DownloadKinds.Season, SeasonTitleOf(show.Title, season.Key), Poster(show.Images)) is { } row)
                {
                    rows.Add(row);
                }
            }
        }

        return rows;
    }

    private async Task<Dictionary<int, string?>> ProfileNamesAsync(ArrKind kind, CancellationToken cancellationToken) =>
        ByKey((await arr.GetQualityProfilesAsync(kind, cancellationToken).ConfigureAwait(false)).OfType<ArrQualityProfile>(), p => p.Id)
            .ToDictionary(p => p.Key, p => p.Value.Name);

    // La riga se il file peggiore è sotto l'obiettivo; senza obiettivo (anime) mai (ruling 2). Peso: tutti i file.
    private ReviewItem? BelowTarget(
        ArrKind kind, int profileId, IReadOnlyDictionary<int, string?> profiles, IReadOnlyList<ArrFile> files, string key, string itemKind, string title, string? poster)
    {
        var worst = files.MinBy(f => f.CustomFormatScore);
        var target = settings.For(kind, profileId, profiles.GetValueOrDefault(profileId)).TargetScore;
        return worst is null || target is not { } goal || worst.CustomFormatScore >= goal ? null : new ReviewItem
        {
            Key = key,
            Kind = itemKind,
            Title = title,
            PosterUrl = poster,
            Score = worst.CustomFormatScore,
            SizeBytes = files.Sum(f => f.Size),
            Quality = worst.Quality?.Quality?.Name ?? "",
        };
    }

    // Fuori dal lock: i file del download, poi il comando ManualImport. Se non riesce, serve l'admin.
    private async Task ImportByHandAsync(ManualImport import, CancellationToken cancellationToken)
    {
        string error;
        try
        {
            var files = (await arr.GetManualImportAsync(import.Service, import.DownloadId, cancellationToken).ConfigureAwait(false))
                .OfType<ArrManualImportItem>().Where(i => Importable(import.Service, i)).ToList();
            if (files.Count > 0)
            {
                await arr.ManualImportAsync(import.Service, files, cancellationToken).ConfigureAwait(false);
                logger.LogInformation("Download automatici: {Key} importato a mano da {Kind}", import.Key, import.Service);
                return;
            }

            error = "NoFiles";
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            error = ErrorOf(ex);
        }

        logger.LogWarning("Download automatici: {Key}, {Kind} non ha importato a mano ({Error})", import.Key, import.Service, error);
        lock (_lock)
        {
            if (Book.Get(import.Key) is { } entry && entry.QueueId == import.QueueId)
            {
                entry.State = DownloadStates.NeedsYou;
                entry.Reason = DownloadReasons.ImportBlocked;
            }
        }
    }

    // Un file riconosciuto (il film, o la serie e gli episodi) e non un sample: un sample prenderebbe il posto del film.
    private static bool Importable(ArrKind kind, ArrManualImportItem item) =>
        !string.IsNullOrEmpty(item.Path)
        && item.Quality is not null
        && (kind == ArrKind.Radarr ? item.Movie?.Id > 0 : item.Series?.Id > 0 && item.Episodes?.Any(e => e?.Id > 0) == true)
        && item.Rejections?.Any(r => r?.Reason?.StartsWith("Sample", StringComparison.OrdinalIgnoreCase) == true) != true;
}
