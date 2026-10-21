using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class SubtitleServiceTests
{
    private readonly FakeServer _server = new();
    private readonly FakeSubtitleTools _tools = new();
    private readonly RecordingLogger<SubtitleService> _logger = new();
    private readonly SubtitleService _service;
    private readonly UserRef _mario;
    private readonly UserRef _toad;
    private readonly UserRef _peach;
    private readonly UserRef _daisy;
    private readonly Guid _episode = Guid.NewGuid();

    public SubtitleServiceTests()
    {
        _service = new SubtitleService(_tools, _server, _server, _logger);
        _mario = _server.AddUser("Mario");
        _toad = _server.AddUser("Toad", canManageSubtitles: true);
        _peach = _server.AddUser("Peach", isAdmin: true);
        _daisy = _server.AddUser("Daisy", enabled: false, canManageSubtitles: true);
        _tools.Videos.Add(_episode);
    }

    private static string N(Guid id) => id.ToString("N");

    private Task<SubtitleResult<IReadOnlyList<RemoteSubtitleDto>>> Search(UserRef user) =>
        _service.SearchAsync(user.Id, N(_episode), "ita", null, default);

    private Task<SubtitleStatus> Upload(string format, string? data) =>
        _service.UploadAsync(_toad.Id, N(_episode), new UploadSubtitleRequest { Language = "ITA", Format = format, Data = data }, default);

    [Fact]
    public async Task OnlyAdminsAndSubtitleManagersMayUseIt()
    {
        Assert.Equal(SubtitleStatus.Forbidden, (await Search(_mario)).Status);
        Assert.Equal(SubtitleStatus.Forbidden, (await Search(_daisy)).Status);
        Assert.Equal(SubtitleStatus.Forbidden, (await _service.SearchAsync(Guid.Empty, N(_episode), "ita", null, default)).Status);
        Assert.Equal(SubtitleStatus.Ok, (await Search(_toad)).Status);
        Assert.Equal(SubtitleStatus.Ok, (await Search(_peach)).Status);
    }

    [Fact]
    public async Task SearchNormalisesTheLanguage()
    {
        await _service.SearchAsync(_toad.Id, N(_episode), " ITA ", true, default);
        Assert.Equal((_episode, "ita", (bool?)true), Assert.Single(_tools.Searches));
        Assert.Equal(SubtitleStatus.Invalid, (await _service.SearchAsync(_toad.Id, N(_episode), "it", null, default)).Status);
        Assert.Equal(SubtitleStatus.Invalid, (await _service.SearchAsync(_toad.Id, N(_episode), "it1", null, default)).Status);
    }

    [Fact]
    public async Task SearchReturnsTheResults()
    {
        var dto = new RemoteSubtitleDto("open_1", "open", "Ciao", "ita", "srt", 8.5f, 10, true, false, false, false);
        _tools.Results.Add(dto);
        Assert.Equal(dto, Assert.Single((await Search(_toad)).Value!));
    }

    [Fact]
    public async Task OnlyVisibleVideosCanBeUsed()
    {
        var other = Guid.NewGuid();
        Assert.Equal(SubtitleStatus.Invalid, (await _service.SearchAsync(_toad.Id, N(other), "ita", null, default)).Status);
        Assert.Equal(SubtitleStatus.Invalid, (await _service.SearchAsync(_toad.Id, "non un id", "ita", null, default)).Status);
        Assert.Equal(SubtitleStatus.Invalid, (await _service.SearchAsync(_toad.Id, null, "ita", null, default)).Status);
        _server.Unseen.Add((_toad.Id, _episode));
        Assert.Equal(SubtitleStatus.Invalid, (await Search(_toad)).Status);
        _server.Unseen.Clear();
        _tools.LibraryFails = true;
        Assert.Equal(SubtitleStatus.Invalid, (await Search(_toad)).Status);
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Empty(_tools.Searches);
    }

    [Fact]
    public async Task ASearchErrorIsFailed()
    {
        var service = new SubtitleService(new ThrowingSearch(), _server, _server, _logger);
        Assert.Equal(SubtitleStatus.Failed, (await service.SearchAsync(_toad.Id, N(_episode), "ita", null, default)).Status);
    }

    [Fact]
    public async Task AFailedDownloadIsFailed()
    {
        _tools.Failure = new HttpRequestException("provider giù");
        var status = await _service.DownloadAsync(_toad.Id, N(_episode), new DownloadSubtitleRequest { SubtitleId = "open_123" }, default);
        Assert.Equal(SubtitleStatus.Failed, status);
        var warning = Assert.Single(_logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Contains("open", warning.Message);
        Assert.DoesNotContain("123", warning.Message);
    }

    [Fact]
    public async Task AHostileSubtitleIdNeverReachesTheLog()
    {
        _tools.Failure = new HttpRequestException("provider giù");
        var hostile = new string('x', 100) + "\nFORGED line_1";
        Assert.Equal(SubtitleStatus.Failed, await _service.DownloadAsync(_toad.Id, N(_episode), new DownloadSubtitleRequest { SubtitleId = hostile }, default));
        var warning = Assert.Single(_logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.DoesNotContain("xxxxx", warning.Message);
        Assert.DoesNotContain("FORGED", warning.Message);
        Assert.DoesNotContain("\n", warning.Message);
        Assert.Contains("unknown", warning.Message);
    }

    [Fact]
    public async Task AnOversizedSubtitleIdIsInvalid()
    {
        var id = "open_" + new string('a', SubtitleService.MaxSubtitleIdLength);
        Assert.Equal(SubtitleStatus.Invalid, await _service.DownloadAsync(_toad.Id, N(_episode), new DownloadSubtitleRequest { SubtitleId = id }, default));
        Assert.Empty(_tools.Downloads);
    }

    [Fact]
    public async Task ADownloadIsPassedOn()
    {
        var status = await _service.DownloadAsync(_peach.Id, N(_episode), new DownloadSubtitleRequest { SubtitleId = "open_123" }, default);
        Assert.Equal(SubtitleStatus.Ok, status);
        Assert.Equal((_episode, "open_123"), Assert.Single(_tools.Downloads));
    }

    [Fact]
    public async Task DownloadNeedsASubtitleId()
    {
        Assert.Equal(SubtitleStatus.Invalid, await _service.DownloadAsync(_toad.Id, N(_episode), null, default));
        Assert.Equal(SubtitleStatus.Invalid, await _service.DownloadAsync(_toad.Id, N(_episode), new DownloadSubtitleRequest(), default));
        Assert.Equal(SubtitleStatus.Invalid, await _service.DownloadAsync(_toad.Id, N(_episode), new DownloadSubtitleRequest { SubtitleId = "" }, default));
        Assert.Empty(_tools.Downloads);
    }

    [Fact]
    public async Task AFailedUploadIsFailed()
    {
        _tools.Failure = new IOException("disco");
        Assert.Equal(SubtitleStatus.Failed, await Upload("srt", Convert.ToBase64String([1])));
        Assert.Contains(_logger.Entries, e => e.Level == LogLevel.Warning);
    }

    [Fact]
    public async Task UploadChecksFormatSizeAndBase64()
    {
        Assert.Equal(SubtitleStatus.Ok, await Upload("SRT", Convert.ToBase64String("1\n00:00:01,000 --> 00:00:02,000\nCiao\n"u8.ToArray())));
        Assert.Equal(("ita", "srt"), (_tools.Uploads[0].Upload.Language, _tools.Uploads[0].Upload.Format));
        Assert.Equal(SubtitleStatus.Invalid, await Upload("exe", Convert.ToBase64String([1])));
        Assert.Equal(SubtitleStatus.Invalid, await Upload("srt", "non base64!"));
        Assert.Equal(SubtitleStatus.Invalid, await Upload("srt", ""));
        Assert.Equal(SubtitleStatus.Invalid, await Upload("srt", Convert.ToBase64String(new byte[SubtitleService.MaxUploadBytes + 1])));
        Assert.Equal(SubtitleStatus.Ok, await Upload("srt", Convert.ToBase64String(new byte[SubtitleService.MaxUploadBytes])));
    }

    [Fact]
    public async Task UploadCarriesTheFlagsAndTheBytes()
    {
        var request = new UploadSubtitleRequest { Language = "eng", Format = "vtt", IsForced = true, IsHearingImpaired = true, Data = Convert.ToBase64String([1, 2, 3]) };
        Assert.Equal(SubtitleStatus.Ok, await _service.UploadAsync(_toad.Id, N(_episode), request, default));
        var (itemId, upload) = Assert.Single(_tools.Uploads);
        Assert.Equal(_episode, itemId);
        Assert.Equal("eng", upload.Language);
        Assert.True(upload.IsForced && upload.IsHearingImpaired);
        Assert.Equal(new byte[] { 1, 2, 3 }, upload.Data);
        Assert.Equal(SubtitleStatus.Invalid, await _service.UploadAsync(_toad.Id, N(_episode), null, default));
    }

    private sealed class ThrowingSearch : ISubtitleTools
    {
        public bool IsVideo(Guid itemId) => true;

        public Task<IReadOnlyList<RemoteSubtitleDto>> SearchAsync(Guid itemId, string language, bool? perfectMatch, CancellationToken cancellationToken) =>
            throw new HttpRequestException("provider giù");

        public Task DownloadAsync(Guid itemId, string subtitleId, CancellationToken cancellationToken) => Task.CompletedTask;

        public Task UploadAsync(Guid itemId, SubtitleUpload upload, CancellationToken cancellationToken) => Task.CompletedTask;
    }
}
