using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Home;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>Le operazioni dello spazio, passo per passo (spec U §6.2 e §6.5).</summary>
public sealed partial class SpaceService
{
    /// <summary>Legge la coda ed esegue un'operazione alla volta, finché non si annulla (la avvia il servizio in background).</summary>
    public async Task RunOperationsAsync(CancellationToken cancellationToken)
    {
        await foreach (var id in _queue.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
        {
            await RunGuardedAsync(id, cancellationToken).ConfigureAwait(false);
        }
    }

    /// <summary>Esegue le operazioni già in coda e ritorna: per i test.</summary>
    internal async Task DrainAsync(CancellationToken cancellationToken)
    {
        while (_queue.Reader.TryRead(out var id))
        {
            await RunGuardedAsync(id, cancellationToken).ConfigureAwait(false);
        }
    }

    // Un errore inatteso ferma solo la sua operazione, che risulta fallita; la coda va avanti.
    private async Task RunGuardedAsync(string id, CancellationToken cancellationToken)
    {
        try
        {
            await RunAsync(id, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            // Solo il tipo: il messaggio di un errore inatteso potrebbe contenere un percorso.
            logger.LogError("Spazio: operazione {Id} interrotta da un errore inatteso ({Error})", id, ex.GetType().Name);
            lock (_lock)
            {
                if (Book.Operation(id) is { } operation && IsActive(operation))
                {
                    Abort(operation);
                    Save();
                }
            }
        }
        finally
        {
            lock (_lock)
            {
                _scanOf.Remove(id);
            }
        }
    }

    private async Task RunAsync(string id, CancellationToken cancellationToken)
    {
        var before = ReadQuota();
        Run run;
        string[] names;
        lock (_lock)
        {
            if (Book.Operation(id) is not { State: SpaceOperationStates.Queued } operation || !_scanOf.TryGetValue(id, out var scan))
            {
                return;
            }

            operation.State = SpaceOperationStates.Running;
            operation.QuotaBeforeBytes = before?.UsedBytes;
            run = new Run(operation.Kind, operation.Key, operation.Title, scan) { StartedAt = operation.StartedAt };
            names = [.. operation.Steps.Select(s => s.Name)];
            Save();
        }

        for (var i = 0; i < names.Length; i++)
        {
            SetStep(id, i, step => step.State = SpaceStepStates.Running);
            var result = await GuardAsync(names[i], run, cancellationToken).ConfigureAwait(false);
            var level = result.Detail == SpaceDetails.Unreachable ? LogLevel.Warning : LogLevel.Information;
            logger.Log(level, "Spazio: {Kind} {Key}, passo {Step}: {State} {Detail}", run.Kind, LogKey(run.Key), names[i], result.State, result.Detail);

            var last = i == names.Length - 1;
            var failed = result.State == SpaceStepStates.Failed;
            lock (_lock)
            {
                var operation = Book.Operation(id)!;
                var step = operation.Steps[i];
                (step.State, step.Detail, step.Done, step.Waiting) = (result.State, result.Detail, result.Done, result.Waiting);
                (operation.EstimatedFreedBytes, operation.PendingBytes, operation.QuotaAfterBytes) = (run.Freed, run.Pending, run.QuotaAfter);
                operation.RemovedHashes = [.. run.Removed];
                if (failed)
                {
                    Abort(operation);
                }
                else if (last)
                {
                    operation.State = SpaceOperationStates.Done;
                    operation.EndedAt = time.GetUtcNow();
                }

                Save();
            }

            if (failed)
            {
                return;
            }
        }
    }

    private void SetStep(string id, int index, Action<SpaceStep> change)
    {
        lock (_lock)
        {
            change(Book.Operation(id)!.Steps[index]);
            Save();
        }
    }

    /// <summary>
    /// Un passo con gli errori della spec U §6.5: un 404 è "saltato" (<c>Gone</c>) e si va avanti; gli altri errori
    /// di Radarr, Sonarr, qBittorrent, Seerr e del disco fanno fallire il passo con il loro codice.
    /// </summary>
    private async Task<StepResult> GuardAsync(string name, Run run, CancellationToken cancellationToken)
    {
        try
        {
            return await StepAsync(name, run, cancellationToken).ConfigureAwait(false);
        }
        catch (ArrException ex) when (ex.Status == 404)
        {
            return StepResult.Skipped(SpaceDetails.Gone);
        }
        catch (QbitException ex) when (ex.Error == QbitError.NotFound)
        {
            return StepResult.Skipped(SpaceDetails.Gone);
        }
        catch (SeerrException ex) when (ex.Error == SeerrError.NotFound)
        {
            return StepResult.Skipped(SpaceDetails.Gone);
        }
        catch (ArrException ex)
        {
            return StepResult.Failed(UpcomingErrors.Code(ex.Error));
        }
        catch (QbitException ex)
        {
            return StepResult.Failed(CodeOf(ex.Error));
        }
        catch (SeerrException ex)
        {
            return StepResult.Failed(CodeOf(ex.Error));
        }
        catch (TimeoutException)
        {
            // stat non ha risposto: i file non vanno trattati come mancanti.
            return StepResult.Failed(SpaceDetails.Unreachable);
        }
    }

    /// <summary>Il codice di un errore di qBittorrent (spec U §6.5).</summary>
    private static string CodeOf(QbitError error) => error switch
    {
        QbitError.NotConfigured => SpaceDetails.NotConfigured,
        QbitError.Unauthorized => SpaceDetails.Unauthorized,
        _ => SpaceDetails.Unreachable,
    };

    /// <summary>Il codice di un errore di Seerr (spec U §6.5).</summary>
    private static string CodeOf(SeerrError error) => error switch
    {
        SeerrError.NotConfigured => SpaceDetails.NotConfigured,
        SeerrError.Auth => SpaceDetails.Unauthorized,
        _ => SpaceDetails.Unreachable,
    };

    /// <summary>I passi di ogni tipo, in ordine (spec U §6.2).</summary>
    private static string[] StepsOf(string kind) => kind switch
    {
        SpaceKinds.Movie =>
        [
            SpaceSteps.FindTorrents, SpaceSteps.RemoveFromQueue, SpaceSteps.DeleteFromRadarr, SpaceSteps.RemoveTorrents,
            SpaceSteps.RemoveFromSeerr, SpaceSteps.RefreshLibrary, SpaceSteps.ReadQuota,
        ],
        SpaceKinds.Series =>
        [
            SpaceSteps.FindTorrents, SpaceSteps.RemoveFromQueue, SpaceSteps.DeleteFromSonarr, SpaceSteps.RemoveTorrents,
            SpaceSteps.RemoveFromSeerr, SpaceSteps.RefreshLibrary, SpaceSteps.ReadQuota,
        ],
        SpaceKinds.Season =>
        [
            SpaceSteps.FindTorrents, SpaceSteps.RemoveFromQueue, SpaceSteps.UnmonitorSeason, SpaceSteps.DeleteEpisodeFiles,
            SpaceSteps.RemoveTorrents, SpaceSteps.RefreshLibrary, SpaceSteps.ReadQuota,
        ],
        SpaceKinds.Torrent or SpaceKinds.AllTorrents => [SpaceSteps.RemoveTorrents, SpaceSteps.ReadQuota],
        _ => [SpaceSteps.DeleteFile, SpaceSteps.ReadQuota],
    };

    private Task<StepResult> StepAsync(string name, Run run, CancellationToken ct) => name switch
    {
        SpaceSteps.FindTorrents => FindTorrentsAsync(run, ct),
        SpaceSteps.RemoveFromQueue => RemoveFromQueueAsync(run, ct),
        SpaceSteps.DeleteFromRadarr => DoneAfter(arr.DeleteMovieAsync(run.ArrId, ct)),
        SpaceSteps.DeleteFromSonarr => DoneAfter(arr.DeleteSeriesAsync(run.ArrId, ct)),
        SpaceSteps.UnmonitorSeason => DoneAfter(arr.SetSeasonMonitoredAsync(run.ArrId, run.Season, false, ct)),
        SpaceSteps.DeleteEpisodeFiles => DeleteEpisodeFilesAsync(run, ct),
        SpaceSteps.RemoveTorrents => run.Kind is SpaceKinds.Torrent or SpaceKinds.AllTorrents
            ? RemoveCleanupTorrentsAsync(run, ct)
            : RemoveTitleTorrentsAsync(run, ct),
        SpaceSteps.RemoveFromSeerr => RemoveFromSeerrAsync(run, ct),
        SpaceSteps.RefreshLibrary => Refresh(),
        SpaceSteps.DeleteFile => DeleteFileAsync(run, ct),
        _ => Task.FromResult(ReadQuotaStep(run)),
    };

    private static async Task<StepResult> DoneAfter(Task call)
    {
        await call.ConfigureAwait(false);
        return StepResult.Ok();
    }

    /// <summary>L'esito di un passo.</summary>
    private readonly record struct StepResult(string State, string? Detail = null, int? Done = null, int? Waiting = null)
    {
        public static StepResult Ok(int? done = null, int? waiting = null) => new(SpaceStepStates.Done, null, done, waiting);

        public static StepResult Skipped(string detail) => new(SpaceStepStates.Skipped, detail);

        public static StepResult Failed(string detail) => new(SpaceStepStates.Failed, detail);
    }

    /// <summary>Quello che un'operazione si porta tra un passo e l'altro. Lo usa solo il ciclo delle operazioni, fuori dal lock.</summary>
    private sealed class Run
    {
        public Run(string kind, string key, string title, SpaceScan scan)
        {
            (Kind, Key, Title, Scan) = (kind, key, title, scan);
            var parts = key.Split(':');
            ArrId = parts.Length > 1 && int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var id) ? id : 0;
            Season = parts.Length > 2 && int.TryParse(parts[2], NumberStyles.None, CultureInfo.InvariantCulture, out var season) ? season : 0;
        }

        public string Kind { get; }

        public string Key { get; }

        public string Title { get; }

        public SpaceScan Scan { get; }

        public DateTimeOffset StartedAt { get; init; }

        /// <summary>Id di Radarr/Sonarr dalla chiave (<c>movie:12</c>, <c>series:5</c>, <c>season:5:2</c>); 0 per gli altri.</summary>
        public int ArrId { get; }

        public int Season { get; }

        /// <summary>Il titolo nel calcolo, per film, serie e stagioni.</summary>
        public ScanTitle? Scanned => Scan.Titles.GetValueOrDefault(Key);

        /// <summary>La stima di <c>FindTorrents</c>; null se il passo è stato saltato.</summary>
        public SpaceEstimate? Estimate { get; set; }

        public IReadOnlyDictionary<string, TorrentFacts> Facts { get; set; } = new Dictionary<string, TorrentFacts>();

        public long Freed { get; set; }

        public long Pending { get; set; }

        public long? QuotaAfter { get; set; }

        /// <summary>Gli hash che la Pulizia ha tolto davvero.</summary>
        public IReadOnlyList<string> Removed { get; set; } = [];
    }
}
