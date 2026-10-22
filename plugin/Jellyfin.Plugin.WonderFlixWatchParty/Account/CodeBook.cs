using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>A cosa serve un codice (spec L §7.2).</summary>
public enum CodePurpose
{
    VerifyDiscord,
    VerifyEmail,
    Recovery,
}

/// <summary>Il contatto in attesa di verifica: l'id Discord con il nome utente, oppure l'email (Name null).</summary>
public sealed record PendingContact(string Value, string? Name);

/// <summary>Esito di un controllo: con Ok, il contatto in attesa (null per il recupero).</summary>
public sealed record CodeCheck(bool Ok, PendingContact? Pending)
{
    public static readonly CodeCheck Wrong = new(false, null);
}

/// <summary>
/// I codici a 6 cifre (spec L §7.2), solo in memoria: un riavvio li perde.
/// Uno per utente e scopo; si salva l'hash con un sale, mai il codice.
/// Sicuro tra thread.
/// </summary>
public sealed class CodeBook(TimeProvider time)
{
    /// <summary>Quanto vale un codice.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(10);

    /// <summary>Tentativi sbagliati dopo i quali il codice sparisce.</summary>
    public const int MaxAttempts = 5;

    /// <summary>Cifre di un codice.</summary>
    public const int Digits = 6;

    // Codici possibili: da 000000 a 999999.
    private const int CodeSpace = 1_000_000;

    private const int SaltBytes = 16;

    private readonly Lock _lock = new();
    private readonly Dictionary<(Guid UserId, CodePurpose Purpose), Entry> _entries = [];

    /// <summary>Voci in memoria (per i test).</summary>
    internal int Count
    {
        get
        {
            lock (_lock)
            {
                return _entries.Count;
            }
        }
    }

    /// <summary>Un codice nuovo, che sostituisce quello di prima con lo stesso scopo.</summary>
    public (string Code, DateTimeOffset ExpiresAt) Issue(Guid userId, CodePurpose purpose, PendingContact? pending = null)
    {
        var code = RandomNumberGenerator.GetInt32(0, CodeSpace).ToString("D6", CultureInfo.InvariantCulture);
        var salt = RandomNumberGenerator.GetBytes(SaltBytes);
        var now = time.GetUtcNow();
        var expiresAt = now + Lifetime;
        lock (_lock)
        {
            // Gli scaduti vanno via qui: senza, resterebbero finché lo stesso utente non ne chiede un altro.
            foreach (var key in _entries.Where(e => e.Value.ExpiresAt <= now).Select(e => e.Key).ToList())
            {
                _entries.Remove(key);
            }

            _entries[(userId, purpose)] = new Entry(Hash(salt, code), salt, expiresAt, pending);
        }

        return (code, expiresAt);
    }

    /// <summary>
    /// Controlla un codice. Giusto: la voce sparisce (vale una volta) e torna
    /// il contatto in attesa. Sbagliato: conta un tentativo, e al
    /// <see cref="MaxAttempts"/>-esimo la voce sparisce. Assente o scaduto: Wrong.
    /// </summary>
    public CodeCheck Check(Guid userId, CodePurpose purpose, string? code)
    {
        var given = Normalize(code);
        var now = time.GetUtcNow();
        lock (_lock)
        {
            if (!_entries.TryGetValue((userId, purpose), out var entry))
            {
                return CodeCheck.Wrong;
            }

            if (entry.ExpiresAt <= now)
            {
                _entries.Remove((userId, purpose));
                return CodeCheck.Wrong;
            }

            if (given is not null && CryptographicOperations.FixedTimeEquals(entry.Hash, Hash(entry.Salt, given)))
            {
                _entries.Remove((userId, purpose));
                return new CodeCheck(true, entry.Pending);
            }

            entry.Attempts++;
            if (entry.Attempts >= MaxAttempts)
            {
                _entries.Remove((userId, purpose));
            }

            return CodeCheck.Wrong;
        }
    }

    /// <summary>Toglie il codice (per esempio se l'invio non è riuscito).</summary>
    public void Discard(Guid userId, CodePurpose purpose)
    {
        lock (_lock)
        {
            _entries.Remove((userId, purpose));
        }
    }

    // Spazi e trattini via ("123 456", "123-456"); poi devono restare 6 cifre.
    private static string? Normalize(string? code)
    {
        if (code is null)
        {
            return null;
        }

        var digits = new string(code.Where(c => !char.IsWhiteSpace(c) && c != '-').ToArray());
        return digits.Length == Digits && digits.All(char.IsAsciiDigit) ? digits : null;
    }

    private static byte[] Hash(byte[] salt, string code)
    {
        var text = Encoding.UTF8.GetBytes(code);
        var data = new byte[salt.Length + text.Length];
        salt.CopyTo(data, 0);
        text.CopyTo(data, salt.Length);
        return SHA256.HashData(data);
    }

    private sealed class Entry(byte[] hash, byte[] salt, DateTimeOffset expiresAt, PendingContact? pending)
    {
        public byte[] Hash { get; } = hash;

        public byte[] Salt { get; } = salt;

        public DateTimeOffset ExpiresAt { get; } = expiresAt;

        public PendingContact? Pending { get; } = pending;

        public int Attempts { get; set; }
    }
}
