using System.Net;
using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class DiscordBotClientTests
{
    private const string ChannelsPath = "/api/v10/users/@me/channels";
    private static readonly CancellationToken Ct = CancellationToken.None;
    private readonly FakeDiscordHttp _http = new();
    private readonly FakeAccountSettings _settings = new();
    private readonly RecordingLogger<DiscordBotClient> _logger = new();

    private DiscordBotClient Client(TimeSpan? timeout = null) =>
        new(_http, _settings, _logger) { Timeout = timeout ?? DiscordBotClient.DefaultTimeout };

    private static HttpResponseMessage Json(HttpStatusCode status, string json) => FakeDiscordHttp.Json(status, json);

    // Il canale DM si apre sempre; il messaggio risponde con status e body.
    private void MessagesAnswer(HttpStatusCode status, string body) =>
        _http.Respond = (request, _) => Task.FromResult(request.RequestUri!.AbsolutePath == ChannelsPath
            ? Json(HttpStatusCode.OK, """{"id":"333333333333333333"}""")
            : Json(status, body));

    [Fact]
    public async Task FindsTheExactNameAmongThePrefixMatches()
    {
        _http.Respond = (_, _) => Task.FromResult(Json(
            HttpStatusCode.OK,
            """[{"user":{"id":"111111111111111111","username":"mario64"}},{"user":{"id":"222222222222222222","username":"Mario"}}]"""));

        var lookup = await Client().FindMemberAsync("mario", Ct);

        Assert.Equal(new DiscordMember("222222222222222222", "Mario"), lookup.Member);
        var request = Assert.Single(_http.Requests);
        Assert.Equal(HttpMethod.Get, request.Method);
        Assert.Equal("/api/v10/guilds/123456789012345678/members/search?query=mario&limit=10", request.PathAndQuery);
        Assert.Equal("Bot bot-token", request.Authorization);
        Assert.StartsWith("DiscordBot (https://github.com/davidesidoti/wonderflix, ", request.UserAgent);
        Assert.Equal(DiscordBotClient.HttpClientName, _http.LastClientName);
    }

    [Fact]
    public async Task OnlyPrefixMatchesIsNotFound()
    {
        _http.Respond = (_, _) => Task.FromResult(Json(
            HttpStatusCode.OK, """[{"user":{"id":"111111111111111111","username":"mario64"}}]"""));

        var lookup = await Client().FindMemberAsync("mario", Ct);

        Assert.Null(lookup.Member);
        Assert.False(lookup.Failed);
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, """{"code":50001,"message":"Missing Access"}""")]
    [InlineData(HttpStatusCode.OK, "non è json")]
    [InlineData(HttpStatusCode.OK, """{"user":{}}""")]
    public async Task SearchErrorsAreFailures(HttpStatusCode status, string body)
    {
        _http.Respond = (_, _) => Task.FromResult(Json(status, body));

        Assert.True((await Client().FindMemberAsync("mario", Ct)).Failed);
    }

    [Fact]
    public async Task ANetworkErrorIsAFailure()
    {
        _http.Respond = (_, _) => throw new HttpRequestException("rete");

        Assert.True((await Client().FindMemberAsync("mario", Ct)).Failed);
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));
        Assert.Equal(DiscordCheck.Failed, await Client().CheckAsync(Ct));
    }

    [Fact]
    public async Task ADirectMessageOpensTheChannelThenWrites()
    {
        MessagesAnswer(HttpStatusCode.OK, "{}");

        Assert.Equal(SendOutcome.Sent, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));

        Assert.Equal(2, _http.Requests.Count);
        Assert.Equal(HttpMethod.Post, _http.Requests[0].Method);
        Assert.Equal(ChannelsPath, _http.Requests[0].PathAndQuery);
        Assert.Equal("""{"recipient_id":"222222222222222222"}""", _http.Requests[0].Body);
        Assert.Equal(HttpMethod.Post, _http.Requests[1].Method);
        Assert.Equal("/api/v10/channels/333333333333333333/messages", _http.Requests[1].PathAndQuery);
        Assert.Equal("""{"content":"Codice 654321"}""", _http.Requests[1].Body);
    }

    [Fact]
    public async Task ClosedDirectMessagesAreDmClosed()
    {
        MessagesAnswer(HttpStatusCode.Forbidden, """{"code":50007,"message":"Cannot send messages to this user"}""");

        Assert.Equal(SendOutcome.DmClosed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));
    }

    [Theory]
    [InlineData(HttpStatusCode.TooManyRequests, """{"retry_after":1.5,"global":false}""")]
    [InlineData(HttpStatusCode.Forbidden, """{"code":50001,"message":"Missing Access"}""")]
    [InlineData(HttpStatusCode.InternalServerError, "")]
    public async Task OtherErrorsAreFailures(HttpStatusCode status, string body)
    {
        MessagesAnswer(status, body);
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));

        // Anche quando non si apre il canale.
        _http.Respond = (_, _) => Task.FromResult(Json(status, body));
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct));
    }

    [Fact]
    public async Task NoAnswerInTimeIsAFailure()
    {
        _http.Respond = async (_, ct) =>
        {
            await Task.Delay(Timeout.Infinite, ct);
            return Json(HttpStatusCode.OK, "{}");
        };

        Assert.Equal(
            SendOutcome.Failed,
            await Client(TimeSpan.FromMilliseconds(50)).SendDmAsync("222222222222222222", "Codice 654321", Ct));
    }

    [Fact]
    public async Task CheckReadsTheBotThenTheServer()
    {
        Assert.Equal(DiscordCheck.Ok, await Client().CheckAsync(Ct));

        Assert.Equal(
            new[] { "/api/v10/users/@me", "/api/v10/guilds/123456789012345678" },
            _http.Requests.Select(r => r.PathAndQuery));
    }

    [Theory]
    [InlineData("/api/v10/users/@me", HttpStatusCode.Unauthorized, DiscordCheck.Invalid)]
    [InlineData("/api/v10/guilds/123456789012345678", HttpStatusCode.NotFound, DiscordCheck.Invalid)]
    [InlineData("/api/v10/guilds/123456789012345678", HttpStatusCode.Forbidden, DiscordCheck.Invalid)]
    [InlineData("/api/v10/users/@me", HttpStatusCode.BadGateway, DiscordCheck.Failed)]
    public async Task CheckErrors(string failing, HttpStatusCode status, DiscordCheck expected)
    {
        _http.Respond = (request, _) => Task.FromResult(request.RequestUri!.AbsolutePath == failing
            ? Json(status, "{}")
            : Json(HttpStatusCode.OK, "{}"));

        Assert.Equal(expected, await Client().CheckAsync(Ct));
    }

    [Fact]
    public async Task WithoutSettingsOrWithABadIdNothingIsSent()
    {
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("non-un-id", "x", Ct));
        _settings.DiscordBotToken = " ";

        Assert.True((await Client().FindMemberAsync("mario", Ct)).Failed);
        Assert.Equal(SendOutcome.Failed, await Client().SendDmAsync("222222222222222222", "x", Ct));
        Assert.Equal(DiscordCheck.Invalid, await Client().CheckAsync(Ct));
        Assert.Empty(_http.Requests);
    }

    [Fact]
    public async Task TheTokenAndTheQueryNeverGoToTheLog()
    {
        _http.Respond = (_, _) => Task.FromResult(Json(HttpStatusCode.Forbidden, """{"code":50001,"message":"Missing Access"}"""));

        await Client().FindMemberAsync("mario", Ct);
        await Client().SendDmAsync("222222222222222222", "Codice 654321", Ct);

        Assert.NotEmpty(_logger.Entries);
        Assert.All(_logger.Entries, e =>
        {
            Assert.DoesNotContain("bot-token", e.Message);
            Assert.DoesNotContain("query=", e.Message);
            Assert.DoesNotContain("654321", e.Message);
        });
    }
}
