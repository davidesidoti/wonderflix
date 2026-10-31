namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>Base64url senza padding (RFC 4648 §5), la forma delle chiavi e dei JWT del Web Push.</summary>
public static class Base64Url
{
    public static string Encode(byte[] bytes) => System.Buffers.Text.Base64Url.EncodeToString(bytes);

    /// <exception cref="FormatException">Se il testo non è base64url.</exception>
    public static byte[] Decode(string text) => System.Buffers.Text.Base64Url.DecodeFromChars(text);

    public static bool TryDecode(string text, out byte[] bytes)
    {
        // TryDecodeFromChars di .NET lancia lo stesso sui caratteri sbagliati: il suo "Try" è solo per il buffer.
        try
        {
            bytes = Decode(text);
            return true;
        }
        catch (FormatException)
        {
            bytes = [];
            return false;
        }
    }
}
