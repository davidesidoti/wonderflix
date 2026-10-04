using System.Text.RegularExpressions;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Protocol;

/// <summary>Un evento valido e normalizzato, pronto da timbrare.</summary>
public sealed record ValidatedEvent(
    string Type,
    string? Action = null,
    long? PositionTicks = null,
    string? Text = null,
    string? Reaction = null);

/// <summary>Validazione degli eventi mandati dall'app (spec E §6.3).</summary>
public static partial class EventValidator
{
    private static readonly HashSet<string> Actions = new(StringComparer.Ordinal)
    {
        "Pause", "Unpause", "Seek", "NextItem", "NewQueue",
        // Coda del watch party (spec H §7).
        "PreviousItem", "SetCurrentItem", "Queue", "QueueNext", "ShuffleMode",
    };

    /// <summary>L'evento valido e normalizzato; null se non è valido.</summary>
    public static ValidatedEvent? Validate(EventRequest? request)
    {
        if (request is null)
        {
            return null;
        }

        switch (request.Type)
        {
            case EventTypes.Action:
                if (request.Action is not { } action || !Actions.Contains(action))
                {
                    return null;
                }

                if (action != "Seek")
                {
                    return new ValidatedEvent(EventTypes.Action, action);
                }

                return request.PositionTicks is >= 0
                    ? new ValidatedEvent(EventTypes.Action, action, request.PositionTicks)
                    : null;
            case EventTypes.Chat:
                var text = NormalizeText(request.Text);
                var length = text.EnumerateRunes().Count();
                return length is >= 1 and <= WatchPartyProtocol.MaxChatLength
                    ? new ValidatedEvent(EventTypes.Chat, Text: text)
                    : null;
            case EventTypes.Reaction:
                // Il plugin non controlla l'elenco: le app ignorano quelle che non conoscono.
                return request.Reaction is { } reaction && ReactionPattern().IsMatch(reaction)
                    ? new ValidatedEvent(EventTypes.Reaction, Reaction: reaction)
                    : null;
            default:
                return null;
        }
    }

    /// <summary>A capo diventati spazi, spazi esterni tolti (come normalizeChatText dell'app).</summary>
    public static string NormalizeText(string? text) =>
        LineBreaks().Replace(text ?? string.Empty, " ").Trim();

    [GeneratedRegex(@"^[a-z]{1,20}\z")]
    private static partial Regex ReactionPattern();

    [GeneratedRegex(@"[\r\n]+")]
    private static partial Regex LineBreaks();
}
