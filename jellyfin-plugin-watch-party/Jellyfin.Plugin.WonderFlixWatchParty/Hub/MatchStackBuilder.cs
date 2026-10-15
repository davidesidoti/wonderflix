using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Hub;

/// <summary>
/// La pila del match (spec P §6.2): candidati a caso dalla libreria di chi
/// ha aperto la sala, poi tipo, durata, esclusi e, per ogni membro (anche
/// chi ha aperto), "lo può vedere" e "non l'ha mai visto né iniziato". I
/// controlli di un candidato si fermano al primo che non passa. Non lancia:
/// gli errori della libreria danno una pila più corta o vuota.
/// </summary>
public sealed class MatchStackBuilder(
    IMatchLibrary library,
    ILibraryAccess access,
    IRecommendationLibrary history,
    ILogger<MatchStackBuilder> logger)
{
    /// <summary>Titoli di una pila, all'inizio e a ogni "Altri 30" (spec P §3).</summary>
    public const int StackSize = 30;

    /// <summary>Candidati chiesti alla libreria per una pila (spec P §6.2).</summary>
    public const int CandidateLimit = 300;

    public IReadOnlyList<Guid> Draw(
        Guid creatorId, IReadOnlyList<Guid> members, MatchFilters filters, IReadOnlyCollection<Guid> exclude)
    {
        IReadOnlyList<MatchCandidate> candidates;
        try
        {
            candidates = library.Candidates(creatorId, filters, exclude, CandidateLimit);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Pila del match non pescata per {UserId}", creatorId);
            return [];
        }

        var stack = new List<Guid>();
        foreach (var candidate in candidates)
        {
            if (stack.Count == StackSize)
            {
                break;
            }

            if (exclude.Contains(candidate.Id) || stack.Contains(candidate.Id) || !Fits(candidate, filters))
            {
                continue;
            }

            try
            {
                if (members.All(member => access.CanSee(member, candidate.Id) && history.LastWatched(member, candidate.Id) is null))
                {
                    stack.Add(candidate.Id);
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Candidato {ItemId} del match scartato", candidate.Id.ToString("N"));
            }
        }

        logger.LogDebug("Pila del match per {UserId}: {Count} titoli su {Candidates} candidati", creatorId, stack.Count, candidates.Count);
        return stack;
    }

    // Come "Cosa guardo stasera?" nell'app: con un limite, un film senza durata non passa.
    private static bool Fits(MatchCandidate candidate, MatchFilters filters) =>
        candidate.IsMovie
            ? filters.Movies && (filters.MaxRuntime is not { } limit || candidate.RunTimeTicks < limit.Ticks)
            : filters.Series;
}
