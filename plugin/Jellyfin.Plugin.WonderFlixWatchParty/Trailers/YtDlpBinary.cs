using System.Security.Cryptography;
using MediaBrowser.Common.Configuration;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>Tiene aggiornato il binario standalone <c>yt-dlp_linux</c> (YouTube cambia spesso: oltre 7 giorni si riscarica).</summary>
public sealed class YtDlpBinary(
    IHttpClientFactory httpClientFactory,
    IApplicationPaths paths,
    TimeProvider timeProvider,
    ILogger<YtDlpBinary> logger)
{
    /// <summary>Nome dell'HttpClient registrato dal plugin.</summary>
    public const string HttpClientName = "WonderFlixYtDlp";

    public const string FileName = "yt-dlp_linux";

    private const string ReleaseUrl = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/";

    private static readonly TimeSpan MaxAge = TimeSpan.FromDays(7);

    private readonly SemaphoreSlim gate = new(1, 1);

    /// <summary>L'hash atteso di <paramref name="fileName"/> in un SHA2-256SUMS (<c>hash  nome</c> per riga), minuscolo; null se manca.</summary>
    public static string? ExpectedHash(string sha256Sums, string fileName)
    {
        foreach (var line in sha256Sums.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2 && parts[1] == fileName)
            {
                return parts[0].ToLowerInvariant();
            }
        }

        return null;
    }

    /// <summary>Il percorso del binario, scaricandolo se manca, è vecchio o <paramref name="forceRefresh"/>. Se il controllo fallisce lancia e il vecchio binario resta.</summary>
    public async Task<string> EnsureAsync(bool forceRefresh, CancellationToken cancellationToken)
    {
        var path = Path.Combine(TrailerPaths.Bin(paths), FileName);
        if (!forceRefresh && IsFresh(path))
        {
            return path;
        }

        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            // Chi aspettava il semaforo trova il lavoro già fatto.
            if (!forceRefresh && IsFresh(path))
            {
                return path;
            }

            await DownloadAsync(path, cancellationToken).ConfigureAwait(false);
            return path;
        }
        finally
        {
            gate.Release();
        }
    }

    private bool IsFresh(string path) =>
        File.Exists(path) && timeProvider.GetUtcNow() - File.GetLastWriteTimeUtc(path) < MaxAge;

    private async Task DownloadAsync(string path, CancellationToken ct)
    {
        logger.LogInformation("Scarico yt-dlp");
        using var client = httpClientFactory.CreateClient(HttpClientName);
        var sums = await client.GetStringAsync(ReleaseUrl + "SHA2-256SUMS", ct).ConfigureAwait(false);
        var expected = ExpectedHash(sums, FileName)
            ?? throw new InvalidDataException("SHA2-256SUMS di yt-dlp senza " + FileName);
        var bytes = await client.GetByteArrayAsync(ReleaseUrl + FileName, ct).ConfigureAwait(false);
        var actual = Convert.ToHexStringLower(SHA256.HashData(bytes));
        if (actual != expected)
        {
            throw new InvalidDataException("L'hash di yt-dlp non corrisponde: il file scaricato non si usa");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var tmp = path + ".tmp";
        await File.WriteAllBytesAsync(tmp, bytes, ct).ConfigureAwait(false);
        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(tmp, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }

        File.Move(tmp, path, overwrite: true);
        logger.LogInformation("yt-dlp aggiornato ({Bytes} byte)", bytes.Length);
    }
}
