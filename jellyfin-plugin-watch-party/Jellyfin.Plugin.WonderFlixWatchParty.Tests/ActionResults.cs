using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Stato e codice d'errore delle risposte dei controller Account.</summary>
internal static class ActionResults
{
    public static int Status(IActionResult result) => result switch
    {
        StatusCodeResult code => code.StatusCode,
        ObjectResult value => value.StatusCode ?? StatusCodes.Status200OK,
        _ => throw new InvalidOperationException(result.GetType().Name),
    };

    public static string Code(IActionResult result) =>
        Assert.IsType<AccountErrorDto>(Assert.IsType<ObjectResult>(result).Value).Code;

    public static void AssertError(int status, string code, IActionResult? result)
    {
        Assert.NotNull(result);
        Assert.Equal(status, Status(result));
        Assert.Equal(code, Code(result));
    }
}
