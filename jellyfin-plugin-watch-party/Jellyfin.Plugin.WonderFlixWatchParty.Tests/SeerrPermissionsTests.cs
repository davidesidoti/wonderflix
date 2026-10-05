using Jellyfin.Plugin.WonderFlixWatchParty.Seerr;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class SeerrPermissionsTests
{
    [Theory]
    [InlineData(2, true, true)] // ADMIN: tutti i permessi
    [InlineData(34, true, true)] // ADMIN + REQUEST (l'admin del server)
    [InlineData(32, true, false)] // REQUEST (gli amici)
    [InlineData(16, false, true)] // MANAGE_REQUESTS
    [InlineData(262144, true, false)] // REQUEST_MOVIE
    [InlineData(524288, true, false)] // REQUEST_TV
    [InlineData(0, false, false)]
    public void RequestAndManage(int permissions, bool canRequest, bool canManage)
    {
        Assert.Equal(canRequest, SeerrPermissions.CanRequest(permissions));
        Assert.Equal(canManage, SeerrPermissions.CanManage(permissions));
    }
}
