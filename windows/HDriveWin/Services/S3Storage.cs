using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Xml.Linq;
using HDriveWin.Models;

namespace HDriveWin.Services;

internal static class S3RequestSigner
{
    internal static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    internal static string Encode(string text) => Uri.EscapeDataString(text);
    private static byte[] Hmac(byte[] key, string value) => HMACSHA256.HashData(key, Encoding.UTF8.GetBytes(value));

    public static void Sign(HttpRequestMessage request, ServerConfig config, DateTimeOffset? timestamp = null)
    {
        if (string.IsNullOrEmpty(config.Username) || string.IsNullOrEmpty(config.Password))
            throw new InvalidOperationException("S3 Access Key ve Secret Key gereklidir.");
        var uri = request.RequestUri!;
        var now = (timestamp ?? DateTimeOffset.UtcNow).UtcDateTime;
        var date = now.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
        var stamp = now.ToString("yyyyMMddTHHmmssZ", CultureInfo.InvariantCulture);
        var payload = request.Content == null ? Hash("") : "UNSIGNED-PAYLOAD";
        request.Headers.Host = uri.IsDefaultPort ? uri.IdnHost : uri.Authority;
        request.Headers.Remove("x-amz-date");
        request.Headers.Add("x-amz-date", stamp);
        request.Headers.Remove("x-amz-content-sha256");
        request.Headers.Add("x-amz-content-sha256", payload);
        var headers = request.Headers.Where(h => h.Key.Equals("Host", StringComparison.OrdinalIgnoreCase) || h.Key.StartsWith("x-amz-", StringComparison.OrdinalIgnoreCase))
            .Select(h => new KeyValuePair<string, string>(h.Key.ToLowerInvariant(), string.Join(",", h.Value).Trim()))
            .OrderBy(h => h.Key, StringComparer.Ordinal).ToArray();
        var signedHeaders = string.Join(";", headers.Select(h => h.Key));
        var canonicalHeaders = string.Concat(headers.Select(h => h.Key + ":" + h.Value + "\n"));
        var query = string.Join("&", uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2)).Select(p => Encode(Uri.UnescapeDataString(p[0])) + "=" + Encode(Uri.UnescapeDataString(p.Length > 1 ? p[1] : "")))
            .OrderBy(p => p, StringComparer.Ordinal));
        var canonical = $"{request.Method.Method}\n{uri.AbsolutePath}\n{query}\n{canonicalHeaders}\n{signedHeaders}\n{payload}";
        var region = string.IsNullOrWhiteSpace(config.Region) ? "us-east-1" : config.Region;
        var scope = $"{date}/{region}/s3/aws4_request";
        var toSign = $"AWS4-HMAC-SHA256\n{stamp}\n{scope}\n{Hash(canonical)}";
        var key = Hmac(Hmac(Hmac(Hmac(Encoding.UTF8.GetBytes("AWS4" + config.Password), date), region), "s3"), "aws4_request");
        var signature = Convert.ToHexString(Hmac(key, toSign)).ToLowerInvariant();
        request.Headers.Authorization = new AuthenticationHeaderValue("AWS4-HMAC-SHA256", $"Credential={config.Username}/{scope}, SignedHeaders={signedHeaders}, Signature={signature}");
    }
}

public partial class WebDAVClient
{
    private Uri S3BucketUri()
    {
        var endpoint = new Uri(_config.ServerURL.TrimEnd('/') + "/");
        var bucket = _config.BucketName.Trim('/');
        if (string.IsNullOrEmpty(bucket)) throw new InvalidOperationException("S3 bucket adı gereklidir.");
        if (endpoint.Host.StartsWith(bucket + ".", StringComparison.OrdinalIgnoreCase) || endpoint.AbsolutePath.TrimEnd('/').EndsWith("/" + bucket, StringComparison.Ordinal))
            return endpoint;
        return new Uri(endpoint.AbsoluteUri + Uri.EscapeDataString(bucket) + "/");
    }

    internal Uri S3ObjectUri(string key) => new(S3BucketUri().AbsoluteUri + string.Join("/", key.TrimStart('/').Split('/').Select(Uri.EscapeDataString)));

    private async Task<List<FileItem>> ListS3DirectoryAsync(string path)
    {
        var prefix = path.Trim('/');
        if (prefix.Length > 0) prefix += "/";
        var result = new List<FileItem>();
        string? token = null;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        do
        {
            var url = S3BucketUri().AbsoluteUri + "?list-type=2&delimiter=%2F&prefix=" + Uri.EscapeDataString(prefix);
            if (token != null) url += "&continuation-token=" + Uri.EscapeDataString(token);
            using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Get, url));
            response.EnsureSuccessStatusCode();
            var xml = XDocument.Parse(await response.Content.ReadAsStringAsync());
            foreach (var entry in xml.Root!.Elements())
            {
                string Get(string name) => entry.Elements().FirstOrDefault(e => e.Name.LocalName == name)?.Value ?? "";
                if (entry.Name.LocalName == "CommonPrefixes")
                {
                    var key = Get("Prefix");
                    result.Add(new FileItem { Name = key.TrimEnd('/').Split('/').Last(), Path = key, IsDirectory = true });
                }
                else if (entry.Name.LocalName == "Contents")
                {
                    var key = Get("Key");
                    if (key == prefix || key.EndsWith('/')) continue;
                    long.TryParse(Get("Size"), out var size);
                    DateTime.TryParse(Get("LastModified"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var modified);
                    result.Add(new FileItem { Name = key.Split('/').Last(), Path = key, Size = size, ModifiedDate = modified });
                }
            }
            token = xml.Root.Elements().FirstOrDefault(e => e.Name.LocalName == "NextContinuationToken")?.Value;
            if (token != null && !seen.Add(token)) throw new InvalidOperationException("S3 sunucusu aynı sayfa token'ını tekrarladı.");
        } while (!string.IsNullOrEmpty(token));
        return result.OrderByDescending(i => i.IsDirectory).ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    private async Task<bool> CreateS3FolderAsync(string path)
    {
        using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Put, S3ObjectUri(path.TrimEnd('/') + "/")) { Content = new ByteArrayContent(Array.Empty<byte>()) });
        return response.IsSuccessStatusCode;
    }

    private async Task<bool> DeleteS3Async(string path, bool isDirectory)
    {
        if (string.IsNullOrEmpty(path.Trim('/'))) throw new InvalidOperationException("Bucket kökü silinemez.");
        if (isDirectory)
            foreach (var item in await ListS3DirectoryAsync(path))
                if (!await DeleteS3Async(item.Path, item.IsDirectory)) return false;
        var key = isDirectory ? path.TrimEnd('/') + "/" : path;
        using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Delete, S3ObjectUri(key)));
        return response.IsSuccessStatusCode || response.StatusCode == System.Net.HttpStatusCode.NotFound;
    }

    private async Task<bool> MoveS3Async(string source, string destination, bool overwrite)
    {
        if (source.TrimEnd('/') == destination.TrimEnd('/')) return true;
        if (source.EndsWith('/'))
        {
            var prefix = source.Trim('/') + "/";
            var target = destination.Trim('/') + "/";
            if (target == prefix || target.StartsWith(prefix, StringComparison.Ordinal)) return false;
            if (!overwrite && (await ListS3DirectoryAsync(target)).Count != 0) return false;
            if (!await CopyS3FolderAsync(prefix, target, overwrite)) return false;
            return await DeleteS3Async(prefix, true);
        }
        if (!overwrite)
        {
            using var exists = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Head, S3ObjectUri(destination)));
            if (exists.IsSuccessStatusCode) return false;
            if (exists.StatusCode != System.Net.HttpStatusCode.NotFound) return false;
        }
        using var copy = await SendAuthorizedAsync(() =>
        {
            var request = new HttpRequestMessage(HttpMethod.Put, S3ObjectUri(destination));
            request.Headers.Add("x-amz-copy-source", "/" + Uri.EscapeDataString(_config.BucketName) + "/" + string.Join("/", source.TrimStart('/').Split('/').Select(Uri.EscapeDataString)));
            return request;
        });
        if (!copy.IsSuccessStatusCode) return false;
        var body = await copy.Content.ReadAsStringAsync();
        if (body.Contains("<Error", StringComparison.Ordinal)) return false;
        return await DeleteS3Async(source, false);
    }

    private async Task<bool> CopyS3FolderAsync(string source, string destination, bool overwrite)
    {
        if (!await CreateS3FolderAsync(destination)) return false;
        foreach (var item in await ListS3DirectoryAsync(source))
        {
            var target = destination + item.Path[source.Length..];
            if (item.IsDirectory)
            {
                if (!await CopyS3FolderAsync(item.Path, target, overwrite)) return false;
                continue;
            }
            if (!overwrite)
            {
                using var head = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Head, S3ObjectUri(target)));
                if (head.StatusCode != System.Net.HttpStatusCode.NotFound) return false;
            }
            using var response = await SendAuthorizedAsync(() => {
                var request = new HttpRequestMessage(HttpMethod.Put, S3ObjectUri(target));
                request.Headers.Add("x-amz-copy-source", "/" + Uri.EscapeDataString(_config.BucketName) + "/" + string.Join("/", item.Path.Split('/').Select(Uri.EscapeDataString)));
                return request;
            });
            if (!response.IsSuccessStatusCode || (await response.Content.ReadAsStringAsync()).Contains("<Error", StringComparison.Ordinal)) return false;
        }
        return true;
    }
}
