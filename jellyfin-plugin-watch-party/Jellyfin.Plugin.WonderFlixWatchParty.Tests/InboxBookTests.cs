using Jellyfin.Plugin.WonderFlixWatchParty.Hub;
using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class InboxBookTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 3, 20, 0, 0, TimeSpan.Zero);

    private readonly Guid _mario = Guid.NewGuid();

    private static InboxEntry Announcement(string text, DateTimeOffset? at = null) =>
        new() { Type = InboxEntryTypes.Announcement, CreatedAt = at ?? Now, Text = text };

    [Fact]
    public void EntriesTakeIncreasingSeqAndListNewestFirst()
    {
        var book = new InboxBook();
        var first = book.Add(_mario, Announcement("uno"));
        var second = book.Add(_mario, Announcement("due"));

        Assert.Equal(1, first.Seq);
        Assert.Equal(2, second.Seq);
        Assert.NotEqual(first.Id, second.Id);
        Assert.Equal(new[] { "due", "uno" }, book.List(_mario).Select(e => e.Text));
        Assert.Empty(book.List(Guid.NewGuid()));
    }

    [Fact]
    public void ListGivesCopies()
    {
        var book = new InboxBook();
        book.Add(_mario, Announcement("uno"));
        book.List(_mario)[0].Read = true;
        Assert.False(book.List(_mario)[0].Read);
    }

    [Fact]
    public void BeyondTheLimitTheOldestGoes()
    {
        var book = new InboxBook();
        for (var i = 0; i <= InboxBook.MaxEntries; i++)
        {
            book.Add(_mario, Announcement($"n{i}"));
        }

        var entries = book.List(_mario);
        Assert.Equal(InboxBook.MaxEntries, entries.Count);
        Assert.DoesNotContain(entries, e => e.Text == "n0");
        Assert.Equal($"n{InboxBook.MaxEntries}", entries[0].Text);
    }

    [Fact]
    public void ASecondInviteToTheSameGroupUpdatesTheEntry()
    {
        var book = new InboxBook();
        var invite = book.UpsertInvite(_mario, "g1", "Luigi", "Dune", "m1", Now);
        book.Add(_mario, Announcement("in mezzo"));
        book.MarkRead(_mario, long.MaxValue);

        var again = book.UpsertInvite(_mario, "G1", "Peach", "Dune", "m1", Now.AddMinutes(5));

        Assert.Equal(invite.Id, again.Id);
        Assert.Equal(3, again.Seq);
        var entries = book.List(_mario);
        Assert.Equal(2, entries.Count);
        Assert.Equal(invite.Id, entries[0].Id);
        Assert.Equal("Peach", entries[0].FromName);
        Assert.Equal(Now.AddMinutes(5), entries[0].CreatedAt);
        Assert.False(entries[0].Read);
        Assert.True(entries[1].Read);
    }

    [Fact]
    public void MarkReadStopsAtUpTo()
    {
        var book = new InboxBook();
        book.Add(_mario, Announcement("uno"));
        book.Add(_mario, Announcement("due"));

        Assert.True(book.MarkRead(_mario, 1));
        Assert.Equal(new[] { false, true }, book.List(_mario).Select(e => e.Read));
        Assert.False(book.MarkRead(_mario, 1));
        Assert.False(book.MarkRead(Guid.NewGuid(), 5));
    }

    [Fact]
    public void RemoveAndClear()
    {
        var book = new InboxBook();
        var first = book.Add(_mario, Announcement("uno"));
        book.Add(_mario, Announcement("due"));

        Assert.True(book.Remove(_mario, first.Id));
        Assert.False(book.Remove(_mario, first.Id));
        Assert.Single(book.List(_mario));
        Assert.True(book.Clear(_mario));
        Assert.False(book.Clear(_mario));
        Assert.Empty(book.List(_mario));
        // Il Seq continua: una voce nuova non riusa quelli già visti dall'app.
        Assert.Equal(3, book.Add(_mario, Announcement("tre")).Seq);
    }

    [Fact]
    public void PruneDropsOldEntriesAndMissingUsers()
    {
        var book = new InboxBook();
        var luigi = Guid.NewGuid();
        book.Add(_mario, Announcement("vecchia", Now.AddDays(-31)));
        book.Add(_mario, Announcement("nuova", Now));
        book.Add(luigi, Announcement("di Luigi"));

        Assert.Equal(2, book.Prune(Now.AddDays(-30), id => id == _mario));

        Assert.Equal(new[] { "nuova" }, book.List(_mario).Select(e => e.Text));
        Assert.Empty(book.List(luigi));
    }

    [Fact]
    public void TheFileRoundTripsAndKeepsTheSeq()
    {
        var book = new InboxBook();
        book.UpsertInvite(_mario, "g1", "Luigi", "Dune", "m1", Now);
        book.Add(_mario, Announcement("ciao"));
        book.Clear(_mario);
        book.Add(_mario, Announcement("dopo"));

        var copy = InboxBook.FromFile(book.ToFile());

        Assert.Equal(new[] { "dopo" }, copy.List(_mario).Select(e => e.Text));
        Assert.Equal(4, copy.Add(_mario, Announcement("ancora")).Seq);
    }

    [Fact]
    public void ABadFileIsRefused()
    {
        var mario = _mario.ToString("N");
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { ["x"] = new InboxFileUser() } }));
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { [mario] = null } }));
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { [mario] = new InboxFileUser { Entries = [null] } } }));
        Assert.Throws<FormatException>(() => InboxBook.FromFile(
            new InboxFile { Users = new() { [mario] = new InboxFileUser { Entries = [new InboxEntry()] } } }));
    }
}
