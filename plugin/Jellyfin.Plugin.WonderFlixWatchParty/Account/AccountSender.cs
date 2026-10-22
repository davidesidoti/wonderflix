namespace Jellyfin.Plugin.WonderFlixWatchParty.Account;

/// <summary>L'ultimo errore d'invio di un canale (spec L §7.3), senza il destinatario.</summary>
public sealed record SendError(DateTimeOffset At, string Code);

/// <summary>I codici di <see cref="SendError"/>.</summary>
public static class SendErrorCodes
{
    public const string DmClosed = "DmClosed";

    public const string SendFailed = "SendFailed";

    /// <summary>Discord ha rifiutato token o server.</summary>
    public const string Invalid = "Invalid";
}

/// <summary>
/// Manda i messaggi ai contatti, canale per canale, e ricorda l'ultimo
/// errore di ogni canale per lo stato dell'admin; un invio riuscito lo
/// cancella. Un canale spento non manda niente e non conta come errore.
/// Sicuro tra thread.
/// </summary>
public sealed class AccountSender(IDiscordSender discord, IMailSender mail, IAccountSettings settings, TimeProvider time)
{
    private readonly Lock _lock = new();
    private readonly Dictionary<AccountChannel, SendError> _lastErrors = [];

    /// <summary>Un messaggio a un contatto: l'id Discord o l'indirizzo email.</summary>
    public async Task<SendOutcome> SendAsync(
        AccountChannel channel, string target, AccountMessage message, CancellationToken cancellationToken)
    {
        if (!settings.IsConfigured(channel))
        {
            return SendOutcome.Failed;
        }

        var outcome = channel == AccountChannel.Discord
            ? await discord.SendDmAsync(target, message.Text, cancellationToken).ConfigureAwait(false)
            : await mail.SendAsync(target, message, cancellationToken).ConfigureAwait(false);
        Record(channel, outcome);
        return outcome;
    }

    /// <summary>I contatti dell'utente sui canali configurati, nell'ordine Discord, Email (la stessa regola di <c>HasReachableContact</c>).</summary>
    public IReadOnlyList<(AccountChannel Channel, string Target)> Targets(UserContacts contacts) =>
        settings.ReachableTargets(contacts);

    /// <summary>
    /// Un messaggio a tutti i contatti dell'utente; restituisce i canali dove è
    /// arrivato, nell'ordine Discord, Email. I canali partono in parallelo, così
    /// l'attesa è quella del canale più lento e non la somma.
    /// </summary>
    public async Task<IReadOnlyList<AccountChannel>> SendToAllAsync(
        UserContacts contacts, AccountMessage message, CancellationToken cancellationToken)
    {
        var targets = Targets(contacts);
        var outcomes = await Task.WhenAll(
            targets.Select(t => SendAsync(t.Channel, t.Target, message, cancellationToken))).ConfigureAwait(false);
        return targets.Where((_, i) => outcomes[i] == SendOutcome.Sent).Select(t => t.Channel).ToList();
    }

    /// <summary>L'ultimo errore del canale; null se l'ultimo invio è riuscito o non ce ne sono stati.</summary>
    public SendError? LastError(AccountChannel channel)
    {
        lock (_lock)
        {
            return _lastErrors.GetValueOrDefault(channel);
        }
    }

    /// <summary>Registra l'esito di un invio (o di una ricerca) fatto altrove.</summary>
    public void Record(AccountChannel channel, SendOutcome outcome)
    {
        lock (_lock)
        {
            if (outcome == SendOutcome.Sent)
            {
                _lastErrors.Remove(channel);
            }
            else
            {
                _lastErrors[channel] = new SendError(
                    time.GetUtcNow(), outcome == SendOutcome.DmClosed ? SendErrorCodes.DmClosed : SendErrorCodes.SendFailed);
            }
        }
    }

    /// <summary>Discord ha rifiutato token o server.</summary>
    public void RecordInvalid(AccountChannel channel)
    {
        lock (_lock)
        {
            _lastErrors[channel] = new SendError(time.GetUtcNow(), SendErrorCodes.Invalid);
        }
    }
}
