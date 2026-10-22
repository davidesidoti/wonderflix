using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class ReportsHostedServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 21, 21, 0, 0, TimeSpan.Zero));
    private readonly ReportService _reports;

    public ReportsHostedServiceTests()
    {
        _reports = TestReports.Create(_server, _folder, _time, TestInbox.Create(_server, _folder, _time));
    }

    public void Dispose() => _folder.Dispose();

    [Fact]
    public async Task StartLoadsAndTheTimerCleans()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_folder.ReportsFile)!);
        File.WriteAllText(_folder.ReportsFile, "{nope");
        using var hosted = new ReportsHostedService(_reports, _time, NullLogger<ReportsHostedService>.Instance);
        await hosted.StartAsync(CancellationToken.None);
        Assert.True(File.Exists(_folder.ReportsFile + ".bad"));

        // Un utente tolto: la sua segnalazione sparisce dal file al giro dei 5 minuti.
        var luigi = _server.AddUser("Luigi");
        var film = _server.AddMovie("Dune");
        var created = await _reports.CreateAsync(
            luigi.Id, new CreateReportRequest { ItemId = film.Id.ToString("N"), Type = ReportTypes.Other });
        Assert.Equal(HubStatus.Ok, created.Status);
        Assert.Contains(luigi.Id.ToString("N"), File.ReadAllText(_folder.ReportsFile));
        _server.Users.Remove(luigi.Id);
        _time.Advance(ReportsHostedService.StoreInterval);
        Assert.DoesNotContain(luigi.Id.ToString("N"), File.ReadAllText(_folder.ReportsFile));
        await hosted.StopAsync(CancellationToken.None);
    }
}
