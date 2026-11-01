using Jellyfin.Plugin.WonderFlixWatchParty.Downloads;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ExternalSearchTests
{
    private const string Template = "https://t.example/search.php?keywords={query}&sr=topics";

    [Theory]
    [InlineData("Il cavaliere oscuro (2008)", "https://t.example/search.php?keywords=Il%20cavaliere%20oscuro&sr=topics")]
    [InlineData("A Knight of the Seven Kingdoms · S01E02", "https://t.example/search.php?keywords=A%20Knight%20of%20the%20Seven%20Kingdoms&sr=topics")]
    [InlineData("Dexter · Stagione 3", "https://t.example/search.php?keywords=Dexter&sr=topics")]
    [InlineData("Tom & Jerry", "https://t.example/search.php?keywords=Tom%20%26%20Jerry&sr=topics")]
    public void TheTitleBecomesTheQuery(string title, string expected) =>
        Assert.Equal(expected, ExternalSearch.UrlFor(Template, title));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("https://t.example/search.php")]
    public void NoTemplateOrNoPlaceholderIsNoLink(string? template) =>
        Assert.Null(ExternalSearch.UrlFor(template, "Animals (2025)"));

    [Fact]
    public void TheDefaultIsMirCrew() =>
        Assert.Equal(
            "https://mircrew-releases.org/search.php?keywords=Animals&terms=all&sf=titleonly&sr=topics&sk=t&sd=d",
            ExternalSearch.UrlFor(DownloadDefaults.ExternalSearchUrl, "Animals (2025)"));
}
