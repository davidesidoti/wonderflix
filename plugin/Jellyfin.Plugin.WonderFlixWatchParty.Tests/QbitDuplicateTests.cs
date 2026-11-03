using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class QbitDuplicateTests
{
    [Fact]
    public void TheNameOfAPrivateTorrentMessage() =>
        Assert.Equal(
            "Una mamma per amica - Stagione 03 (2000-2016) [COMPLETA] 1080p H265 ITA AAC",
            QbitDuplicate.NameOf("Detected an attempt to add a duplicate torrent. Existing torrent: Una mamma per amica - Stagione 03 (2000-2016) [COMPLETA] 1080p H265 ITA AAC. Result: Trackers cannot be merged because it is a private torrent"));

    [Fact]
    public void TheNameWhenTheMessageHasASource() =>
        Assert.Equal(
            "Mushoku Tensei - Isekai Ittara Honki Dasu - 23 (Amazon Prime CBR 1080p)",
            QbitDuplicate.NameOf("Detected an attempt to add a duplicate torrent. Source: magnet:?xt=urn:btih:abc&dn=x Existing torrent: Mushoku Tensei - Isekai Ittara Honki Dasu - 23 (Amazon Prime CBR 1080p). Result: Trackers are merged from new source"));

    [Fact]
    public void ADotInTheNameIsPartOfTheName() =>
        Assert.Equal(
            "Film.2026. Director's Cut.1080p",
            QbitDuplicate.NameOf("Detected an attempt to add a duplicate torrent. Existing torrent: Film.2026. Director's Cut.1080p. Result: Trackers are merged from new source"));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Torrent added. Existing torrent: A. Result: B")]
    [InlineData("Detected an attempt to add a duplicate torrent. Source: magnet:?xt=urn:btih:abc")]
    [InlineData("Detected an attempt to add a duplicate torrent. Existing torrent: Senza fine")]
    [InlineData("Detected an attempt to add a duplicate torrent. Existing torrent: . Result: x")]
    public void AnythingElseIsNotADuplicate(string? message) => Assert.Null(QbitDuplicate.NameOf(message));
}
