using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class RequestWebhookTests : IDisposable
{
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new();
    private readonly FakeSeerrClient _seerr = new();
    private readonly FakeSeerrSettings _settings = new();
    private readonly RecordingLogger<RequestWebhookHandler> _logger = new();
    private readonly InboxService _inbox;
    private readonly UserRef _mario;
    private readonly UserRef _davide;
    private readonly RequestWebhookHandler _handler;

    public RequestWebhookTests()
    {
        _mario = _server.AddUser("Mario");
        _davide = _server.AddUser("Davide");
        _seerr.Users.Add(new SeerrUser { Id = 3, Permissions = 34, JellyfinUserId = _davide.Id.ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 24, Permissions = 32, JellyfinUserId = _mario.Id.ToString("N") });
        _inbox = TestInbox.Create(_server, _folder, _time);
        _handler = Handler();
    }

    public void Dispose() => _folder.Dispose();

    private RequestWebhookHandler Handler() => new(
        _settings, new SeerrUserMap(_seerr, _time, NullLogger<SeerrUserMap>.Instance), _server, _inbox, _time, _logger);

    private SeerrWebhookPayload Payload(string type, string? secret = "secret") => new()
    {
        Secret = secret,
        NotificationType = type,
        Subject = "Dune (2021)",
        RequestId = "53",
        MediaType = "movie",
        MediaTmdbId = "438631",
        MediaJellyfinMediaId = "EE39BEF06F503DD0E9DBD20593DF417F",
        RequestedByJellyfinUserId = _mario.Id.ToString("N"),
        RequestedByUsername = "Mario",
    };

    [Fact]
    public async Task AWrongOrMissingSecretIsRejectedAndLoggedOnceAMinute()
    {
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", "sbagliato"), Ct));
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", null), Ct));
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(null, Ct));
        Assert.Single(_logger.Entries);

        _time.Advance(RequestWebhookHandler.RejectedLogEvery);
        await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", "sbagliato"), Ct);
        Assert.Equal(2, _logger.Entries.Count);

        // Senza segreto nella configurazione nessun webhook passa.
        _settings.WebhookSecret = string.Empty;
        Assert.Equal(WebhookResult.Unauthorized, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE", string.Empty), Ct));

        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Null(_handler.LastEvent.At);
    }

    [Fact]
    public async Task AvailableGoesToTheRequesterWithTheLibraryItem()
    {
        _server.AddSession("s1", _mario);

        Assert.Equal(WebhookResult.Accepted, await _handler.HandleAsync(Payload("MEDIA_AVAILABLE"), Ct));

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(InboxEntryTypes.RequestAvailable, entry.Type);
        Assert.Equal(53, entry.RequestId);
        Assert.Equal("movie", entry.MediaType);
        Assert.Equal(438631, entry.TmdbId);
        Assert.Equal("Dune (2021)", entry.Title);
        Assert.Equal("ee39bef06f503dd0e9dbd20593df417f", entry.ItemId);
        Assert.Null(entry.Seasons);
        Assert.Null(entry.RequesterName);
        Assert.Empty(_inbox.Get(_davide.Id).Entries);
        Assert.Single(_server.SentTo("s1"));
        Assert.Equal(_time.GetUtcNow(), _handler.LastEvent.At);
        Assert.Equal("MEDIA_AVAILABLE", _handler.LastEvent.Type);
    }

    [Fact]
    public async Task AvailableForASeriesKeepsTheSeasonsAndARepeatReplacesTheEntry()
    {
        var payload = Payload("MEDIA_AVAILABLE");
        payload.MediaType = "tv";
        payload.Extra = [new SeerrWebhookExtra { Name = "Requested Seasons", Value = "2, 1, x, 2" }];

        await _handler.HandleAsync(payload, Ct);
        await _inbox.MarkReadAsync(_mario.Id, long.MaxValue);
        await _handler.HandleAsync(payload, Ct);

        var entry = Assert.Single(_inbox.Get(_mario.Id).Entries);
        Assert.Equal(new[] { 1, 2 }, entry.Seasons!);
        Assert.False(entry.Read);
    }

    [Fact]
    public async Task PendingGoesToWhoCanApproveButNotToTheRequester()
    {
        await _handler.HandleAsync(Payload("MEDIA_PENDING"), Ct);

        var entry = Assert.Single(_inbox.Get(_davide.Id).Entries);
        Assert.Equal(InboxEntryTypes.RequestPending, entry.Type);
        Assert.Equal("Mario", entry.RequesterName);
        Assert.Null(entry.ItemId);
        Assert.Empty(_inbox.Get(_mario.Id).Entries);

        // L'admin che chiede (se Seerr non approvasse da solo) non avvisa sé stesso.
        var own = Payload("MEDIA_PENDING");
        own.RequestId = "54";
        own.RequestedByJellyfinUserId = _davide.Id.ToString("N");
        await _handler.HandleAsync(own, Ct);
        Assert.Single(_inbox.Get(_davide.Id).Entries);
    }

    [Fact]
    public async Task PendingSkipsManagersThatAreDisabledOrGoneAndSurvivesSeerrDown()
    {
        var off = _server.AddUser("Spento", enabled: false);
        _seerr.Users.Add(new SeerrUser { Id = 1, Permissions = 2, JellyfinUserId = Guid.NewGuid().ToString("N") });
        _seerr.Users.Add(new SeerrUser { Id = 5, Permissions = 16, JellyfinUserId = off.Id.ToString("N") });

        await _handler.HandleAsync(Payload("MEDIA_PENDING"), Ct);

        Assert.Single(_inbox.Get(_davide.Id).Entries);
        Assert.Empty(_inbox.Get(off.Id).Entries);

        _seerr.FailWith = SeerrError.Unavailable;
        var next = Payload("MEDIA_PENDING");
        next.RequestId = "60";
        Assert.Equal(WebhookResult.Accepted, await Handler().HandleAsync(next, Ct));
        Assert.Single(_inbox.Get(_davide.Id).Entries);
    }

    [Fact]
    public async Task IncompleteEventsAndOtherTypesAreAcceptedWithoutEntries()
    {
        var noId = Payload("MEDIA_AVAILABLE");
        noId.RequestId = string.Empty;
        var person = Payload("MEDIA_AVAILABLE");
        person.MediaType = "person";
        var noSubject = Payload("MEDIA_AVAILABLE");
        noSubject.Subject = " ";
        var unknownUser = Payload("MEDIA_AVAILABLE");
        unknownUser.RequestedByJellyfinUserId = Guid.NewGuid().ToString("N");

        foreach (var payload in new[] { noId, person, noSubject, unknownUser, Payload("MEDIA_APPROVED"), Payload("TEST_NOTIFICATION") })
        {
            Assert.Equal(WebhookResult.Accepted, await _handler.HandleAsync(payload, Ct));
        }

        Assert.Empty(_inbox.Get(_mario.Id).Entries);
        Assert.Empty(_inbox.Get(_davide.Id).Entries);
        Assert.Equal("TEST_NOTIFICATION", _handler.LastEvent.Type);
    }
}
