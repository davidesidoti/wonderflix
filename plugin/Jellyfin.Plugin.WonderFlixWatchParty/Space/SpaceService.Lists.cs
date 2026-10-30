using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Le liste dei titoli del calcolo: Cancellare, Alleggerire e la divisione dello spazio (spec U §5.1, §5.2 e §5.4).</summary>
public sealed partial class SpaceService
{
    /// <summary>I voti sono da 1 a 10; la media e le soglie dello spazio sono in stelle, da 1 a 5 (spec U §4.1 e §4.3).</summary>
    private const double ScorePerStar = 2;

    /// <summary>GB = 10⁹ byte.</summary>
    private const double BytesPerGb = 1_000_000_000;

    /// <summary>La durata di un film quando Radarr non la sa (spec U §5.2).</summary>
    private const int DefaultMovieMinutes = 100;

    /// <summary>La durata di un episodio quando Sonarr non la sa (spec U §5.2).</summary>
    private const int DefaultEpisodeMinutes = 40;

    private const double MinutesPerHour = 60;

    /// <summary>Un titolo è anime se il suo percorso passa da questa cartella (spec U §5.4).</summary>
    private const string AnimeFolder = "/anime/";

    private const string ReleasedStatus = "released";

    private const string EndedStatus = "ended";

    private static string MovieKey(int id) => string.Create(CultureInfo.InvariantCulture, $"movie:{id}");

    private static string SeriesKey(int id) => string.Create(CultureInfo.InvariantCulture, $"series:{id}");

    private static string SeasonKey(int id, int season) => string.Create(CultureInfo.InvariantCulture, $"season:{id}:{season}");

    /// <summary>
    /// Film con un file, serie <c>ended</c> intere e stagioni (decisione 6): segnali, stima e righe. Una riga va in Cancellare
    /// se ha un segnale "via"; le stagioni di una serie già in Cancellare intera restano fuori. Alleggerire esclude i titoli
    /// (e le serie) in Cancellare.
    /// </summary>
    private TitleLists BuildTitles(ScanData data, DateTimeOffset now)
    {
        var thresholds = SpaceThresholds.From(settings);
        var people = users.GetUsers().DistinctBy(u => u.Id).ToDictionary(u => u.Id);
        IReadOnlyCollection<Guid> voters = [.. people.Values.Where(u => u.Enabled).Select(u => u.Id)];
        var requests = data.Requests.Select(r => (Request: r, Fact: RequestOf(r, people))).Where(x => x.Fact is not null).ToList();
        var movieItems = ByExternalId(jellyfin.GetMovies().Select(m => (m.TmdbId, m.Id)));
        var jellyfinSeries = jellyfin.GetSeries();
        var seriesByTvdb = ByExternalId(jellyfinSeries.Select(s => (s.TvdbId, s.Id)));
        var seriesByTmdb = ByExternalId(jellyfinSeries.Select(s => (s.TmdbId, s.Id)));

        // Seguito in arrivo (decisione 5): una collezione con un film senza file e non ancora uscito.
        var sequels = data.Movies
            .Where(m => !m.HasFile && m.Collection is { TmdbId: > 0 } && !string.Equals(m.Status, ReleasedStatus, StringComparison.OrdinalIgnoreCase))
            .Select(m => m.Collection!.TmdbId)
            .ToHashSet();

        var titles = new Dictionary<string, ScanTitle>();
        var delete = new List<ScanRow<SpaceCandidateDto>>();
        var lighten = new List<ScanRow<SpaceLightenDto>>();
        var rated = new List<Guid>();

        bool Add(TitleSource source, bool listed = true)
        {
            var (row, title) = Evaluate(source, data, thresholds, now);
            titles[source.Key] = title;
            if (!listed || row.Dto.Via.Count == 0)
            {
                return false;
            }

            delete.Add(row);
            return true;
        }

        foreach (var movie in data.Movies.Where(m => m.HasFile))
        {
            var key = MovieKey(movie.Id);
            var itemId = Find(movieItems, movie.TmdbId);
            var view = itemId is { } id ? viewing.Movie(id) : null;
            IReadOnlyList<Guid> itemIds = itemId is { } i ? [i] : [];
            rated.AddRange(itemIds);
            var poster = DownloadService.Poster(movie.Images);
            Add(new TitleSource(
                key, SpaceKinds.Movie, movie.Title ?? "", movie.Title ?? "", movie.Year > 0 ? movie.Year : null, null, null,
                itemId, itemIds, poster, movie.SizeOnDisk, movie.MovieFile?.Path is { } path ? [path] : [],
                view, view?.Added ?? movie.Added,
                [.. requests.Where(x => IsMovie(x.Request) && x.Request.Media?.TmdbId == movie.TmdbId).Select(x => x.Fact!)],
                RatingOf(itemId, voters),
                movie.Collection is { TmdbId: > 0 } collection && sequels.Contains(collection.TmdbId),
                view?.Genres ?? [], movie.TmdbId, movie.Path));
            if (movie.MovieFile is { Size: > 0 } file
                && Heavy(key, SpaceKinds.Movie, movie.Title ?? "", null, itemId, poster, file.Size,
                    (movie.Runtime > 0 ? movie.Runtime : DefaultMovieMinutes) / MinutesPerHour, [key], itemIds) is { } heavy)
            {
                lighten.Add(heavy);
            }
        }

        foreach (var (show, files) in data.Series.Where(s => s.Files.Count > 0))
        {
            var seriesKey = SeriesKey(show.Id);
            var seriesItem = Find(seriesByTvdb, show.TvdbId) ?? Find(seriesByTmdb, show.TmdbId);
            var seriesView = seriesItem is { } sid ? viewing.Series(sid) : null;
            var seasonViews = seriesItem is { } id ? viewing.Seasons(id) : new Dictionary<int, ItemViewing>();
            rated.AddRange(seasonViews.Values.Select(v => v.ItemId));
            var poster = DownloadService.Poster(show.Images);
            var genres = seriesView?.Genres ?? [];
            int? year = show.Year > 0 ? show.Year : null;
            var showRequests = requests.Where(x => IsTv(x.Request) && SameShow(x.Request.Media, show)).ToList();
            var seasonRatings = seasonViews.Values.Select(v => RatingOf(v.ItemId, voters)).Where(r => r.Avg is not null).ToList();
            var withFiles = (show.Seasons ?? []).OfType<SonarrSeason>()
                .Where(s => s.SeasonNumber > 0 && s.Statistics is { EpisodeFileCount: > 0 })
                .ToList();
            var ended = string.Equals(show.Status, EndedStatus, StringComparison.OrdinalIgnoreCase);

            // Voti della serie (decisione 8): la media delle medie delle stagioni.
            var wholeListed = ended && Add(new TitleSource(
                seriesKey, SpaceKinds.Series, show.Title ?? "", show.Title ?? "", year, null, null,
                seriesItem, seriesItem is { } whole ? [whole] : [], poster, show.Statistics?.SizeOnDisk ?? 0,
                [.. files.Select(f => f.Path).OfType<string>()],
                seriesView, seriesView?.Added ?? show.Added, [.. showRequests.Select(x => x.Fact!)],
                seasonRatings.Count == 0 ? (null, 0) : (seasonRatings.Average(r => r.Avg!.Value), seasonRatings.Sum(r => r.Count)),
                false, genres, show.TmdbId, show.Path));

            // Di una serie in corso mai l'ultima stagione con episodi.
            var last = withFiles.Count == 0 ? 0 : withFiles.Max(s => s.SeasonNumber);
            var minutes = show.Runtime > 0 ? show.Runtime : DefaultEpisodeMinutes;
            foreach (var season in withFiles)
            {
                var n = season.SeasonNumber;
                var key = SeasonKey(show.Id, n);
                var view = seasonViews.GetValueOrDefault(n);
                var seasonFiles = files.Where(f => f.SeasonNumber == n).ToList();
                IReadOnlyList<Guid> itemIds = [.. new[] { view?.ItemId, seriesItem }.OfType<Guid>()];
                if (ended || n != last)
                {
                    Add(
                        new TitleSource(
                            key, SpaceKinds.Season, show.Title ?? "", DownloadService.SeasonTitleOf(show.Title, n), year, n, seriesKey,
                            view?.ItemId, itemIds, poster, season.Statistics!.SizeOnDisk,
                            [.. seasonFiles.Select(f => f.Path).OfType<string>()],
                            view, view?.Added ?? show.Added,
                            [.. showRequests.Where(x => x.Request.Seasons.Count == 0 || x.Request.Seasons.Any(r => r.SeasonNumber == n)).Select(x => x.Fact!)],
                            RatingOf(view?.ItemId, voters), false, genres, show.TmdbId, show.Path),
                        listed: !wholeListed);
                }

                if (Heavy(key, SpaceKinds.Season, show.Title ?? "", n, view?.ItemId, poster, seasonFiles.Sum(f => f.Size),
                        seasonFiles.Count * minutes / MinutesPerHour, [key, seriesKey], itemIds) is { } heavy)
                {
                    lighten.Add(heavy);
                }
            }
        }

        var deleted = delete.Select(r => r.Dto.Key).ToHashSet();
        return new TitleLists(
            titles,
            [.. delete
                .OrderBy(r => r.Dto.Keep.Count > 0)
                .ThenByDescending(r => r.Dto.FreeNowBytes + r.Dto.FreeLaterBytes)
                .ThenBy(r => r.Dto.Key, StringComparer.Ordinal)],
            [.. lighten
                .Where(r => !r.Keys.Any(deleted.Contains))
                .OrderByDescending(r => r.Dto.ExcessBytes)
                .ThenBy(r => r.Dto.Key, StringComparer.Ordinal)],
            rated);
    }

    /// <summary>Segnali, stima e torrent di un titolo (spec U §4 e §5.1): la riga di Cancellare e il titolo per le operazioni.</summary>
    private (ScanRow<SpaceCandidateDto> Row, ScanTitle Title) Evaluate(TitleSource t, ScanData data, SpaceThresholds thresholds, DateTimeOffset now)
    {
        IReadOnlyList<FileFact> files = [.. t.Paths.Distinct().Where(data.Stamps.ContainsKey)
            .Select(p => new FileFact(p, data.Stamps[p].Id, data.Stamps[p].Links, data.Stamps[p].SizeBytes))];
        var estimate = SpaceMath.Estimate(files, data.Index, data.LibraryFiles, settings.Seed, now);
        var usage = t.Viewing?.Usage ?? [];
        var signals = SpaceSignals.Evaluate(
            new TitleFacts(t.Added, usage, t.Requests, t.Rating.Avg, t.Rating.Count, t.SequelComing), thresholds, now);

        // I torrent legati al titolo: quelli che la stima toglie e ogni altro che ha un suo file.
        IReadOnlyList<string> hashes = [.. estimate.RemoveNow
            .Concat(estimate.RemoveLater)
            .Concat(files.SelectMany(f => data.Index.HashesByFile.GetValueOrDefault(f.Id) ?? []))
            .Distinct()];
        var dto = new SpaceCandidateDto(
            t.Key,
            t.Kind,
            t.Title,
            t.Year,
            t.Season,
            t.SeriesKey,
            t.ItemId?.ToString("N"),
            t.Poster,
            t.SizeBytes,
            estimate.FreeNowBytes,
            estimate.FreeLaterBytes,
            estimate.FreeLaterAt,
            estimate.InPackBytes,
            signals.Via,
            signals.Keep,
            [.. usage.Select(u => new SpaceViewerDto(u.Name, u.Finished, u.LastPlayed))],
            [.. t.Requests.Select(r => new SpaceRequestDto(r.Name, r.At))],
            t.Rating.Avg,
            t.Rating.Count,
            signals.LastOpened,
            t.Added,
            t.Genres);
        IReadOnlyList<string> keys = t.SeriesKey is { } series ? [t.Key, series] : [t.Key];
        return (new ScanRow<SpaceCandidateDto>(dto, keys, t.ItemIds), new ScanTitle(t.OperationTitle, t.TmdbId, t.Folder, files, hashes));
    }

    /// <summary>La riga di Alleggerire se il file supera la soglia di GB all'ora (spec U §5.2); null altrimenti.</summary>
    private ScanRow<SpaceLightenDto>? Heavy(
        string key, string kind, string title, int? season, Guid? itemId, string? poster, long sizeBytes, double hours,
        IReadOnlyList<string> keys, IReadOnlyList<Guid> itemIds)
    {
        var limit = settings.HeavyGbPerHour * BytesPerGb * hours;
        return hours > 0 && sizeBytes > limit
            ? new ScanRow<SpaceLightenDto>(
                new SpaceLightenDto(
                    key, kind, title, season, itemId?.ToString("N"), poster, sizeBytes, (long)(sizeBytes - limit),
                    Math.Round(sizeBytes / BytesPerGb / hours, 2)),
                keys,
                itemIds)
            : null;
    }

    /// <summary>La media dei voti in stelle e quanti sono, tra gli utenti attivi (spec U §4.1).</summary>
    private (double? Avg, int Count) RatingOf(Guid? itemId, IReadOnlyCollection<Guid> voters)
    {
        if (itemId is not { } id)
        {
            return (null, 0);
        }

        var scores = ratings.Of(id, voters).Values.Select(r => r.Score).ToList();
        return (RatingService.Average(scores) / ScorePerStar, scores.Count);
    }

    /// <summary>
    /// Una richiesta come fatto per i segnali (spec U §4.2): il richiedente è l'utente Jellyfin di <c>JellyfinUserId</c>.
    /// Null se quell'utente è disattivato o non c'è più (spec U §11); chi non è di Jellyfin conta con il nome di Seerr.
    /// </summary>
    private static RequestFact? RequestOf(SeerrRequest request, IReadOnlyDictionary<Guid, UserRef> people)
    {
        if (!Guid.TryParse(request.RequestedBy?.JellyfinUserId, out var userId))
        {
            return new RequestFact(null, request.RequestedBy?.DisplayName ?? "", request.CreatedAt);
        }

        return people.TryGetValue(userId, out var user) && user.Enabled ? new RequestFact(user.Id, user.Name, request.CreatedAt) : null;
    }

    private static bool IsMovie(SeerrRequest request) => (request.Media?.MediaType ?? request.Type) == "movie";

    private static bool IsTv(SeerrRequest request) => (request.Media?.MediaType ?? request.Type) == "tv";

    // TVDB, poi TMDB.
    private static bool SameShow(SeerrRequestMedia? media, SonarrSeries show) =>
        media is not null && ((show.TvdbId > 0 && media.TvdbId == show.TvdbId) || (show.TmdbId > 0 && media.TmdbId == show.TmdbId));

    private static Dictionary<string, Guid> ByExternalId(IEnumerable<(string? ExternalId, Guid ItemId)> items) =>
        items.Where(x => !string.IsNullOrEmpty(x.ExternalId))
            .GroupBy(x => x.ExternalId!)
            .ToDictionary(g => g.Key, g => g.First().ItemId);

    private static Guid? Find(Dictionary<string, Guid> items, int externalId) =>
        externalId > 0 && items.TryGetValue(externalId.ToString(CultureInfo.InvariantCulture), out var id) ? id : null;

    /// <summary>La divisione (spec U §5.4): film e serie da <c>sizeOnDisk</c>, gli anime a parte, poi i torrent e il resto della quota.</summary>
    private static SpaceBreakdownDto Breakdown(
        IReadOnlyList<RadarrMovie> movies, IReadOnlyList<ScanSeries> series, SpaceCleanupDto cleanup, Quota? quota)
    {
        static bool IsAnime(string? path) => path?.Contains(AnimeFolder, StringComparison.OrdinalIgnoreCase) == true;

        var moviesBytes = movies.Where(m => !IsAnime(m.Path)).Sum(m => m.SizeOnDisk);
        var seriesBytes = series.Where(s => !IsAnime(s.Show.Path)).Sum(s => s.Show.Statistics?.SizeOnDisk ?? 0);
        var animeBytes = movies.Where(m => IsAnime(m.Path)).Sum(m => m.SizeOnDisk)
            + series.Where(s => IsAnime(s.Show.Path)).Sum(s => s.Show.Statistics?.SizeOnDisk ?? 0);
        var torrentOnlyBytes = cleanup.Torrents.Sum(t => t.SizeBytes);
        var known = moviesBytes + seriesBytes + animeBytes + torrentOnlyBytes;
        return new SpaceBreakdownDto(
            moviesBytes, seriesBytes, animeBytes, torrentOnlyBytes, quota is null ? 0 : Math.Max(0, quota.UsedBytes - known));
    }

    /// <summary>Un titolo da valutare, con tutto quello che serve alla sua riga e alle operazioni.</summary>
    private sealed record TitleSource(
        string Key,
        string Kind,
        string Title,
        string OperationTitle,
        int? Year,
        int? Season,
        string? SeriesKey,
        Guid? ItemId,
        IReadOnlyList<Guid> ItemIds,
        string? Poster,
        long SizeBytes,
        IReadOnlyList<string> Paths,
        ItemViewing? Viewing,
        DateTimeOffset? Added,
        IReadOnlyList<RequestFact> Requests,
        (double? Avg, int Count) Rating,
        bool SequelComing,
        IReadOnlyList<string> Genres,
        int TmdbId,
        string? Folder);

    /// <summary>Le liste dei titoli, già in ordine.</summary>
    private sealed record TitleLists(
        IReadOnlyDictionary<string, ScanTitle> Titles,
        IReadOnlyList<ScanRow<SpaceCandidateDto>> Delete,
        IReadOnlyList<ScanRow<SpaceLightenDto>> Lighten,
        IReadOnlyList<Guid> RatedItems);
}
