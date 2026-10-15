using System;
using System.Security.Cryptography;
using System.Text;

namespace HDriveWin.Services;

internal sealed class OAuthLoginSession
{
    internal string State { get; } = Base64Url(RandomNumberGenerator.GetBytes(32));
    internal string Verifier { get; } = Base64Url(RandomNumberGenerator.GetBytes(64));
    internal string Challenge => Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(Verifier)));
    internal static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    internal bool Matches(string? state)
    {
        if (state == null) return false;
        return CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(State), Encoding.UTF8.GetBytes(state));
    }
}
