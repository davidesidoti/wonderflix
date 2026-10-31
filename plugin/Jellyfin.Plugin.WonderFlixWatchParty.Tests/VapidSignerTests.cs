using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Jellyfin.Plugin.WonderFlixWatchParty.Push;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public class VapidSignerTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 31, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Generate_ProducesValidKeys()
    {
        var keys = VapidSigner.Generate();

        var publicKey = Base64Url.Decode(keys.PublicKey);
        Assert.Equal(65, publicKey.Length);
        Assert.Equal(0x04, publicKey[0]);
        Assert.Equal(32, Base64Url.Decode(keys.PrivateKey).Length);
    }

    [Fact]
    public void AuthorizationHeader_VerifiesWithPublicKey()
    {
        var keys = VapidSigner.Generate();

        var header = VapidSigner.AuthorizationHeader(
            "https://web.push.apple.com/abc", keys, "mailto:admin@example.com", Now);

        var prefix = "vapid t=";
        var suffix = ", k=" + keys.PublicKey;
        Assert.StartsWith(prefix, header);
        Assert.EndsWith(suffix, header);
        var jwt = header[prefix.Length..^suffix.Length];
        var parts = jwt.Split('.');
        Assert.Equal(3, parts.Length);

        using var head = JsonDocument.Parse(Base64Url.Decode(parts[0]));
        Assert.Equal("ES256", head.RootElement.GetProperty("alg").GetString());
        using var claims = JsonDocument.Parse(Base64Url.Decode(parts[1]));
        Assert.Equal("https://web.push.apple.com", claims.RootElement.GetProperty("aud").GetString());
        Assert.Equal(Now.AddHours(12).ToUnixTimeSeconds(), claims.RootElement.GetProperty("exp").GetInt64());
        Assert.Equal("mailto:admin@example.com", claims.RootElement.GetProperty("sub").GetString());

        var publicKey = Base64Url.Decode(keys.PublicKey);
        using var verifier = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = publicKey[1..33], Y = publicKey[33..] },
        });
        Assert.True(verifier.VerifyData(
            Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]),
            Base64Url.Decode(parts[2]),
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
    }
}
