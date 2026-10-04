using Jellyfin.Plugin.WonderFlixWatchParty.Protocol;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class EventValidatorTests
{
    private static EventRequest Request(
        string? type,
        string? action = null,
        long? ticks = null,
        string? text = null,
        string? reaction = null) =>
        new() { Type = type, Action = action, PositionTicks = ticks, Text = text, Reaction = reaction };

    [Theory]
    [InlineData("Pause")]
    [InlineData("Unpause")]
    [InlineData("NextItem")]
    [InlineData("NewQueue")]
    [InlineData("PreviousItem")]
    [InlineData("SetCurrentItem")]
    [InlineData("Queue")]
    [InlineData("QueueNext")]
    [InlineData("ShuffleMode")]
    public void ActionsWithoutPosition(string action)
    {
        var valid = EventValidator.Validate(Request(EventTypes.Action, action, ticks: 5));
        Assert.NotNull(valid);
        Assert.Equal(EventTypes.Action, valid.Type);
        Assert.Equal(action, valid.Action);
        Assert.Null(valid.PositionTicks);
    }

    [Fact]
    public void SeekNeedsAPosition()
    {
        Assert.Equal(600000000L, EventValidator.Validate(Request(EventTypes.Action, "Seek", 600000000))!.PositionTicks);
        Assert.Equal(0L, EventValidator.Validate(Request(EventTypes.Action, "Seek", 0))!.PositionTicks);
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action, "Seek")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action, "Seek", -1)));
    }

    [Fact]
    public void UnknownTypesAndActionsAreInvalid()
    {
        Assert.Null(EventValidator.Validate(null));
        Assert.Null(EventValidator.Validate(Request(null)));
        Assert.Null(EventValidator.Validate(Request("Poll")));
        // I valori distinguono le maiuscole (i nomi delle proprietà no).
        Assert.Null(EventValidator.Validate(Request("chat", text: "x")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action, "Shuffle")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Action)));
    }

    [Fact]
    public void ChatTextIsNormalizedAndLimited()
    {
        Assert.Equal("ciao a tutti", EventValidator.Validate(Request(EventTypes.Chat, text: "  ciao\r\na tutti\n "))!.Text);
        Assert.Null(EventValidator.Validate(Request(EventTypes.Chat, text: "  \n ")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Chat)));
        Assert.NotNull(EventValidator.Validate(Request(EventTypes.Chat, text: new string('x', 200))));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Chat, text: new string('x', 201))));
        // Un'emoji vale un carattere, come nell'app.
        var emoji = string.Concat(Enumerable.Repeat("😂", 200));
        Assert.NotNull(EventValidator.Validate(Request(EventTypes.Chat, text: emoji)));
    }

    [Fact]
    public void ReactionsAreShortLowercaseIds()
    {
        Assert.Equal("joy", EventValidator.Validate(Request(EventTypes.Reaction, reaction: "joy"))!.Reaction);
        // Il plugin non controlla l'elenco: le app ignorano quelle che non conoscono.
        Assert.NotNull(EventValidator.Validate(Request(EventTypes.Reaction, reaction: "heart")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction, reaction: "Joy")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction, reaction: "joy\n")));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction, reaction: new string('a', 21))));
        Assert.Null(EventValidator.Validate(Request(EventTypes.Reaction)));
    }
}
