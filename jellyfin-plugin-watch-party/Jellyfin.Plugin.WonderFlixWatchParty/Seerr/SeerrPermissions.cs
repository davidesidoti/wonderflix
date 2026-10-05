namespace Jellyfin.Plugin.WonderFlixWatchParty.Seerr;

/// <summary>Bit dei permessi di Seerr (spec I §3) e i controlli che servono al plugin.</summary>
public static class SeerrPermissions
{
    public const int Admin = 2;
    public const int ManageUsers = 8;
    public const int ManageRequests = 16;
    public const int Request = 32;
    public const int RequestMovie = 262144;
    public const int RequestTv = 524288;

    /// <summary>Ha il permesso; ADMIN li ha tutti, come in Seerr.</summary>
    public static bool Has(int permissions, int permission) =>
        (permissions & Admin) != 0 || (permissions & permission) == permission;

    /// <summary>Può approvare e rifiutare le richieste.</summary>
    public static bool CanManage(int permissions) => Has(permissions, ManageRequests);

    /// <summary>Può chiedere film o serie.</summary>
    public static bool CanRequest(int permissions) =>
        Has(permissions, Request) || Has(permissions, RequestMovie) || Has(permissions, RequestTv);
}
