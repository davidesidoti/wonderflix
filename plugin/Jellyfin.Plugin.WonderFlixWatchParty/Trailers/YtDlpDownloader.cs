using System.ComponentModel;
using System.Diagnostics;
using System.Text.RegularExpressions;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller.MediaEncoding;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>Gli argomenti di yt-dlp: mp4 h264 fino a 720p, 10 minuti e 200 MB al massimo.</summary>
public static class YtDlpArguments
{
    public static IReadOnlyList<string> For(string videoId, string partTemplate, string ffmpegPath) =>
    [
        "--no-playlist",
        "--no-progress",
        "-f", "bv*[height<=720][vcodec^=avc1]+ba[ext=m4a]/b[height<=720][ext=mp4]",
        "--merge-output-format", "mp4",
        "--match-filter", "duration<=600",
        "--max-filesize", "200M",
        "--ffmpeg-location", ffmpegPath,
        "-o", partTemplate,
        "https://www.youtube.com/watch?v=" + videoId,
    ];
}

/// <summary>Scarica i trailer con yt-dlp, passando da <c>&lt;id&gt;.part.*</c> e rinominando a download finito.</summary>
public sealed partial class YtDlpDownloader(
    YtDlpBinary binary,
    IMediaEncoder mediaEncoder,
    IApplicationPaths paths,
    ILogger<YtDlpDownloader> logger) : ITrailerDownloader
{
    private static readonly TimeSpan Timeout = TimeSpan.FromMinutes(3);

    private static readonly string[] UnavailableMarkers =
        ["does not pass filter", "File is larger than max-filesize", "Video unavailable", "Private video", "Sign in to confirm your age"];

    private static readonly string[] OutdatedMarkers = ["Unable to extract", "nsig"];

    public async Task<TrailerDownloadOutcome> DownloadAsync(string videoId, string targetMp4Path, CancellationToken cancellationToken)
    {
        var cache = TrailerPaths.Cache(paths);
        Directory.CreateDirectory(cache);
        try
        {
            var outcome = await AttemptAsync(videoId, cache, targetMp4Path, forceRefresh: false, cancellationToken).ConfigureAwait(false)
                ?? await AttemptAsync(videoId, cache, targetMp4Path, forceRefresh: true, cancellationToken).ConfigureAwait(false);
            return outcome ?? TrailerDownloadOutcome.Failed;
        }
        finally
        {
            DeleteParts(cache, videoId);
        }
    }

    /// <summary>Un tentativo; null = yt-dlp è vecchio, conviene aggiornarlo e riprovare.</summary>
    private async Task<TrailerDownloadOutcome?> AttemptAsync(string videoId, string cache, string target, bool forceRefresh, CancellationToken ct)
    {
        DeleteParts(cache, videoId);
        string exe;
        try
        {
            exe = await binary.EnsureAsync(forceRefresh, ct).ConfigureAwait(false);
        }
        catch (Exception e) when (e is HttpRequestException or IOException or InvalidDataException or UnauthorizedAccessException)
        {
            logger.LogWarning(e, "Trailer {Id}: yt-dlp non disponibile", videoId);
            return TrailerDownloadOutcome.Failed;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            // Il timeout dell'HttpClient arriva come annullamento: non è uno spegnimento.
            logger.LogWarning("Trailer {Id}: scaricare yt-dlp ha superato il tempo massimo", videoId);
            return TrailerDownloadOutcome.Failed;
        }

        var info = new ProcessStartInfo(exe)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        foreach (var arg in YtDlpArguments.For(videoId, Path.Combine(cache, videoId + ".part.%(ext)s"), mediaEncoder.EncoderPath))
        {
            info.ArgumentList.Add(arg);
        }

        string errors;
        int exitCode;
        try
        {
            (exitCode, errors) = await RunAsync(info, ct).ConfigureAwait(false);
        }
        catch (TimeoutException)
        {
            logger.LogWarning("Trailer {Id}: yt-dlp ha superato i {Minutes} minuti", videoId, Timeout.TotalMinutes);
            return TrailerDownloadOutcome.Failed;
        }
        catch (Exception e) when (e is IOException or Win32Exception)
        {
            logger.LogWarning(e, "Trailer {Id}: yt-dlp non parte", videoId);
            return TrailerDownloadOutcome.Failed;
        }

        var part = Path.Combine(cache, videoId + ".part.mp4");
        if (exitCode == 0)
        {
            // yt-dlp esce 0 anche quando --match-filter scarta il video: senza file è "non disponibile".
            if (!File.Exists(part))
            {
                logger.LogInformation("Trailer {Id}: scartato dai limiti (durata)", videoId);
                return TrailerDownloadOutcome.Unavailable;
            }

            try
            {
                File.Move(part, target, overwrite: true);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                logger.LogWarning(e, "Trailer {Id}: non riesco a salvare il file", videoId);
                DeleteParts(cache, videoId);
                return TrailerDownloadOutcome.Failed;
            }

            return TrailerDownloadOutcome.Ok;
        }

        if (UnavailableMarkers.Any(errors.Contains))
        {
            logger.LogInformation("Trailer {Id}: non disponibile ({Tail})", videoId, Tail(errors));
            return TrailerDownloadOutcome.Unavailable;
        }

        if (!forceRefresh && OutdatedMarkers.Any(errors.Contains))
        {
            logger.LogWarning("Trailer {Id}: yt-dlp sembra vecchio, lo aggiorno e riprovo ({Tail})", videoId, Tail(errors));
            return null;
        }

        logger.LogWarning("Trailer {Id}: yt-dlp è uscito con {Code} ({Tail})", videoId, exitCode, Tail(errors));
        return TrailerDownloadOutcome.Failed;
    }

    private static async Task<(int ExitCode, string Errors)> RunAsync(ProcessStartInfo info, CancellationToken ct)
    {
        using var process = Process.Start(info) ?? throw new IOException("yt-dlp non parte");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(Timeout);

        // Le pipe vanno svuotate, altrimenti il processo si blocca; le letture finiscono quando lui chiude.
        var output = process.StandardOutput.ReadToEndAsync(CancellationToken.None);
        var errors = process.StandardError.ReadToEndAsync(CancellationToken.None);
        try
        {
            await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // Solo il nostro processo (e i suoi figli, ffmpeg), mai per nome.
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch (InvalidOperationException)
            {
                // già finito
            }

            ct.ThrowIfCancellationRequested();
            throw new TimeoutException("yt-dlp scaduto");
        }

        await Task.WhenAll(output, errors).ConfigureAwait(false);
        return (process.ExitCode, errors.Result);
    }

    private static void DeleteParts(string cache, string videoId)
    {
        try
        {
            foreach (var file in Directory.EnumerateFiles(cache, videoId + ".part*"))
            {
                File.Delete(file);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // resta lì: il prossimo tentativo riprova a toglierlo
        }
    }

    /// <summary>Le ultime righe di stderr per il log, accorciate e senza URL (quelli di googlevideo portano token).</summary>
    internal static string Tail(string errors)
    {
        var lines = errors.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var tail = UrlPattern().Replace(string.Join(" | ", lines.TakeLast(3)), "<url>");
        return tail.Length > 400 ? tail[^400..] : tail;
    }

    [GeneratedRegex(@"https?://\S+")]
    private static partial Regex UrlPattern();
}
