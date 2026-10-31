using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class PushServiceTests : IDisposable
{
    private readonly TempFolder _folder = new();
    private readonly FakeServer _server = new();
    private readonly FakePushTransport _transport = new();
    private readonly FakeDeviceAccess _devices = new();
    private readonly FailingUsers _users;
    private readonly PushService _push;
    private readonly UserRef _mario;

    // Le chiavi private dei browser finti, per endpoint: servono a decifrare.
    private readonly Dictionary<string, (ECDiffieHellman Key, byte[] Auth)> _browsers = [];

    public PushServiceTests()
    {
        _users = new FailingUsers(_server);
        _push = new PushService(
            new NotificationStore(_folder.NotificationsFile, NullLogger<NotificationStore>.Instance),
            new VapidKeyProvider(() => null, () => { }),
            _transport,
            _devices,
            _users,
            TimeProvider.System,
            NullLogger<PushService>.Instance);
        _mario = _server.AddUser("Mario");
    }

    public void Dispose()
    {
        foreach (var (key, _) in _browsers.Values)
        {
            key.Dispose();
        }

        _folder.Dispose();
    }

    /// <summary>Gli utenti di FakeServer, con una lettura che lancia per gli utenti in <see cref="Failing"/>.</summary>
    private sealed class FailingUsers(FakeServer server) : IUserDirectory
    {
        public HashSet<Guid> Failing { get; } = [];

        public IReadOnlyList<UserRef> GetUsers() => server.GetUsers();

        public UserRef? GetUser(Guid userId) =>
            Failing.Contains(userId) ? throw new InvalidOperationException("database non disponibile") : server.GetUser(userId);
    }

    private static InboxEntry Entry(string type = InboxEntryTypes.Announcement) =>
        new() { Id = "voce-1", Type = type, Text = "Stasera si guarda Dune", Percent = 92 };

    /// <summary>Iscrive un browser finto con chiavi vere e dà accesso al suo dispositivo.</summary>
    private string Subscribe(UserRef user, string name, string? language = "it", string? device = null)
    {
        var key = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
        var auth = RandomNumberGenerator.GetBytes(16);
        var endpoint = $"https://fcm.googleapis.com/fcm/send/{name}";
        _browsers[endpoint] = (key, auth);
        var request = new SubscribeRequest
        {
            Endpoint = endpoint, P256dh = Base64Url.Encode(Point(key)), Auth = Base64Url.Encode(auth), Language = language,
        };
        Assert.Equal(HubStatus.Ok, _push.Subscribe(user.Id, device ?? $"dev-{name}", request));
        _devices.Allow(user.Id, device ?? $"dev-{name}");
        return endpoint;
    }

    private Task Deliver(UserRef user, InboxEntry entry) => _push.DeliverAsync([(user.Id, entry)]);

    private static byte[] Point(ECDiffieHellman key)
    {
        var q = key.ExportParameters(false).Q;
        return [0x04, .. q.X!, .. q.Y!];
    }

    // Il contrario di WebPushCrypto.Encrypt (RFC 8291), dalla parte del browser.
    private JsonElement Decrypt(SentPush sent)
    {
        var (key, auth) = _browsers[sent.Sub.Endpoint];
        var body = sent.Body;
        var salt = body[..16];
        var asPublic = body[21..86];
        using var server = ECDiffieHellman.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = asPublic[1..33], Y = asPublic[33..] },
        });
        var secret = key.DeriveRawSecretAgreement(server.PublicKey);
        var prkKey = HKDF.Extract(HashAlgorithmName.SHA256, secret, auth);
        var ikm = HKDF.Expand(HashAlgorithmName.SHA256, prkKey, 32, [.. "WebPush: info\0"u8, .. Point(key), .. asPublic]);
        var prk = HKDF.Extract(HashAlgorithmName.SHA256, ikm, salt);
        var cek = HKDF.Expand(HashAlgorithmName.SHA256, prk, 16, "Content-Encoding: aes128gcm\0"u8.ToArray());
        var nonce = HKDF.Expand(HashAlgorithmName.SHA256, prk, 12, "Content-Encoding: nonce\0"u8.ToArray());
        var plain = new byte[body.Length - 86 - 16];
        using var aes = new AesGcm(cek, 16);
        aes.Decrypt(nonce, body[86..^16], body[^16..], plain);
        Assert.Equal(0x02, plain[^1]);
        return JsonDocument.Parse(Encoding.UTF8.GetString(plain[..^1])).RootElement;
    }

    [Fact]
    public async Task Deliver_SendsToEveryDeviceOfUser()
    {
        var phone = Subscribe(_mario, "telefono");
        var laptop = Subscribe(_mario, "portatile");

        await Deliver(_mario, Entry());

        Assert.Equal([phone, laptop], _transport.Sent.Select(s => s.Sub.Endpoint).OrderDescending());
        Assert.All(_transport.Sent, s => Assert.StartsWith("vapid t=", s.Authorization));
    }

    [Fact]
    public async Task Deliver_SkipsDisabledType()
    {
        Subscribe(_mario, "telefono");
        Assert.True(_push.SetEnabled(_mario.Id, InboxEntryTypes.Announcement, false, isAdmin: false, isApprover: false));

        await Deliver(_mario, Entry());

        Assert.Empty(_transport.Sent);
    }

    [Fact]
    public async Task Deliver_AdminTypeToUserNoLongerAdmin_NotSent()
    {
        Subscribe(_mario, "telefono");

        await Deliver(_mario, Entry(InboxEntryTypes.DiskAlmostFull));

        Assert.Empty(_transport.Sent);
        _server.Users[_mario.Id] = _mario with { IsAdmin = true };
        await Deliver(_mario, Entry(InboxEntryTypes.DiskAlmostFull));
        Assert.Single(_transport.Sent);
    }

    [Fact]
    public async Task Deliver_DisabledUser_NotSentAndSubscriptionsKept()
    {
        Subscribe(_mario, "telefono");
        _server.Users[_mario.Id] = _mario with { Enabled = false };

        await Deliver(_mario, Entry());

        Assert.Empty(_transport.Sent);
        _server.Users[_mario.Id] = _mario;
        await Deliver(_mario, Entry());
        Assert.Single(_transport.Sent);
    }

    [Fact]
    public async Task Deliver_DeviceWithoutAccess_NotSentAndSubscriptionRemoved()
    {
        Subscribe(_mario, "telefono");
        var laptop = Subscribe(_mario, "portatile");
        _devices.Revoke(_mario.Id, "dev-telefono");

        await Deliver(_mario, Entry());

        Assert.Equal(laptop, Assert.Single(_transport.Sent).Sub.Endpoint);
        _devices.Allow(_mario.Id, "dev-telefono");
        _transport.Sent.Clear();
        await Deliver(_mario, Entry());
        Assert.Equal(laptop, Assert.Single(_transport.Sent).Sub.Endpoint);
        Assert.DoesNotContain("telefono", File.ReadAllText(_folder.NotificationsFile), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Deliver_GoneRemovesOnlyThatSubscription()
    {
        var phone = Subscribe(_mario, "telefono");
        var laptop = Subscribe(_mario, "portatile");
        _transport.ResultFor[phone] = PushResult.Gone;

        await Deliver(_mario, Entry());

        Assert.Equal(2, _transport.Sent.Count);
        _transport.Sent.Clear();
        await Deliver(_mario, Entry());
        Assert.Equal(laptop, Assert.Single(_transport.Sent).Sub.Endpoint);
    }

    [Fact]
    public async Task Deliver_FailedKeepsSubscriptionAndOthersStillSent()
    {
        var phone = Subscribe(_mario, "telefono");
        Subscribe(_mario, "portatile");
        _transport.ResultFor[phone] = PushResult.Failed;

        await Deliver(_mario, Entry());
        await Deliver(_mario, Entry());

        Assert.Equal(4, _transport.Sent.Count);
    }

    [Fact]
    public async Task Deliver_BrokenSubscriptionDoesNotStopTheOthers()
    {
        // 65 byte con il prefisso giusto ma fuori dalla curva: Encrypt lancia.
        byte[] offCurve = [0x04, .. new byte[64]];
        Assert.Equal(HubStatus.Ok, _push.Subscribe(_mario.Id, "dev-rotto", new SubscribeRequest
        {
            Endpoint = "https://fcm.googleapis.com/fcm/send/rotto", P256dh = Base64Url.Encode(offCurve),
            Auth = Base64Url.Encode(new byte[16]), Language = "it",
        }));
        _devices.Allow(_mario.Id, "dev-rotto");
        var phone = Subscribe(_mario, "telefono");

        await Deliver(_mario, Entry());

        Assert.Equal(phone, Assert.Single(_transport.Sent).Sub.Endpoint);
    }

    [Fact]
    public async Task Deliver_PayloadHasNoSecrets()
    {
        Subscribe(_mario, "telefono");

        await Deliver(_mario, Entry());

        var payload = Decrypt(Assert.Single(_transport.Sent));
        Assert.Equal(["body", "route", "tag", "title"], payload.EnumerateObject().Select(p => p.Name).Order());
        Assert.Equal("voce-1", payload.GetProperty("tag").GetString());
        Assert.Equal("/inbox", payload.GetProperty("route").GetString());
        Assert.Equal("Stasera si guarda Dune", payload.GetProperty("body").GetString());
    }

    [Fact]
    public async Task Deliver_UsesSubscriptionLanguage()
    {
        var phone = Subscribe(_mario, "telefono", "it");
        var laptop = Subscribe(_mario, "portatile", "fr");

        await Deliver(_mario, Entry());

        var titles = _transport.Sent.ToDictionary(s => s.Sub.Endpoint, s => Decrypt(s).GetProperty("title").GetString());
        Assert.Equal("Annuncio", titles[phone]);
        Assert.Equal("Announcement", titles[laptop]);
    }

    [Fact]
    public async Task Deliver_UnknownTypeNotSent()
    {
        Subscribe(_mario, "telefono");

        await Deliver(_mario, Entry("Sconosciuto"));

        Assert.Empty(_transport.Sent);
    }

    [Theory]
    [InlineData("http://fcm.googleapis.com/x", 65, 16)]
    [InlineData("fcm.googleapis.com/x", 65, 16)]
    [InlineData("https://127.0.0.1/x", 65, 16)]
    [InlineData("https://evil.example/x", 65, 16)]
    [InlineData("https://evilgoogleapis.com/x", 65, 16)]
    [InlineData("https://fcm.googleapis.com/x", 33, 16)]
    [InlineData("https://fcm.googleapis.com/x", 65, 8)]
    public void Subscribe_RejectsBadEndpointOrKeys(string endpoint, int p256dhBytes, int authBytes)
    {
        var request = new SubscribeRequest
        {
            Endpoint = endpoint, P256dh = Base64Url.Encode(new byte[p256dhBytes]), Auth = Base64Url.Encode(new byte[authBytes]),
        };

        Assert.Equal(HubStatus.Invalid, _push.Subscribe(_mario.Id, "dev", request));
    }

    [Fact]
    public void Subscribe_RejectsEndpointLongerThan2048()
    {
        SubscribeRequest Request(int length) => new()
        {
            Endpoint = "https://fcm.googleapis.com/" + new string('x', length - "https://fcm.googleapis.com/".Length),
            P256dh = Base64Url.Encode(new byte[65]),
            Auth = Base64Url.Encode(new byte[16]),
        };

        Assert.Equal(HubStatus.Ok, _push.Subscribe(_mario.Id, "dev", Request(PushService.MaxEndpointLength)));
        Assert.Equal(HubStatus.Invalid, _push.Subscribe(_mario.Id, "dev", Request(PushService.MaxEndpointLength + 1)));
    }

    [Fact]
    public async Task Cleanup_DropsSubscriptionsOfDeletedUsers()
    {
        var luigi = _server.AddUser("Luigi");
        Subscribe(_mario, "telefono");
        Subscribe(luigi, "telefono");
        _server.Users.Remove(luigi.Id);

        Assert.Equal(1, _push.Cleanup());
        Assert.Equal(0, _push.Cleanup());

        _server.Users[luigi.Id] = luigi;
        await Deliver(luigi, Entry());
        await Deliver(_mario, Entry());
        Assert.Equal(_mario.Id, Assert.Single(_transport.Sent).Sub.UserId);
    }

    [Fact]
    public void Subscribe_RejectsKeysThatAreNotBase64Url()
    {
        var request = new SubscribeRequest { Endpoint = "https://fcm.googleapis.com/x", P256dh = "@@@@", Auth = "!!" };

        Assert.Equal(HubStatus.Invalid, _push.Subscribe(_mario.Id, "dev", request));
        Assert.Equal(HubStatus.Invalid, _push.Subscribe(_mario.Id, "dev", new SubscribeRequest()));
    }

    [Fact]
    public async Task Unsubscribe_RemovesOnlyTheCallersSubscription()
    {
        var phone = Subscribe(_mario, "telefono");
        var luigi = _server.AddUser("Luigi");
        Subscribe(luigi, "telefono");

        _push.Unsubscribe(_mario.Id, phone);
        await Deliver(_mario, Entry());
        await Deliver(luigi, Entry());

        Assert.Equal(luigi.Id, Assert.Single(_transport.Sent).Sub.UserId);
    }

    [Theory]
    [InlineData("https://web.push.apple.com/x")]
    [InlineData("https://fcm.googleapis.com/fcm/send/x")]
    [InlineData("https://wns2-par02p.notify.windows.com/w/?token=x")]
    [InlineData("https://updates.push.services.mozilla.com/wpush/v2/x")]
    [InlineData("https://FCM.GoogleAPIs.com/x")]
    public void Subscribe_AcceptsKnownPushServices(string endpoint)
    {
        var request = new SubscribeRequest
        {
            Endpoint = endpoint, P256dh = Base64Url.Encode(new byte[65]), Auth = Base64Url.Encode(new byte[16]),
        };

        Assert.Equal(HubStatus.Ok, _push.Subscribe(_mario.Id, "dev", request));
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(null)]
    public void Subscribe_WithoutDeviceIsInvalid(string? device)
    {
        var request = new SubscribeRequest
        {
            Endpoint = "https://fcm.googleapis.com/x", P256dh = Base64Url.Encode(new byte[65]), Auth = Base64Url.Encode(new byte[16]),
        };

        Assert.Equal(HubStatus.Invalid, _push.Subscribe(_mario.Id, device, request));
    }

    [Theory]
    [InlineData("it", "Annuncio")]
    [InlineData("it-IT", "Annuncio")]
    [InlineData("IT", "Annuncio")]
    [InlineData("it_CH", "Annuncio")]
    [InlineData("en-US", "Announcement")]
    [InlineData("ita", "Announcement")]
    [InlineData(null, "Announcement")]
    public async Task Subscribe_LanguageByPrefix(string? language, string title)
    {
        Subscribe(_mario, "telefono", language);

        await Deliver(_mario, Entry());

        Assert.Equal(title, Decrypt(Assert.Single(_transport.Sent)).GetProperty("title").GetString());
    }

    [Fact]
    public async Task Deliver_AccessCheckThatThrowsDoesNotStopTheOthers()
    {
        Subscribe(_mario, "telefono");
        var laptop = Subscribe(_mario, "portatile");
        _devices.Failing.Add("dev-telefono");
        var luigi = _server.AddUser("Luigi");
        var luigiPhone = Subscribe(luigi, "luigi");

        await _push.DeliverAsync([(_mario.Id, Entry()), (luigi.Id, Entry())]);

        Assert.Equal([luigiPhone, laptop], _transport.Sent.Select(s => s.Sub.Endpoint).Order());
    }

    [Fact]
    public async Task Deliver_UserLookupThatThrowsDoesNotStopTheOtherEntries()
    {
        var luigi = _server.AddUser("Luigi");
        var luigiPhone = Subscribe(luigi, "luigi");
        Subscribe(_mario, "telefono");
        _users.Failing.Add(_mario.Id);

        await _push.DeliverAsync([(_mario.Id, Entry()), (luigi.Id, Entry())]);

        Assert.Equal(luigiPhone, Assert.Single(_transport.Sent).Sub.Endpoint);
    }

    [Fact]
    public async Task Deliver_NoAccess_KeepsSubscriptionRecreatedMeanwhile()
    {
        var phone = Subscribe(_mario, "telefono", device: "vecchio");
        _devices.Revoke(_mario.Id, "vecchio");
        // Durante il controllo il browser si iscrive di nuovo da una sessione nuova.
        _devices.BeforeCheck = (_, device) =>
        {
            if (device == "vecchio")
            {
                Subscribe(_mario, "telefono", device: "nuovo");
            }
        };

        await Deliver(_mario, Entry());
        _devices.BeforeCheck = null;
        await Deliver(_mario, Entry());

        var sent = Assert.Single(_transport.Sent);
        Assert.Equal((phone, "nuovo"), (sent.Sub.Endpoint, sent.Sub.DeviceId));
    }

    [Fact]
    public async Task Deliver_Gone_KeepsSubscriptionRecreatedMeanwhile()
    {
        var phone = Subscribe(_mario, "telefono");
        _transport.ResultFor[phone] = PushResult.Gone;
        // Mentre il servizio push risponde, il browser si iscrive di nuovo.
        _transport.BeforeResult = _ =>
        {
            _transport.BeforeResult = null;
            Subscribe(_mario, "telefono");
        };

        await Deliver(_mario, Entry());
        _transport.ResultFor.Clear();
        _transport.Sent.Clear();
        await Deliver(_mario, Entry());

        Assert.Equal(phone, Assert.Single(_transport.Sent).Sub.Endpoint);
    }

    [Fact]
    public void Get_ListsOnlyVisibleTypesInCatalogueOrder()
    {
        var plain = _push.Get(_mario.Id, isAdmin: false, isApprover: false);
        var approver = _push.Get(_mario.Id, isAdmin: false, isApprover: true);
        var admin = _push.Get(_mario.Id, isAdmin: true, isApprover: false);

        Assert.NotEmpty(plain.VapidPublicKey);
        Assert.DoesNotContain(plain.Types, t => t.Type is InboxEntryTypes.RequestPending or InboxEntryTypes.DiskAlmostFull);
        Assert.Contains(approver.Types, t => t.Type == InboxEntryTypes.RequestPending);
        Assert.DoesNotContain(approver.Types, t => t.Type == InboxEntryTypes.DiskAlmostFull);
        Assert.Contains(admin.Types, t => t.Type == InboxEntryTypes.DiskAlmostFull);
        Assert.Equal(NotificationCatalog.Types.Where(admin.Types.Select(t => t.Type).Contains), admin.Types.Select(t => t.Type));
        Assert.All(plain.Types, t => Assert.True(t.Enabled));
    }

    [Fact]
    public void SetEnabled_RefusesUnknownOrHiddenTypes()
    {
        Assert.False(_push.SetEnabled(_mario.Id, "Sconosciuto", false, isAdmin: true, isApprover: true));
        Assert.False(_push.SetEnabled(_mario.Id, InboxEntryTypes.DiskAlmostFull, false, isAdmin: false, isApprover: true));
        Assert.True(_push.SetEnabled(_mario.Id, InboxEntryTypes.Invite, false, isAdmin: false, isApprover: false));

        var invite = _push.Get(_mario.Id, isAdmin: false, isApprover: false).Types.Single(t => t.Type == InboxEntryTypes.Invite);
        Assert.False(invite.Enabled);
    }
}
