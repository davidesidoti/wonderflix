using Jellyfin.Database.Implementations.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Come chiedere a IUserManager tutti gli utenti. In Jellyfin 10.11.0 è la
/// proprietà Users; in una 10.11.x successiva (la 10.11.9 del server ce l'ha
/// già) è diventata il metodo GetUsers(). Il plugin è compilato contro
/// 10.11.0, il minimo: si cerca a runtime quello che il server ha davvero.
/// </summary>
internal static class UserListing
{
    /// <summary>La funzione che elenca gli utenti di managerType; null se non ha né l'uno né l'altro.</summary>
    public static Func<object, IEnumerable<User>>? For(Type managerType)
    {
        var method = managerType.GetMethod("GetUsers", Type.EmptyTypes);
        if (method is not null && typeof(IEnumerable<User>).IsAssignableFrom(method.ReturnType))
        {
            return manager => (IEnumerable<User>?)method.Invoke(manager, null) ?? [];
        }

        var property = managerType.GetProperty("Users");
        if (property is not null && typeof(IEnumerable<User>).IsAssignableFrom(property.PropertyType))
        {
            return manager => (IEnumerable<User>?)property.GetValue(manager) ?? [];
        }

        return null;
    }
}
