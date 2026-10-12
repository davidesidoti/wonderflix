using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class InboxRecommendationTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 12, 20, 0, 0, TimeSpan.Zero));
    private readonly InboxService _inbox;
    private readonly UserRef _mario;
    private readonly UserRef _luigi;
    private readonly UserRef _peach;

    public InboxRecommendationTests()
    {
        _inbox = TestInbox.Create(_server, _folder, _time);
        _mario = _server.AddUser("Mario");
        _luigi = _server.AddUser("Luigi");
        _peach = _server.AddUser("Peach");
        _server.AddSession("s-luigi", _luigi);
    }

    public void Dispose() => _folder.Dispose();

    [Fact]
    public void TheTitleHasTheYearWhenKnown()
    {
        Assert.Equal("Dune (2021)", new RecommendableItem(Guid.NewGuid(), "Dune", 2021).DisplayTitle);
        Assert.Equal("Dune", new RecommendableItem(Guid.NewGuid(), "Dune", null).DisplayTitle);
    }

    [Fact]
    public async Task EachRecipientGetsAnEntryAndItsSessionsAreNotified()
    {
        var dune = _server.AddRecommendable("Dune", 2021);

        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", dune, "da vedere", [_luigi.Id, _peach.Id]);

        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(InboxEntryTypes.Recommendation, entry.Type);
        Assert.Equal(dune.Id.ToString("N"), entry.ItemId);
        Assert.Equal(_mario.Id.ToString("N"), entry.FromUserId);
        Assert.Equal("Mario", entry.FromName);
        Assert.Equal("Dune (2021)", entry.Title);
        Assert.Equal("da vedere", entry.Text);
        Assert.False(entry.Read);
        Assert.Single(_inbox.Get(_peach.Id).Entries);
        Assert.Equal(
            "InboxChanged",
            JsonDocument.Parse(Assert.Single(_server.SentTo("s-luigi"))).RootElement.GetProperty("Type").GetString());
    }

    [Fact]
    public async Task RecommendingAgainUpdatesTheSameEntry()
    {
        var dune = _server.AddRecommendable("Dune");
        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", dune, "da vedere", [_luigi.Id]);
        var first = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        await _inbox.MarkReadAsync(_luigi.Id, first.Seq);
        _time.Advance(TimeSpan.FromHours(1));

        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", dune, null, [_luigi.Id]);

        var entry = Assert.Single(_inbox.Get(_luigi.Id).Entries);
        Assert.Equal(first.Id, entry.Id);
        Assert.True(entry.Seq > first.Seq);
        Assert.False(entry.Read);
        Assert.Null(entry.Text);
        Assert.Equal(_time.GetUtcNow(), entry.CreatedAt);

        // Un altro amico, o un altro titolo: un'altra voce.
        await _inbox.AddRecommendationsAsync(_peach.Id, "Peach", dune, null, [_luigi.Id]);
        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", _server.AddRecommendable("The Bear"), null, [_luigi.Id]);
        Assert.Equal(3, _inbox.Get(_luigi.Id).Entries.Count);
    }

    [Fact]
    public async Task ASendingErrorStaysInTheLog()
    {
        _server.Failing.Add("s-luigi");

        await _inbox.AddRecommendationsAsync(_mario.Id, "Mario", _server.AddRecommendable("Dune"), null, [_luigi.Id]);

        Assert.Single(_inbox.Get(_luigi.Id).Entries);
    }

    [Fact]
    public void TheEntryWritesOnlyItsFields()
    {
        var json = JsonSerializer.Serialize(new InboxEntry
        {
            Id = "a", Seq = 1, Type = InboxEntryTypes.Recommendation, ItemId = "b", FromUserId = "c", FromName = "Mario", Title = "Dune",
        });

        using var document = JsonDocument.Parse(json);
        Assert.Equal("c", document.RootElement.GetProperty("FromUserId").GetString());
        Assert.False(document.RootElement.TryGetProperty("Text", out _));
        Assert.False(document.RootElement.TryGetProperty("GroupId", out _));
    }
}
