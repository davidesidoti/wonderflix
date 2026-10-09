using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class CodeBookTests
{
    private readonly FakeTimeProvider _time = new(new DateTimeOffset(2026, 10, 9, 12, 0, 0, TimeSpan.Zero));
    private readonly Guid _mario = Guid.NewGuid();
    private readonly Guid _luigi = Guid.NewGuid();

    [Fact]
    public void SixDigitCodesThatWorkOnce()
    {
        var book = new CodeBook(_time);

        var (code, expiresAt) = book.Issue(_mario, CodePurpose.Recovery);

        Assert.Matches("^[0-9]{6}$", code);
        Assert.Equal(_time.GetUtcNow() + CodeBook.Lifetime, expiresAt);
        var check = book.Check(_mario, CodePurpose.Recovery, code);
        Assert.True(check.Ok);
        Assert.Null(check.Pending);
        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void ThePendingContactComesBack()
    {
        var book = new CodeBook(_time);
        var pending = new PendingContact("222222222222222222", "mario");

        var (code, _) = book.Issue(_mario, CodePurpose.VerifyDiscord, pending);

        Assert.Equal(pending, book.Check(_mario, CodePurpose.VerifyDiscord, code).Pending);
    }

    [Fact]
    public void ACodeLastsTenMinutes()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        _time.Advance(CodeBook.Lifetime - TimeSpan.FromSeconds(1));
        var (other, _) = book.Issue(_luigi, CodePurpose.Recovery);
        Assert.True(book.Check(_luigi, CodePurpose.Recovery, other).Ok);

        _time.Advance(TimeSpan.FromSeconds(1));

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void FourWrongAttemptsLeaveTheCodeTheFifthDropsIt()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        var wrong = code == "000000" ? "111111" : "000000";
        for (var i = 0; i < CodeBook.MaxAttempts - 1; i++)
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, wrong).Ok);
        }

        Assert.True(book.Check(_mario, CodePurpose.Recovery, code).Ok);

        (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        wrong = code == "000000" ? "111111" : "000000";
        for (var i = 0; i < CodeBook.MaxAttempts; i++)
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, wrong).Ok);
        }

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void ANewCodeReplacesTheOldOne()
    {
        var book = new CodeBook(_time);
        var (first, _) = book.Issue(_mario, CodePurpose.Recovery);
        var (second, _) = book.Issue(_mario, CodePurpose.Recovery);

        // Uguali per caso una volta su un milione: allora il primo vale come il secondo.
        if (first != second)
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, first).Ok);
        }

        Assert.True(book.Check(_mario, CodePurpose.Recovery, second).Ok);
    }

    [Fact]
    public void UsersAndPurposesAreSeparate()
    {
        var book = new CodeBook(_time);
        var (discord, _) = book.Issue(_mario, CodePurpose.VerifyDiscord);
        var (email, _) = book.Issue(_mario, CodePurpose.VerifyEmail);
        var (luigi, _) = book.Issue(_luigi, CodePurpose.Recovery);

        Assert.False(book.Check(_mario, CodePurpose.Recovery, discord).Ok);
        Assert.False(book.Check(_luigi, CodePurpose.VerifyDiscord, discord).Ok);
        Assert.True(book.Check(_mario, CodePurpose.VerifyDiscord, discord).Ok);
        Assert.True(book.Check(_mario, CodePurpose.VerifyEmail, email).Ok);
        Assert.True(book.Check(_luigi, CodePurpose.Recovery, luigi).Ok);
    }

    [Fact]
    public void SpacesAndDashesAreFine()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        Assert.True(book.Check(_mario, CodePurpose.Recovery, $" {code[..3]} {code[3..]} ").Ok);

        (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        Assert.True(book.Check(_mario, CodePurpose.Recovery, $"{code[..3]}-{code[3..]}").Ok);
    }

    [Fact]
    public void MalformedCodesAreWrongAttempts()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);
        foreach (var bad in new string?[] { null, string.Empty, "abc", "12345", "1234567" })
        {
            Assert.False(book.Check(_mario, CodePurpose.Recovery, bad).Ok);
        }

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
    }

    [Fact]
    public void DiscardRemovesTheCode()
    {
        var book = new CodeBook(_time);
        var (code, _) = book.Issue(_mario, CodePurpose.Recovery);

        book.Discard(_mario, CodePurpose.Recovery);

        Assert.False(book.Check(_mario, CodePurpose.Recovery, code).Ok);
        Assert.Equal(0, book.Count);
    }

    [Fact]
    public void ExpiredCodesGoAwayWithTheNextIssue()
    {
        var book = new CodeBook(_time);
        book.Issue(_mario, CodePurpose.Recovery);
        _time.Advance(CodeBook.Lifetime);

        book.Issue(_luigi, CodePurpose.Recovery);

        Assert.Equal(1, book.Count);
    }
}
