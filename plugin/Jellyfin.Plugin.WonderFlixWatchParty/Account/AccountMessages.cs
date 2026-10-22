namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>Un messaggio da mandare: l'oggetto (per le email) e il testo.</summary>
public sealed record AccountMessage(string Subject, string Text);

/// <summary>I testi dei messaggi del plugin (spec L §7.3), in italiano o in inglese.</summary>
public static class AccountMessages
{
    private static int Minutes => (int)CodeBook.Lifetime.TotalMinutes;

    /// <summary>"en" è inglese; tutto il resto, anche vuoto o sconosciuto, italiano.</summary>
    public static bool IsEnglish(string? language) =>
        string.Equals(language?.Trim(), "en", StringComparison.OrdinalIgnoreCase);

    public static AccountMessage Verify(string? language, string code) => IsEnglish(language)
        ? new(
            "WonderFlix — code",
            $"Your WonderFlix code to link this account is {code}. It expires in {Minutes} minutes. If you didn't ask for it, ignore this message.")
        : new(
            "WonderFlix — codice",
            $"Il tuo codice WonderFlix per collegare questo account è {code}. Scade tra {Minutes} minuti. Se non l'hai chiesto tu, ignora questo messaggio.");

    public static AccountMessage Recovery(string? language, string userName, string code) => IsEnglish(language)
        ? new(
            "WonderFlix — code",
            $"Your WonderFlix code to change the password of «{userName}» is {code}. It expires in {Minutes} minutes. If you didn't ask for it, ignore this message: the password doesn't change until the code is used.")
        : new(
            "WonderFlix — codice",
            $"Il tuo codice WonderFlix per cambiare la password di «{userName}» è {code}. Scade tra {Minutes} minuti. Se non l'hai chiesto tu, ignora questo messaggio: la password non cambia finché il codice non viene usato.");

    public static AccountMessage PasswordChanged(string? language, string userName) => IsEnglish(language)
        ? new(
            "WonderFlix — password changed",
            $"The WonderFlix password of «{userName}» has been changed. If it wasn't you, write to the administrator.")
        : new(
            "WonderFlix — password cambiata",
            $"La password WonderFlix di «{userName}» è stata cambiata. Se non sei stato tu, scrivi all'amministratore.");

    public static AccountMessage Test(string? language) => IsEnglish(language)
        ? new("WonderFlix — test", "Test message from WonderFlix: the channel works.")
        : new("WonderFlix — prova", "Messaggio di prova di WonderFlix: il canale funziona.");
}
