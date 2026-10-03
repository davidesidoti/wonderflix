using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.WonderFlixWatchParty;

/// <summary>
/// Collega il raccoglitore dei nuovi titoli agli eventi della libreria di
/// Jellyfin (spec G §6.6). Gli eventi arrivano dai thread della scansione: i
/// gestori fanno solo il filtro e una chiamata O(1), e non lanciano mai (un
/// errore fermerebbe gli altri ascoltatori dello stesso evento).
/// </summary>
public sealed class NewTitlesHostedService(
    ILibraryManager libraryManager,
    NewTitlesCollector collector,
    ILogger<NewTitlesHostedService> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        libraryManager.ItemAdded += OnItemAdded;
        libraryManager.ItemRemoved += OnItemRemoved;
        collector.Start();
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        libraryManager.ItemAdded -= OnItemAdded;
        libraryManager.ItemRemoved -= OnItemRemoved;
        collector.Dispose();
        return Task.CompletedTask;
    }

    private void OnItemAdded(object? sender, ItemChangeEventArgs e)
    {
        try
        {
            var item = e.Item;
            if (NewTitleRules.IsRealTitle(item))
            {
                collector.Added(item.Id);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Nuovo titolo non raccolto");
        }
    }

    // Gli id esterni si leggono adesso: dopo la rimozione l'elemento non si rilegge più.
    private void OnItemRemoved(object? sender, ItemChangeEventArgs e)
    {
        try
        {
            var item = e.Item;
            if (NewTitleRules.IsRealTitle(item))
            {
                collector.Removed(item.Id, item is Movie, NewTitleRules.ExternalKeys(item));
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Titolo tolto non registrato");
        }
    }
}
