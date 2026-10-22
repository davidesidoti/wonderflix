using System.Reflection;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

/// <summary>
/// Stub di un'interfaccia costruito con DispatchProxy. Registra le chiamate;
/// i membri senza gestore restituiscono il valore di default (o
/// Task.CompletedTask).
/// </summary>
public class InterfaceStub<T> : DispatchProxy
    where T : class
{
    /// <summary>Gestori per nome del metodo (es. "get_Sessions", "add_SessionEnded").</summary>
    public Dictionary<string, Func<object?[], object?>> Handlers { get; } = new(StringComparer.Ordinal);

    public List<(string Name, object?[] Args)> Calls { get; } = [];

    public static (T Proxy, InterfaceStub<T> Stub) Create()
    {
        var proxy = DispatchProxy.Create<T, InterfaceStub<T>>();
        return (proxy, (InterfaceStub<T>)(object)proxy);
    }

    protected override object? Invoke(MethodInfo? targetMethod, object?[]? args)
    {
        ArgumentNullException.ThrowIfNull(targetMethod);
        args ??= [];
        Calls.Add((targetMethod.Name, args));
        if (Handlers.TryGetValue(targetMethod.Name, out var handler))
        {
            return handler(args);
        }

        var returnType = targetMethod.ReturnType;
        if (returnType == typeof(void))
        {
            return null;
        }

        if (returnType == typeof(Task))
        {
            return Task.CompletedTask;
        }

        return returnType.IsValueType ? Activator.CreateInstance(returnType) : null;
    }
}
