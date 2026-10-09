using System.Reflection;
using System.Runtime.ExceptionServices;
using Jellyfin.Database.Implementations.Entities;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Server;

/// <summary>
/// Come chiedere a IUserManager di cambiare una password (spec L §14). In
/// Jellyfin 10.11.0 è ChangePassword(User, string); nella 10.11.9 del server
/// è diventata ChangePassword(Guid, string). Il plugin è compilato contro
/// 10.11.0, il minimo: si cerca a runtime quella che il server ha davvero,
/// come in UserListing.
/// </summary>
internal static class PasswordChanging
{
    /// <summary>La funzione che cambia la password con un manager di managerType; null se non ha nessuna delle due.</summary>
    public static Func<object, User, string, Task>? For(Type managerType)
    {
        var byId = managerType.GetMethod("ChangePassword", [typeof(Guid), typeof(string)]);
        if (byId is not null && byId.ReturnType == typeof(Task))
        {
            return (manager, user, password) => Call(byId, manager, [user.Id, password]);
        }

        var byUser = managerType.GetMethod("ChangePassword", [typeof(User), typeof(string)]);
        if (byUser is not null && byUser.ReturnType == typeof(Task))
        {
            return (manager, user, password) => Call(byUser, manager, [user, password]);
        }

        return null;
    }

    // L'errore di Jellyfin esce com'è, non avvolto in TargetInvocationException.
    private static Task Call(MethodInfo method, object manager, object?[] args)
    {
        try
        {
            return (Task)method.Invoke(manager, args)!;
        }
        catch (TargetInvocationException ex) when (ex.InnerException is not null)
        {
            ExceptionDispatchInfo.Capture(ex.InnerException).Throw();
            throw;
        }
    }
}
