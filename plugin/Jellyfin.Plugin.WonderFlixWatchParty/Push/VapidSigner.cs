using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>Le chiavi VAPID in base64url: il punto P-256 non compresso (65 byte) e lo scalare D (32 byte).</summary>
public sealed record VapidKeys(string PublicKey, string PrivateKey);

/// <summary>L'identificazione del server presso i servizi push (RFC 8292): un JWT ES256 per ogni origine.</summary>
public static class VapidSigner
{
    /// <summary>Quanto vale un JWT; i servizi push ne rifiutano oltre le 24 ore.</summary>
    public static readonly TimeSpan Lifetime = TimeSpan.FromHours(12);

    private static readonly string JwtHeader = Base64Url.Encode(Encoding.UTF8.GetBytes("""{"typ":"JWT","alg":"ES256"}"""));

    /// <summary>Una coppia di chiavi nuova.</summary>
    public static VapidKeys Generate()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var p = key.ExportParameters(true);
        return new VapidKeys(Base64Url.Encode([0x04, .. p.Q.X!, .. p.Q.Y!]), Base64Url.Encode(p.D!));
    }

    /// <summary>L'header Authorization per <paramref name="endpoint"/>: <c>vapid t=&lt;jwt&gt;, k=&lt;chiave pubblica&gt;</c>.</summary>
    /// <param name="subject">Il contatto dell'amministratore: <c>mailto:</c> o <c>https:</c>.</param>
    public static string AuthorizationHeader(string endpoint, VapidKeys keys, string subject, DateTimeOffset now)
    {
        var claims = new
        {
            aud = new Uri(endpoint).GetLeftPart(UriPartial.Authority),
            exp = (now + Lifetime).ToUnixTimeSeconds(),
            sub = subject,
        };
        var signingInput = JwtHeader + "." + Base64Url.Encode(JsonSerializer.SerializeToUtf8Bytes(claims));

        var publicKey = Base64Url.Decode(keys.PublicKey);
        using var key = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            D = Base64Url.Decode(keys.PrivateKey),
            Q = new ECPoint { X = publicKey[1..33], Y = publicKey[33..] },
        });
        var signature = key.SignData(
            Encoding.ASCII.GetBytes(signingInput),
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation);

        return $"vapid t={signingInput}.{Base64Url.Encode(signature)}, k={keys.PublicKey}";
    }
}
