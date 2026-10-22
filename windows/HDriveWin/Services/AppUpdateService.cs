using System.Net;
using System.Security.Cryptography;
using System.Text.Json;

namespace HDriveWin.Services;

public sealed record AppUpdateAsset(string Name, long Size, Uri Url, string? Sha256);
public sealed record AppRelease(string Tag, string Notes, AppUpdateAsset? WindowsAsset)
{
    public Uri PageUrl => new($"https://github.com/ReJOnSTR/HDrive/releases/tag/{Tag}");
    public bool IsNewerThan(string current) => AppUpdateService.ParseVersion(Tag) is { } next &&
        AppUpdateService.ParseVersion(current) is { } installed && next > installed;
}

public sealed class AppUpdateService
{
    public static readonly Uri ReleasesUrl = new("https://github.com/ReJOnSTR/HDrive/releases");
    private static readonly HttpClient DefaultHttp = new(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
        { Timeout = TimeSpan.FromMinutes(30) };
    private readonly HttpClient _http;
    public AppUpdateService(HttpClient? http = null) => _http = http ?? DefaultHttp;

    public static Version? ParseVersion(string value)
    {
        var clean = (value.StartsWith('v') ? value[1..] : value).Split('+')[0];
        var parts = clean.Split('.');
        return parts.Length == 3 && parts.All(p => p.Length > 0 && p.All(c => c >= '0' && c <= '9')) &&
            Version.TryParse(clean, out var version) ? version : null;
    }

    public static AppRelease Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        if (root.GetProperty("draft").GetBoolean() || root.GetProperty("prerelease").GetBoolean() ||
            ParseVersion(tag) is null || tag.Contains('+'))
            throw new InvalidDataException("Geçerli bir kararlı sürüm bulunamadı.");
        AppUpdateAsset? asset = null;
        foreach (var item in root.GetProperty("assets").EnumerateArray())
        {
            var name = item.GetProperty("name").GetString();
            var size = item.GetProperty("size").GetInt64();
            var url = item.GetProperty("browser_download_url").GetString();
            if (name != "HDrive-Setup.exe" || size <= 0 || size > 1_073_741_824 ||
                url != $"https://github.com/ReJOnSTR/HDrive/releases/download/{tag}/HDrive-Setup.exe") continue;
            var digest = item.TryGetProperty("digest", out var d) ? d.GetString() : null;
            var hash = digest?.StartsWith("sha256:", StringComparison.Ordinal) == true ? digest[7..].ToLowerInvariant() : null;
            if (hash is not { Length: 64 } || !hash.All(c => "0123456789abcdef".Contains(c))) hash = null;
            asset = new AppUpdateAsset(name, size, new Uri(url!), hash);
            break;
        }
        var notes = root.TryGetProperty("body", out var body) ? body.GetString() ?? "" : "";
        return new AppRelease(tag, notes, asset);
    }

    public async Task<AppRelease?> CheckAsync(CancellationToken cancellation = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        using var request = new HttpRequestMessage(HttpMethod.Get, "https://api.github.com/repos/ReJOnSTR/HDrive/releases/latest");
        request.Headers.UserAgent.ParseAdd("HDrive-Update-Check");
        request.Headers.Accept.ParseAdd("application/vnd.github+json");
        using var response = await _http.SendAsync(request, timeout.Token);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests)
            throw new HttpRequestException("Güncelleme kontrolü geçici olarak sınırlandı. Biraz sonra tekrar deneyin.");
        response.EnsureSuccessStatusCode();
        return Parse(await response.Content.ReadAsStringAsync(timeout.Token));
    }

    private async Task<HttpResponseMessage> DownloadResponseAsync(Uri url, CancellationToken cancellation)
    {
        for (var redirects = 0; redirects < 6; redirects++)
        {
            if (url.Scheme != "https" || url.Port != 443 || url.UserInfo.Length != 0 ||
                !new[] { "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com" }.Contains(url.Host))
                throw new InvalidDataException("Güncelleme paketi güvenilir bir adreste değil.");
            var response = await _http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellation);
            if ((int)response.StatusCode is >= 300 and < 400)
            {
                var location = response.Headers.Location;
                response.Dispose();
                if (location is null) throw new HttpRequestException("Güncelleme yönlendirmesi geçersiz.");
                url = location.IsAbsoluteUri ? location : new Uri(url, location);
                continue;
            }
            if (response.StatusCode == HttpStatusCode.OK) return response;
            response.Dispose();
            throw new HttpRequestException("Güncelleme paketi indirilemedi.");
        }
        throw new HttpRequestException("Güncelleme sunucusu çok fazla yönlendirme döndürdü.");
    }

    public async Task<string> DownloadAsync(AppRelease release, string current, string directory,
        IProgress<double>? progress = null, CancellationToken cancellation = default)
    {
        var asset = release.WindowsAsset;
        if (!release.IsNewerThan(current) || asset?.Sha256 is null || asset.Name != "HDrive-Setup.exe" ||
            asset.Url.AbsoluteUri != $"https://github.com/ReJOnSTR/HDrive/releases/download/{release.Tag}/HDrive-Setup.exe")
            throw new InvalidDataException("Bu sürüm için doğrulanabilir bir güncelleme paketi yok.");
        var staging = Path.Combine(directory, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            var target = Path.Combine(staging, asset.Name);
            var partial = target + ".part";
            using var response = await DownloadResponseAsync(asset.Url, cancellation);
            await using (var source = await response.Content.ReadAsStreamAsync(cancellation))
            await using (var output = new FileStream(partial, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
            using (var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256))
            {
                var buffer = new byte[81920];
                long total = 0;
                int count;
                while ((count = await source.ReadAsync(buffer, cancellation)) > 0)
                {
                    total += count;
                    if (total > asset.Size) throw new InvalidDataException("Güncelleme paketi boyutu beklenenden farklı.");
                    hash.AppendData(buffer, 0, count);
                    await output.WriteAsync(buffer.AsMemory(0, count), cancellation);
                    progress?.Report((double)total / asset.Size);
                }
                if (total != asset.Size || !Convert.ToHexString(hash.GetHashAndReset()).Equals(asset.Sha256, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("İndirilen paket doğrulanamadı. Lütfen tekrar indirin.");
            }
            cancellation.ThrowIfCancellationRequested();
            File.Move(partial, target);
            if (OperatingSystem.IsWindows())
                await File.WriteAllTextAsync(target + ":Zone.Identifier", "[ZoneTransfer]\r\nZoneId=3\r\nHostUrl=" + asset.Url.AbsoluteUri + "\r\n", cancellation);
            return target;
        }
        catch { try { Directory.Delete(staging, true); } catch { } throw; }
    }
}
