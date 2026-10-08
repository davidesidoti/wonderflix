using System.Reflection;
using Jellyfin.Plugin.WonderFlixWatchParty.Api;
using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AvatarsControllerTests
{
    private readonly FakeAvatars _avatars = new();

    private AvatarsController Controller() => new(_avatars)
    {
        ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() },
    };

    [Fact]
    public void AsksForIdsAndNamesAndAnswersWithJellyfinIds()
    {
        var mario = Guid.NewGuid();
        _avatars.Result = [new UserAvatarInfo(mario, "Mario", "tag-m"), new UserAvatarInfo(Guid.NewGuid(), "Luigi", null)];

        var users = Controller().GetAvatars($"{mario:N}, non-un-id,", "luigi, ").Value!.Users;

        var (ids, names) = Assert.Single(_avatars.Calls);
        // Gli id che non sono GUID e le voci vuote si saltano.
        Assert.Equal(new[] { mario }, ids);
        Assert.Equal(new[] { "luigi" }, names);
        Assert.Equal(mario.ToString("N"), users[0].UserId);
        Assert.Equal("Mario", users[0].Name);
        Assert.Equal("tag-m", users[0].ImageTag);
        Assert.Null(users[1].ImageTag);
    }

    [Fact]
    public void WithoutIdsOrNamesTheListIsEmptyAndNobodyIsAsked()
    {
        Assert.Empty(Controller().GetAvatars(null, null).Value!.Users);
        Assert.Empty(Controller().GetAvatars(" ", ",").Value!.Users);
        // Solo id che non sono GUID (o il GUID vuoto): non c'è nessuno da cercare.
        Assert.Empty(Controller().GetAvatars("non-un-id", null).Value!.Users);
        Assert.Empty(Controller().GetAvatars($"non-un-id,{Guid.Empty:N}", " ").Value!.Users);

        // L'elenco degli utenti non si legge nemmeno.
        Assert.Empty(_avatars.Calls);
    }

    [Fact]
    public void AGuidWithDashesIsAccepted()
    {
        var mario = Guid.NewGuid();

        Controller().GetAvatars(mario.ToString("D"), null);

        var (ids, names) = Assert.Single(_avatars.Calls);
        Assert.Equal(new[] { mario }, ids);
        Assert.Empty(names);
    }

    [Fact]
    public void MoreThanAHundredEntriesIsABadRequest()
    {
        var ids = string.Join(',', Enumerable.Range(0, 60).Select(_ => Guid.NewGuid().ToString("N")));
        static string Names(int count) => string.Join(',', Enumerable.Range(0, count).Select(i => $"utente{i}"));

        Assert.IsType<BadRequestResult>(Controller().GetAvatars(ids, Names(41)).Result);
        Assert.Empty(_avatars.Calls);

        // Esattamente 100 voci vanno bene.
        Assert.NotNull(Controller().GetAvatars(ids, Names(40)).Value);
    }

    [Fact]
    public void EveryAuthenticatedUserCanAsk()
    {
        // Le immagini non dipendono dal watch party: nessuna policy.
        var authorize = Assert.Single(typeof(AvatarsController).GetCustomAttributes<AuthorizeAttribute>());
        Assert.Null(authorize.Policy);
        Assert.Empty(typeof(AvatarsController).GetMethod(nameof(AvatarsController.GetAvatars))!
            .GetCustomAttributes<AuthorizeAttribute>());
    }

    private sealed class FakeAvatars : IUserAvatars
    {
        public List<(IReadOnlyCollection<Guid> Ids, IReadOnlyCollection<string> Names)> Calls { get; } = [];

        public IReadOnlyList<UserAvatarInfo> Result { get; set; } = [];

        public IReadOnlyList<UserAvatarInfo> Find(IReadOnlyCollection<Guid> ids, IReadOnlyCollection<string> names)
        {
            Calls.Add((ids, names));
            return Result;
        }
    }
}
