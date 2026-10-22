using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Logging.Abstractions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>I contatti dei test: file in una cartella temporanea.</summary>
internal static class TestAccount
{
    public static ContactRegistry Registry(TempFolder folder) =>
        new(new ContactStore(folder.ContactsFile, NullLogger<ContactStore>.Instance), NullLogger<ContactRegistry>.Instance);
}
