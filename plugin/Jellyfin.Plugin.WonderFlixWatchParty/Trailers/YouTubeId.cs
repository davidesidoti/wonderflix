using System.Text.RegularExpressions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Trailers;

/// <summary>L'id di un video YouTube (11 caratteri) da un indirizzo.</summary>
public static partial class YouTubeId
{
    /// <summary>
    /// L'id da watch?v=, youtu.be/, /embed/ (anche youtube-nocookie.com e m.youtube.com);
    /// null per ogni altro indirizzo o id non valido.
    /// </summary>
    public static string? FromUrl(string? url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
        {
            return null;
        }

        var host = uri.Host.ToLowerInvariant();
        string? id = null;
        if (host == "youtu.be")
        {
            id = FirstSegment(uri.AbsolutePath);
        }
        else if (host is "youtube.com" or "www.youtube.com" or "m.youtube.com" or "youtube-nocookie.com" or "www.youtube-nocookie.com")
        {
            if (uri.AbsolutePath.StartsWith("/embed/", StringComparison.Ordinal))
            {
                id = FirstSegment(uri.AbsolutePath["/embed/".Length..]);
            }
            else if (uri.AbsolutePath == "/watch")
            {
                id = uri.Query.TrimStart('?').Split('&')
                    .Where(p => p.StartsWith("v=", StringComparison.Ordinal))
                    .Select(p => p[2..])
                    .FirstOrDefault();
            }
        }

        return id is not null && IsValid(id) ? id : null;
    }

    public static bool IsValid(string id) => ValidId().IsMatch(id);

    private static string FirstSegment(string path) => path.Trim('/').Split('/')[0];

    [GeneratedRegex("^[A-Za-z0-9_-]{11}$")]
    private static partial Regex ValidId();
}
