using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Esito di creazione e chiusura: Report è la segnalazione, null alla chiusura.</summary>
public sealed record ReportOutcome(HubStatus Status, string? Reason, ReportDto? Report)
{
    public static readonly ReportOutcome Invalid = new(HubStatus.Invalid, null, null);

    public static ReportOutcome Ok(ReportDto? report) => new(HubStatus.Ok, null, report);

    public static ReportOutcome Conflict(string reason) => new(HubStatus.Conflict, reason, null);
}

/// <summary>
/// Le segnalazioni aperte (spec R §6): creazione, elenchi, chiusura e pulizia.
/// File con <see cref="ReportStore"/>. Sicuro tra thread.
/// </summary>
public sealed class ReportService(
    ReportStore store,
    IUserDirectory users,
    ILibraryAccess access,
    IReportLibrary library,
    ILibraryTitles titles,
    InboxService inbox,
    TimeProvider time,
    ILogger<ReportService> logger)
{
    /// <summary>Segnalazioni aperte per utente (spec R §6.1).</summary>
    public const int MaxOpenPerUser = 20;

    /// <summary>Lunghezza massima di una nota (segnalazione o chiusura), in punti di codice.</summary>
    public const int MaxNoteLength = 500;

    // Per le notifiche della cassetta (Task 3): ancora non usata.
    private readonly InboxService _inbox = inbox;
    private readonly Lock _lock = new();
    private ReportBook? _book;

    // Solo sotto _lock. Il file si legge alla prima occasione.
    private ReportBook Book
    {
        get
        {
            if (_book is null)
            {
                _book = store.Load();
                logger.LogInformation("Segnalazioni in {Path}", store.FilePath);
            }

            return _book;
        }
    }

    /// <summary>La nota pulita (null se vuota); <paramref name="tooLong"/> se supera <see cref="MaxNoteLength"/> punti di codice.</summary>
    internal static string? CleanNote(string? note, out bool tooLong)
    {
        var clean = RecommendationService.CleanMessage(note);
        tooLong = (clean?.EnumerateRunes().Count() ?? 0) > MaxNoteLength;
        return clean;
    }

    /// <summary>Legge subito il file (all'avvio del plugin): eventuali problemi finiscono nel log.</summary>
    public void Load()
    {
        lock (_lock)
        {
            _ = Book;
        }
    }

    /// <summary>
    /// POST Reports (spec R §6.1). Invalid per utente, titolo, tipo o nota non validi, o se
    /// chi chiama non vede il titolo; Conflict LimitReached oltre le segnalazioni aperte.
    /// Un doppione (stesso titolo e tipo) cambia la nota.
    /// </summary>
    public Task<ReportOutcome> CreateAsync(Guid userId, CreateReportRequest? request)
    {
        var note = CleanNote(request?.Note, out var tooLong);
        if (request is null || tooLong || users.GetUser(userId) is not { } user
            || !Guid.TryParse(request.ItemId, out var itemId) || itemId == Guid.Empty
            || !ReportTypes.IsValid(request.Type)
            || Visible(userId, itemId) is not { } item)
        {
            return Task.FromResult(ReportOutcome.Invalid);
        }

        var now = time.GetUtcNow();
        StoredReport report;
        lock (_lock)
        {
            if (Book.FindOpen(userId, itemId, request.Type!) is { } open)
            {
                report = Book.UpdateNote(open.Id, note, now);
            }
            else if (Book.CountOpen(userId) >= MaxOpenPerUser)
            {
                return Task.FromResult(ReportOutcome.Conflict(ReportReasons.LimitReached));
            }
            else
            {
                report = new StoredReport(Guid.NewGuid(), userId, itemId, request.Type!, note, now, now);
                Book.Add(report);
            }

            Persist();
        }

        logger.LogDebug("Segnalazione {ReportId} di {UserId} su {ItemId}", Id(report.Id), Id(userId), Id(itemId));
        return Task.FromResult(ReportOutcome.Ok(ToDto(report, item, user.Name)));
    }

    /// <summary>GET Reports/Mine: le segnalazioni di chi chiama su un titolo. Invalid per un id non valido o un utente che non esiste.</summary>
    public HubResult<ReportListDto> Mine(Guid userId, string? itemId)
    {
        if (!Guid.TryParse(itemId, out var id) || id == Guid.Empty || users.GetUser(userId) is not { } user)
        {
            return HubResult<ReportListDto>.Fail(HubStatus.Invalid);
        }

        IReadOnlyList<StoredReport> mine;
        lock (_lock)
        {
            mine = Book.ForUser(userId, id);
        }

        return HubResult<ReportListDto>.Ok(Describe(mine, _ => user.Name));
    }

    /// <summary>GET Reports: tutte le aperte, dalla più recente. Per un titolo o un utente che non c'è più i nomi sono vuoti.</summary>
    public ReportListDto List()
    {
        IReadOnlyList<StoredReport> all;
        lock (_lock)
        {
            all = Book.All();
        }

        return Describe(all, id => users.GetUser(id)?.Name ?? string.Empty);
    }

    /// <summary>
    /// POST Reports/{id}/Resolve (spec R §6.3). Invalid per id, esito o nota non validi;
    /// Conflict Closed se la segnalazione non c'è più (già chiusa).
    /// </summary>
    public Task<ReportOutcome> ResolveAsync(Guid adminId, string? reportId, ResolveReportRequest? request)
    {
        _ = CleanNote(request?.Note, out var tooLong);
        if (request is null || tooLong || !ReportOutcomes.IsValid(request.Outcome)
            || !Guid.TryParse(reportId, out var id) || id == Guid.Empty)
        {
            return Task.FromResult(ReportOutcome.Invalid);
        }

        lock (_lock)
        {
            if (!Book.Remove(id))
            {
                return Task.FromResult(ReportOutcome.Conflict(ReportReasons.Closed));
            }

            Persist();
        }

        logger.LogInformation(
            "Segnalazione {ReportId} chiusa ({Outcome}) da {Admin}", Id(id), request.Outcome, AdminCaller.Describe(adminId));
        return Task.FromResult(ReportOutcome.Ok(null));
    }

    /// <summary>
    /// Toglie le segnalazioni di utenti spariti e di titoli che Jellyfin non ha più (spec R §6.5);
    /// restituisce quante. Durante una scansione o con la libreria in errore i titoli non si toccano.
    /// </summary>
    public int Cleanup()
    {
        var warned = false;
        bool ItemExists(Guid id)
        {
            if (titles.IsScanRunning)
            {
                return true;
            }

            try
            {
                return library.Find(id) is not null;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                if (!warned)
                {
                    warned = true;
                    logger.LogWarning(ex, "Pulizia delle segnalazioni: la libreria non risponde, i titoli restano");
                }

                return true;
            }
        }

        lock (_lock)
        {
            var removed = Book.Prune(id => users.GetUser(id) is not null, ItemExists).Count;
            if (removed > 0)
            {
                Persist();
                logger.LogDebug("Pulizia delle segnalazioni: {Count} tolte", removed);
            }

            return removed;
        }
    }

    // Il titolo, se chi chiama lo vede; null anche se la libreria lancia.
    private ReportedItem? Visible(Guid userId, Guid itemId)
    {
        try
        {
            return library.Find(itemId) is { } item && access.CanSee(userId, itemId) ? item : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Segnalazioni: la libreria non risponde per {ItemId}", Id(itemId));
            return null;
        }
    }

    // Un solo Warning per elenco se la libreria lancia: i nomi restano vuoti.
    private ReportListDto Describe(IReadOnlyList<StoredReport> reports, Func<Guid, string> userName)
    {
        var warned = false;
        var items = reports.Select(r =>
        {
            ReportedItem? item = null;
            try
            {
                item = library.Find(r.ItemId);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                if (!warned)
                {
                    warned = true;
                    logger.LogWarning(ex, "Segnalazioni: la libreria non risponde, i nomi restano vuoti");
                }
            }

            return ToDto(r, item, userName(r.UserId));
        }).ToList();
        return new ReportListDto(items);
    }

    private static ReportDto ToDto(StoredReport r, ReportedItem? item, string userName) =>
        new(
            Id(r.Id),
            r.Type,
            r.Note,
            r.CreatedAt,
            r.UpdatedAt,
            Id(r.UserId),
            userName,
            Id(r.ItemId),
            item?.Type ?? string.Empty,
            item?.Name ?? string.Empty,
            Id(item?.TitleId ?? r.ItemId),
            item?.TitleName ?? string.Empty,
            item?.SeasonNumber,
            item?.EpisodeNumber);

    // Solo sotto _lock. Un errore di disco non annulla il cambio in memoria:
    // finisce nel log e si riprova alla scrittura successiva.
    private void Persist()
    {
        try
        {
            store.Save(Book);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Segnalazioni non salvate in {Path}", store.FilePath);
        }
    }

    private static string Id(Guid id) => id.ToString("N");
}
