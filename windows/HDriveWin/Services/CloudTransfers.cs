using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using HDriveWin.Models;

namespace HDriveWin.Services;

public readonly record struct TransferProgress(long TransferredBytes, long TotalBytes);

public partial class WebDAVClient
{
    private readonly SemaphoreSlim _refreshGate = new(1, 1);

    private async Task<HttpResponseMessage> SendAuthorizedAsync(Func<HttpRequestMessage> createRequest,
        CancellationToken ct = default, HttpCompletionOption completion = HttpCompletionOption.ResponseHeadersRead)
    {
        var originalToken = _config.Password;
        for (var attempt = 0; ; attempt++)
        {
            using var request = createRequest();
            if (_config.Protocol == StorageProtocol.S3) S3RequestSigner.Sign(request, _config);
            else if (_config.Protocol is StorageProtocol.GoogleDrive or StorageProtocol.OneDrive)
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _config.Password);
            var response = await _httpClient.SendAsync(request, completion, ct).ConfigureAwait(false);
            if (response.StatusCode != HttpStatusCode.Unauthorized || attempt != 0 ||
                _config.Protocol is not (StorageProtocol.GoogleDrive or StorageProtocol.OneDrive)) return response;
            await _refreshGate.WaitAsync(ct).ConfigureAwait(false);
            bool refreshed;
            try { refreshed = _config.Password != originalToken || await TryRefreshOAuthTokenAsync().ConfigureAwait(false); }
            finally { _refreshGate.Release(); }
            if (!refreshed) return response;
            response.Dispose();
        }
    }

    internal static string SafeFileName(string name)
    {
        name = Path.GetFileName(name.Replace('\\', '/'));
        foreach (var invalid in Path.GetInvalidFileNameChars()) name = name.Replace(invalid, '_');
        if (string.IsNullOrWhiteSpace(name) || name is "." or "..") return "download";
        return name;
    }

    internal string CachePath(string remotePath, string fileName)
    {
        var identity = $"{_config.Id}|{_config.Protocol}|{_config.ServerURL}|{remotePath}";
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity)));
        // A new working copy preserves local edits and always fetches the current remote version.
        return Path.Combine(Path.GetTempPath(), "HDriveCache", key, Guid.NewGuid().ToString("N"), SafeFileName(fileName));
    }

    internal static string NativeFileName(string name, string mime)
    {
        var extension = mime switch {
            "application/vnd.google-apps.document" => ".docx",
            "application/vnd.google-apps.spreadsheet" => ".xlsx",
            "application/vnd.google-apps.presentation" => ".pptx",
            "application/vnd.google-apps.drawing" => ".pdf",
            _ => ""
        };
        if (extension.Length == 0 || name.EndsWith(extension, StringComparison.OrdinalIgnoreCase) || name.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase)) return name;
        if (Path.GetExtension(name).ToLowerInvariant() is ".gdoc" or ".gsheet" or ".gslides") name = Path.GetFileNameWithoutExtension(name);
        return name + extension;
    }

    private async Task<(string Mime, string Name)> GoogleMetadataAsync(string path, CancellationToken ct = default)
    {
        var id = Uri.EscapeDataString(path.Trim('/'));
        var url = $"https://www.googleapis.com/drive/v3/files/{id}?fields=mimeType,name&supportsAllDrives=true";
        using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Get, url), ct).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct).ConfigureAwait(false));
        return (document.RootElement.GetProperty("mimeType").GetString() ?? "", document.RootElement.TryGetProperty("name", out var name) ? name.GetString() ?? "" : "");
    }

    private async Task<Uri> DownloadUriAsync(string path, string? fileName, CancellationToken ct)
    {
        var id = Uri.EscapeDataString(path.Trim('/'));
        if (_config.Protocol == StorageProtocol.OneDrive)
            return new Uri($"https://graph.microsoft.com/v1.0/me/drive/items/{id}/content");
        if (_config.Protocol == StorageProtocol.GoogleDrive)
        {
            var info = await GoogleMetadataAsync(path, ct).ConfigureAwait(false);
            if (info.Mime.StartsWith("application/vnd.google-apps.", StringComparison.Ordinal))
            {
                var exportMime = info.Mime switch
                {
                    "application/vnd.google-apps.document" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    "application/vnd.google-apps.spreadsheet" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    "application/vnd.google-apps.presentation" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                    _ => "application/pdf"
                };
                if (string.Equals(Path.GetExtension(fileName), ".pdf", StringComparison.OrdinalIgnoreCase)) exportMime = "application/pdf";
                return new Uri($"https://www.googleapis.com/drive/v3/files/{id}/export?mimeType={Uri.EscapeDataString(exportMime)}");
            }
            return new Uri($"https://www.googleapis.com/drive/v3/files/{id}?alt=media&supportsAllDrives=true");
        }
        return _config.Protocol == StorageProtocol.S3 ? S3ObjectUri(path) : BuildUri(path);
    }

    public async Task DownloadToAsync(string remotePath, string destination, IProgress<TransferProgress>? progress = null,
        CancellationToken ct = default, string? fileName = null)
    {
        var parent = Path.GetDirectoryName(Path.GetFullPath(destination))!;
        Directory.CreateDirectory(parent);
        var staging = Path.Combine(parent, ".hdrive-" + Guid.NewGuid().ToString("N") + ".part");
        try
        {
            if (_config.Protocol == StorageProtocol.SMB)
            {
                if (!await EnsureSmbConnectedAsync()) throw new IOException("SMB bağlantısı kurulamadı.");
                await using var input = new FileStream(GetUncPath(remotePath), FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true);
                await CopyToStagingAsync(input, staging, input.Length, progress, ct).ConfigureAwait(false);
            }
            else
            {
                var uri = await DownloadUriAsync(remotePath, fileName, ct).ConfigureAwait(false);
                using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Get, uri), ct).ConfigureAwait(false);
                response.EnsureSuccessStatusCode();
                await using var input = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
                await CopyToStagingAsync(input, staging, response.Content.Headers.ContentLength ?? -1, progress, ct).ConfigureAwait(false);
            }
            ct.ThrowIfCancellationRequested();
            File.Move(staging, destination, overwrite: true);
        }
        finally { if (File.Exists(staging)) File.Delete(staging); }
    }

    private static async Task CopyToStagingAsync(Stream input, string staging, long total,
        IProgress<TransferProgress>? progress, CancellationToken ct)
    {
        await using var output = new FileStream(staging, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true);
        var buffer = new byte[81920];
        long transferred = 0;
        int count;
        while ((count = await input.ReadAsync(buffer.AsMemory(), ct).ConfigureAwait(false)) != 0)
        {
            await output.WriteAsync(buffer.AsMemory(0, count), ct).ConfigureAwait(false);
            transferred += count;
            progress?.Report(new TransferProgress(transferred, total));
        }
        if (total >= 0 && transferred != total) throw new IOException("İndirme tamamlanmadı; mevcut dosya korundu.");
        await output.FlushAsync(ct).ConfigureAwait(false);
    }

    public async Task UploadAsync(string localPath, string remoteDirectory, IProgress<TransferProgress>? progress = null,
        CancellationToken ct = default, string? existingRemotePath = null)
    {
        var name = SafeFileName(Path.GetFileName(localPath));
        var remotePath = existingRemotePath ?? remoteDirectory.TrimEnd('/') + "/" + name;
        if (_config.Protocol == StorageProtocol.SMB)
        {
            if (!await EnsureSmbConnectedAsync()) throw new IOException("SMB bağlantısı kurulamadı.");
            var destination = GetUncPath(remotePath);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            var staging = destination + "." + Guid.NewGuid().ToString("N") + ".part";
            try
            {
                await using (var input = File.OpenRead(localPath))
                    await CopyToStagingAsync(input, staging, input.Length, progress, ct).ConfigureAwait(false);
                ct.ThrowIfCancellationRequested();
                File.Move(staging, destination, true);
            }
            finally { if (File.Exists(staging)) File.Delete(staging); }
            return;
        }

        HttpRequestMessage Request()
        {
            var stream = new FileStream(localPath, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true);
            var content = new ProgressStreamContent(stream, count => progress?.Report(new TransferProgress(count, stream.Length)), ct);
            content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            if (_config.Protocol == StorageProtocol.GoogleDrive)
            {
                if (existingRemotePath != null)
                    return new HttpRequestMessage(HttpMethod.Patch, $"https://www.googleapis.com/upload/drive/v3/files/{Uri.EscapeDataString(existingRemotePath.Trim('/'))}?uploadType=media&supportsAllDrives=true") { Content = content };
                var parent = string.IsNullOrEmpty(remoteDirectory.Trim('/')) ? "root" : remoteDirectory.Trim('/');
                var multipart = new MultipartContent("related");
                multipart.Add(new StringContent(JsonSerializer.Serialize(new { name, parents = new[] { parent } }), Encoding.UTF8, "application/json"));
                multipart.Add(content);
                return new HttpRequestMessage(HttpMethod.Post, "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true") { Content = multipart };
            }
            if (_config.Protocol == StorageProtocol.OneDrive)
            {
                var parent = remoteDirectory.Trim('/');
                var target = string.IsNullOrEmpty(parent) || parent == "root" ? "root" : "items/" + Uri.EscapeDataString(parent);
                var url = existingRemotePath != null
                    ? $"https://graph.microsoft.com/v1.0/me/drive/items/{Uri.EscapeDataString(existingRemotePath.Trim('/'))}/content"
                    : $"https://graph.microsoft.com/v1.0/me/drive/{target}:/{Uri.EscapeDataString(name)}:/content";
                return new HttpRequestMessage(HttpMethod.Put, url) { Content = content };
            }
            return new HttpRequestMessage(HttpMethod.Put, _config.Protocol == StorageProtocol.S3 ? S3ObjectUri(remotePath) : BuildUri(remotePath)) { Content = content };
        }
        using var response = await SendAuthorizedAsync(Request, ct).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
    }
}
