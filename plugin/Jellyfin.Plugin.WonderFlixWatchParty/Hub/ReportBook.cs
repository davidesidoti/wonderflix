using System.Globalization;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>Una segnalazione aperta di un utente su un titolo.</summary>
public sealed record StoredReport(Guid Id, Guid UserId, Guid ItemId, string Type, string? Note, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

/// <summary>
/// Le segnalazioni aperte in memoria (spec R §3), per id. Non è sicuro tra
/// thread: lo usa solo ReportService, sotto lock.
/// </summary>
public sealed class ReportBook
{
    private readonly Dictionary<Guid, StoredReport> _reports = [];

    public StoredReport? Get(Guid reportId) => _reports.GetValueOrDefault(reportId);

    /// <summary>La segnalazione aperta dello stesso utente su quel titolo e tipo, se c'è.</summary>
    public StoredReport? FindOpen(Guid userId, Guid itemId, string type) =>
        _reports.Values.FirstOrDefault(r => r.UserId == userId && r.ItemId == itemId && r.Type == type);

    public int CountOpen(Guid userId) => _reports.Values.Count(r => r.UserId == userId);

    public void Add(StoredReport report) => _reports[report.Id] = report;

    /// <summary>Cambia la nota (anche togliendola); CreatedAt resta. Solo con un id che c'è.</summary>
    public StoredReport UpdateNote(Guid reportId, string? note, DateTimeOffset now) =>
        _reports[reportId] = _reports[reportId] with { Note = note, UpdatedAt = now };

    /// <summary>Toglie la segnalazione; true se c'era.</summary>
    public bool Remove(Guid reportId) => _reports.Remove(reportId);

    /// <summary>Tutte, dalla più recente.</summary>
    public IReadOnlyList<StoredReport> All() => [.. _reports.Values.OrderByDescending(r => r.CreatedAt)];

    /// <summary>Quelle di un utente su un titolo, dalla più recente.</summary>
    public IReadOnlyList<StoredReport> ForUser(Guid userId, Guid itemId) =>
        [.. _reports.Values.Where(r => r.UserId == userId && r.ItemId == itemId).OrderByDescending(r => r.CreatedAt)];

    /// <summary>Toglie le segnalazioni di utenti o titoli che non esistono più; restituisce le tolte.</summary>
    public IReadOnlyList<StoredReport> Prune(Func<Guid, bool> userExists, Func<Guid, bool> itemExists)
    {
        var removed = _reports.Values.Where(r => !userExists(r.UserId) || !itemExists(r.ItemId)).ToList();
        foreach (var report in removed)
        {
            _reports.Remove(report.Id);
        }

        return removed;
    }

    /// <summary>Legge il file; <see cref="FormatException"/> per un id rovinato, un tipo sconosciuto o una voce null.</summary>
    public static ReportBook FromFile(ReportFile file)
    {
        var book = new ReportBook();
        foreach (var entry in file.Reports ?? throw new FormatException("elenco null"))
        {
            if (entry is null || !ReportTypes.IsValid(entry.Type))
            {
                throw new FormatException("segnalazione non valida");
            }

            book.Add(new StoredReport(ParseId(entry.Id), ParseId(entry.UserId), ParseId(entry.ItemId), entry.Type!, entry.Note, entry.CreatedAt, entry.UpdatedAt));
        }

        return book;
    }

    /// <summary>Il file da scrivere: dalla segnalazione più recente.</summary>
    public ReportFile ToFile() => new()
    {
        Reports = [.. All().Select(r => (ReportFileEntry?)new ReportFileEntry
        {
            Id = r.Id.ToString("N", CultureInfo.InvariantCulture),
            UserId = r.UserId.ToString("N", CultureInfo.InvariantCulture),
            ItemId = r.ItemId.ToString("N", CultureInfo.InvariantCulture),
            Type = r.Type,
            Note = r.Note,
            CreatedAt = r.CreatedAt,
            UpdatedAt = r.UpdatedAt,
        })],
    };

    private static Guid ParseId(string? text) =>
        Guid.TryParseExact(text, "N", out var id) ? id : throw new FormatException("id non valido");
}
