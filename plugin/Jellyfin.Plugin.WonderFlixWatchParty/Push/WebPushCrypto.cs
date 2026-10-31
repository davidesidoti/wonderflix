using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Push;

/// <summary>
/// La cifratura dei messaggi Web Push (RFC 8291, aes128gcm di RFC 8188):
/// un solo record, con una chiave del server nuova a ogni messaggio.
/// </summary>
public static class WebPushCrypto
{
    private const int RecordSize = 4096;
    private const int SaltBytes = 16;
    private const int AuthSecretBytes = 16;
    private const int PointBytes = 65;
    private const int TagBytes = 16;

    /// <summary>Il testo più lungo che sta nel record, con il delimitatore e il tag.</summary>
    public const int MaxPlaintext = RecordSize - 1 - TagBytes;

    private static readonly byte[] KeyInfo = Encoding.ASCII.GetBytes("WebPush: info\0");
    private static readonly byte[] CekInfo = Encoding.ASCII.GetBytes("Content-Encoding: aes128gcm\0");
    private static readonly byte[] NonceInfo = Encoding.ASCII.GetBytes("Content-Encoding: nonce\0");

    /// <summary>Cifra per l'iscrizione con chiave <c>p256dh</c> <paramref name="uaPublic"/> e segreto <c>auth</c>.</summary>
    /// <exception cref="ArgumentException">Se la chiave, il segreto o la lunghezza del testo non vanno.</exception>
    public static byte[] Encrypt(byte[] plaintext, byte[] uaPublic, byte[] authSecret)
    {
        using var serverKey = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
        return Encrypt(plaintext, uaPublic, authSecret, RandomNumberGenerator.GetBytes(SaltBytes), serverKey);
    }

    /// <summary>Come sopra, con il sale e la chiave del server dati (per i test).</summary>
    internal static byte[] Encrypt(
        byte[] plaintext, byte[] uaPublic, byte[] authSecret, byte[] salt, ECDiffieHellman serverKey)
    {
        if (plaintext.Length > MaxPlaintext)
        {
            throw new ArgumentException("Testo troppo lungo per un record.", nameof(plaintext));
        }

        if (authSecret.Length != AuthSecretBytes)
        {
            throw new ArgumentException("Il segreto auth deve essere di 16 byte.", nameof(authSecret));
        }

        using var uaKey = ImportPoint(uaPublic);
        var asPublic = ExportPoint(serverKey);
        var ecdhSecret = serverKey.DeriveRawSecretAgreement(uaKey.PublicKey);

        // §3.4: prima si mescola il segreto auth, poi il sale (RFC 8188 §2.2).
        var prkKey = HKDF.Extract(HashAlgorithmName.SHA256, ecdhSecret, authSecret);
        var ikm = HKDF.Expand(HashAlgorithmName.SHA256, prkKey, 32, [.. KeyInfo, .. uaPublic, .. asPublic]);
        var prk = HKDF.Extract(HashAlgorithmName.SHA256, ikm, salt);
        var cek = HKDF.Expand(HashAlgorithmName.SHA256, prk, 16, CekInfo);
        var nonce = HKDF.Expand(HashAlgorithmName.SHA256, prk, 12, NonceInfo);

        // Header: sale ‖ rs ‖ idlen ‖ keyid (la chiave pubblica del server).
        var header = new byte[SaltBytes + 4 + 1 + PointBytes];
        salt.CopyTo(header, 0);
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(SaltBytes), RecordSize);
        header[SaltBytes + 4] = PointBytes;
        asPublic.CopyTo(header, SaltBytes + 5);

        // Ultimo (e unico) record: delimitatore 0x02, nessun padding.
        byte[] padded = [.. plaintext, 0x02];
        var body = new byte[header.Length + padded.Length + TagBytes];
        header.CopyTo(body, 0);
        using var aes = new AesGcm(cek, TagBytes);
        aes.Encrypt(
            nonce,
            padded,
            body.AsSpan(header.Length, padded.Length),
            body.AsSpan(header.Length + padded.Length));
        return body;
    }

    private static ECDiffieHellman ImportPoint(byte[] uaPublic)
    {
        if (uaPublic.Length != PointBytes || uaPublic[0] != 0x04)
        {
            throw new ArgumentException("La chiave p256dh deve essere un punto P-256 non compresso.", nameof(uaPublic));
        }

        try
        {
            return ECDiffieHellman.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = uaPublic[1..33], Y = uaPublic[33..] },
            });
        }
        catch (CryptographicException e)
        {
            throw new ArgumentException("La chiave p256dh non è sulla curva P-256.", nameof(uaPublic), e);
        }
    }

    private static byte[] ExportPoint(ECDiffieHellman key)
    {
        var q = key.ExportParameters(false).Q;
        return [0x04, .. q.X!, .. q.Y!];
    }
}
