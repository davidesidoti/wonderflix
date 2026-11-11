using Jellyfin.Plugin.WonderFlixWatchParty.Trailers;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class YtDlpTests
{
    [Fact]
    public void ArgumentsPinFormatLimitsAndFfmpeg()
    {
        var args = YtDlpArguments.For("25WcssMq1VM", "/c/cache/25WcssMq1VM.part.%(ext)s", "/usr/lib/jellyfin-ffmpeg/ffmpeg");
        Assert.Equal("https://www.youtube.com/watch?v=25WcssMq1VM", args[^1]);
        Assert.Contains("--no-playlist", args);
        Assert.Contains("--no-progress", args);
        Assert.Equal("bv*[height<=720][vcodec^=avc1]+ba[ext=m4a]/b[height<=720][ext=mp4]", After(args, "-f"));
        Assert.Equal("mp4", After(args, "--merge-output-format"));
        Assert.Equal("duration<=600", After(args, "--match-filter"));
        Assert.Equal("200M", After(args, "--max-filesize"));
        Assert.Equal("/usr/lib/jellyfin-ffmpeg/ffmpeg", After(args, "--ffmpeg-location"));
        Assert.Equal("/c/cache/25WcssMq1VM.part.%(ext)s", After(args, "-o"));
    }

    [Fact]
    public void ExpectedHashReadsTheLineOfTheFile() =>
        Assert.Equal("ab12", YtDlpBinary.ExpectedHash("ff00  yt-dlp\nab12  yt-dlp_linux\ncd34  yt-dlp_linux.zip\n", "yt-dlp_linux"));

    [Fact]
    public void ExpectedHashIsNullWhenTheFileIsMissing() =>
        Assert.Null(YtDlpBinary.ExpectedHash("ff00  yt-dlp\n", "yt-dlp_linux"));

    private static string After(IReadOnlyList<string> args, string flag)
    {
        var i = args.ToList().IndexOf(flag);
        Assert.True(i >= 0, flag);
        return args[i + 1];
    }
}
