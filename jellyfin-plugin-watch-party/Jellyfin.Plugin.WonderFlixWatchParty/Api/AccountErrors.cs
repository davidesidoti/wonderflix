using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Api;

/// <summary>
/// Da errore a stato HTTP e {Code} (spec L §7.6). Mai 404: per l'app un 404
/// vuol dire plugin senza la funzione.
/// </summary>
internal static class AccountErrors
{
    public static ObjectResult Result(AccountError error)
    {
        var status = error switch
        {
            AccountError.ChannelOff => StatusCodes.Status503ServiceUnavailable,
            AccountError.RateLimited => StatusCodes.Status429TooManyRequests,
            AccountError.DmClosed or AccountError.NoContacts => StatusCodes.Status409Conflict,
            AccountError.SendFailed => StatusCodes.Status502BadGateway,
            AccountError.NotAllowed or AccountError.WrongPassword => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status400BadRequest,
        };
        return new ObjectResult(new AccountErrorDto(error.ToString())) { StatusCode = status };
    }
}
