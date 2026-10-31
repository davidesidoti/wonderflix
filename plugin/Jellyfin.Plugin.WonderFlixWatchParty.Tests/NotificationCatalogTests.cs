using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class NotificationCatalogTests
{
    public static TheoryData<InboxEntry, string, string, string, string> Copy => new()
    {
        {
            new InboxEntry { Type = InboxEntryTypes.RequestPending, Title = "Dune (2021)", RequesterName = "Mario" },
            "it", "Nuova richiesta da approvare", "Dune (2021) — da Mario", "/requests"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.RequestPending, Title = "Dune (2021)", RequesterName = "Mario" },
            "en", "New request to approve", "Dune (2021) — from Mario", "/requests"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.DownloadNeedsYou, Title = "Dune", Reason = "GrabRefused" },
            "it", "Download da sistemare", "Dune — grab rifiutato", "/admin?tab=downloads"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.DownloadNeedsYou, Title = "Dune", Reason = "GrabRefused" },
            "en", "Download needs you", "Dune — grab refused", "/admin?tab=downloads"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.RecoveryBlocked, Scope = InboxScopes.Everyone },
            "it", "Recupero password bloccato", "Troppi tentativi: bloccato per tutti", "/admin?tab=users"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.RecoveryBlocked, Scope = InboxScopes.Everyone },
            "en", "Password recovery blocked", "Too many attempts: blocked for everyone", "/admin?tab=users"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.RecoveryBlocked, Scope = InboxScopes.User, UserName = "mario" },
            "it", "Recupero password bloccato", "Troppi tentativi per mario", "/admin?tab=users"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.RecoveryBlocked, Scope = InboxScopes.User, UserName = "mario" },
            "en", "Password recovery blocked", "Too many attempts for mario", "/admin?tab=users"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.DiskAlmostFull, Percent = 93 },
            "it", "Disco quasi pieno", "Usato il 93% della quota", "/admin?tab=space"
        },
        {
            new InboxEntry { Type = InboxEntryTypes.DiskAlmostFull, Percent = 93 },
            "en", "Disk almost full", "93% of the quota used", "/admin?tab=space"
        },
    };

    [Theory]
    [MemberData(nameof(Copy))]
    public void Message_UsesItalianAndEnglishCopy(InboxEntry entry, string language, string title, string body, string route) =>
        Assert.Equal(new PushMessage(title, body, route), NotificationCatalog.Message(entry, language));

    [Fact]
    public void Message_FallsBackToEnglish()
    {
        var message = NotificationCatalog.Message(new InboxEntry { Type = InboxEntryTypes.RequestApproved, Title = "Dune" }, "de");

        Assert.Equal(new PushMessage("Request approved", "Dune", "/requests"), message);
    }

    [Fact]
    public void Message_RoutesRequestAvailable()
    {
        Assert.Equal("/item/abc", NotificationCatalog.Message(new InboxEntry { Type = InboxEntryTypes.RequestAvailable, ItemId = "abc" }, "it")!.Route);
        Assert.Equal("/requests", NotificationCatalog.Message(new InboxEntry { Type = InboxEntryTypes.RequestAvailable }, "it")!.Route);
    }

    [Fact]
    public void Message_NewTitlesListsTheFirstThreeNames()
    {
        var entry = new InboxEntry
        {
            Type = InboxEntryTypes.NewTitles,
            Movies = [new NewTitleMovie { Name = "Dune" }, new NewTitleMovie { Name = "Heat" }],
            Series = [new NewTitleSeries { Name = "Lost" }, new NewTitleSeries { Name = "Fringe" }],
        };

        Assert.Equal("Dune, Heat, Lost", NotificationCatalog.Message(entry, "en")!.Body);
    }

    [Fact]
    public void Message_MissingFieldsBecomeEmpty()
    {
        var message = NotificationCatalog.Message(new InboxEntry { Type = InboxEntryTypes.Invite }, "en")!;

        Assert.Equal(" invited you to a watch party", message.Title);
        Assert.Equal(string.Empty, message.Body);
    }

    [Fact]
    public void Message_UnknownTypeIsNull() =>
        Assert.Null(NotificationCatalog.Message(new InboxEntry { Type = "Boh" }, "it"));

    [Fact]
    public void EveryTypeHasAMessageAndTheRightAudience()
    {
        Assert.Equal(20, NotificationCatalog.Types.Count);
        Assert.Equal(NotificationCatalog.Types.Count, NotificationCatalog.Types.Distinct().Count());
        foreach (var type in NotificationCatalog.Types)
        {
            Assert.NotNull(NotificationCatalog.Message(new InboxEntry { Type = type }, "it"));
        }

        Assert.Equal(NotificationAudience.Everyone, NotificationCatalog.AudienceOf(InboxEntryTypes.Invite));
        Assert.Equal(NotificationAudience.Approvers, NotificationCatalog.AudienceOf(InboxEntryTypes.RequestPending));
        Assert.Equal(NotificationAudience.Admins, NotificationCatalog.AudienceOf(InboxEntryTypes.ReportPending));
        Assert.Equal(InboxEntryTypes.RequestPending, NotificationCatalog.Types[10]);
        Assert.Equal(InboxEntryTypes.RestartPending, NotificationCatalog.Types[^1]);
    }
}
