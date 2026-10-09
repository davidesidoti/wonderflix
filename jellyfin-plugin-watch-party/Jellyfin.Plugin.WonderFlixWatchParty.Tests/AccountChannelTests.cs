using Jellyfin.Plugin.WonderFlixWatchParty.Account;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class AccountChannelTests
{
    [Theory]
    [InlineData("Discord", AccountChannel.Discord)]
    [InlineData("discord", AccountChannel.Discord)]
    [InlineData("EMAIL", AccountChannel.Email)]
    public void ChannelsAreReadWithoutCase(string raw, AccountChannel expected)
    {
        Assert.True(AccountChannels.TryParse(raw, out var channel));
        Assert.Equal(expected, channel);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("0")]
    [InlineData("1")]
    [InlineData("Telegram")]
    public void NumbersAndOtherNamesAreNotChannels(string? raw) =>
        Assert.False(AccountChannels.TryParse(raw, out _));

    [Fact]
    public void NamesAndOrder()
    {
        Assert.Equal("Discord", AccountChannel.Discord.Name());
        Assert.Equal("Email", AccountChannel.Email.Name());
        Assert.Equal(new[] { AccountChannel.Discord, AccountChannel.Email }, AccountChannels.All);
    }

    [Theory]
    [InlineData("12345678901234567", true)]
    [InlineData("12345678901234567890", true)]
    [InlineData("1234567890123456", false)]
    [InlineData("123456789012345678901", false)]
    [InlineData("12345678901234567a", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void DiscordIdsAreSeventeenToTwentyDigits(string? value, bool valid) =>
        Assert.Equal(valid, DiscordIds.IsSnowflake(value));
}
