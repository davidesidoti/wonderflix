using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>Logger che ricorda livello, eccezione e testo di ogni voce.</summary>
internal sealed class RecordingLogger<T>(bool throwOnReveal = false) : ILogger<T>
{
    public List<(LogLevel Level, Exception? Exception, string Message)> Entries { get; } = [];

    public IDisposable? BeginScope<TState>(TState state)
        where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => true;

    public void Log<TState>(
        LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
        Record(logLevel, exception, formatter(state, exception));

    private void Record(LogLevel level, Exception? exception, string message)
    {
        Entries.Add((level, exception, message));

        // Per simulare un errore dentro un timer: il Debug dei voti scoperti lancia.
        if (throwOnReveal && level == LogLevel.Debug && message.Contains("voti scoperti", StringComparison.Ordinal))
        {
            throw new IOException("errore simulato");
        }
    }
}
