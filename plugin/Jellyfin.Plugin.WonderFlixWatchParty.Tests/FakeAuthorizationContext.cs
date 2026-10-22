using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Http;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Autenticazione fissa per i test del controller.</summary>
internal sealed class FakeAuthorizationContext(AuthorizationInfo info) : IAuthorizationContext
{
    public Task<AuthorizationInfo> GetAuthorizationInfo(HttpContext requestContext) => Task.FromResult(info);

    public Task<AuthorizationInfo> GetAuthorizationInfo(HttpRequest requestContext) => Task.FromResult(info);
}
