using System.Globalization;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Space;

/// <summary>La quota del seedbox in byte (spec U §6.1).</summary>
public sealed record Quota(long UsedBytes, long LimitBytes);

/// <summary>Legge il file che il cron del seedbox scrive con l'output di <c>quota -w</c> (spec U §6.1).</summary>
public static class QuotaFile
{
    /// <summary>I blocchi di <c>quota</c> sono da 1 KB.</summary>
    private const long BlockBytes = 1024;

    /// <summary>L'ultima riga non vuota: dispositivo, blocchi usati (con un <c>*</c> se sopra quota), quota, limite. Il limite è il campo 3 se maggiore di zero, altrimenti la quota. Null se non si legge.</summary>
    public static Quota? Parse(string? text)
    {
        var line = (text ?? "").Split('\n').LastOrDefault(l => l.Trim().Length > 0);
        if (line is null)
        {
            return null;
        }

        var fields = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 3
            || !TryNumber(fields[1].TrimEnd('*'), out var used)
            || !TryNumber(fields[2], out var quota))
        {
            return null;
        }

        var limit = fields.Length > 3 && TryNumber(fields[3], out var l) ? l : 0;
        var effective = limit > 0 ? limit : quota;
        return effective > 0 ? new Quota(used * BlockBytes, effective * BlockBytes) : null;
    }

    private static bool TryNumber(string s, out long value) =>
        long.TryParse(s, NumberStyles.None, CultureInfo.InvariantCulture, out value);
}
