using System.Security.Cryptography;
using System.Text;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class WebPushCryptoTests
{
    // L'esempio di RFC 8291 §5 (e appendice A).
    private const string AuthSecret = "BTBZMqHH6r4Tts7J_aSIgg";
    private const string UaPublic = "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4";
    private const string AsPublic = "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8";
    private const string AsPrivate = "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw";
    private const string Salt = "DGv6ra1nlYgDCS1FRnbzlw";
    private const string Body =
        "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml"
        + "mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT"
        + "pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN";

    private static readonly byte[] Plaintext = Encoding.ASCII.GetBytes("When I grow up, I want to be a watermelon");

    [Fact]
    public void Encrypt_MatchesRfc8291Example()
    {
        var asPublic = Base64Url.Decode(AsPublic);
        using var serverKey = ECDiffieHellman.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            D = Base64Url.Decode(AsPrivate),
            Q = new ECPoint { X = asPublic[1..33], Y = asPublic[33..] },
        });

        var body = WebPushCrypto.Encrypt(
            Plaintext, Base64Url.Decode(UaPublic), Base64Url.Decode(AuthSecret), Base64Url.Decode(Salt), serverKey);

        Assert.Equal(Body, Base64Url.Encode(body));
    }

    [Fact]
    public void Encrypt_RandomSaltDiffers()
    {
        var first = WebPushCrypto.Encrypt(Plaintext, Base64Url.Decode(UaPublic), Base64Url.Decode(AuthSecret));
        var second = WebPushCrypto.Encrypt(Plaintext, Base64Url.Decode(UaPublic), Base64Url.Decode(AuthSecret));

        Assert.NotEqual(first, second);
        Assert.Equal(86 + Plaintext.Length + 1 + 16, first.Length);
        Assert.Equal(86 + Plaintext.Length + 1 + 16, second.Length);
    }

    [Fact]
    public void Encrypt_RejectsABadSubscriptionKey()
    {
        Assert.Throws<ArgumentException>(() =>
            WebPushCrypto.Encrypt(Plaintext, new byte[65], Base64Url.Decode(AuthSecret)));
        Assert.Throws<ArgumentException>(() =>
            WebPushCrypto.Encrypt(Plaintext, Base64Url.Decode(UaPublic), new byte[8]));
    }

    [Fact]
    public void Base64Url_TryDecodeRefusesGarbage()
    {
        Assert.False(Base64Url.TryDecode("not base64!", out _));
        Assert.True(Base64Url.TryDecode(Salt, out var salt));
        Assert.Equal(16, salt.Length);
    }
}
