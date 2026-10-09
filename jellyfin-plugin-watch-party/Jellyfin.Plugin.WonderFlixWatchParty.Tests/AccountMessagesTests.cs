using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AccountMessagesTests
{
    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("it")]
    [InlineData("de")]
    [InlineData("english")]
    public void ItalianUnlessEnglish(string? language)
    {
        var message = AccountMessages.Verify(language, "012345");

        Assert.Equal("WonderFlix — codice", message.Subject);
        Assert.Contains("012345", message.Text);
        Assert.Contains("Scade tra 10 minuti", message.Text);
    }

    [Theory]
    [InlineData("en")]
    [InlineData(" EN ")]
    public void English(string language)
    {
        var message = AccountMessages.Verify(language, "012345");

        Assert.Equal("WonderFlix — code", message.Subject);
        Assert.Contains("012345", message.Text);
        Assert.Contains("expires in 10 minutes", message.Text);
    }

    [Fact]
    public void RecoveryNamesTheUserAndSaysThePasswordStays()
    {
        var italian = AccountMessages.Recovery("it", "Mario", "654321");
        Assert.Contains("«Mario»", italian.Text);
        Assert.Contains("654321", italian.Text);
        Assert.Contains("la password non cambia", italian.Text);

        var english = AccountMessages.Recovery("en", "Mario", "654321");
        Assert.Contains("«Mario»", english.Text);
        Assert.Contains("the password doesn't change", english.Text);
    }

    [Fact]
    public void PasswordChangedAndTest()
    {
        Assert.Equal("WonderFlix — password cambiata", AccountMessages.PasswordChanged("it", "Mario").Subject);
        Assert.Contains("«Mario»", AccountMessages.PasswordChanged("en", "Mario").Text);
        Assert.Equal("WonderFlix — prova", AccountMessages.Test(null).Subject);
        Assert.Equal("WonderFlix — test", AccountMessages.Test("en").Subject);
    }
}
