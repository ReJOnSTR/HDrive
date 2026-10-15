using System.Net.Http;
using System.Text;
using System.Text.Json;
using HDriveWin.Models;

namespace HDriveWin.Services;

public record CloudVersion(string Id, string Modified, bool CanRestore);
public record CloudTrashItem(string Id, string Name);

public partial class WebDAVClient
{
    public string SystemConnectionTarget()
    {
        if (_config.Protocol == StorageProtocol.SMB) return GetUncPath("");
        if (_config.Protocol != StorageProtocol.WebDAV) throw new InvalidOperationException("Sistem bağlantısı WebDAV ve SMB hesapları için kullanılabilir.");
        var origin = new Uri(_config.ServerURL);
        if (origin.Scheme is not ("http" or "https")) throw new InvalidOperationException("Geçersiz WebDAV adresi.");
        var server = origin.Host + (origin.Scheme == "https" ? "@SSL" : "") + (origin.IsDefaultPort ? "" : "@" + origin.Port);
        var path = string.Join("\\", origin.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries).Select(Uri.UnescapeDataString));
        return "\\\\" + server + "\\DavWWWRoot" + (path.Length == 0 ? "" : "\\" + path);
    }

    private async Task<JsonDocument> ActionAsync(HttpMethod method, string address, object? body = null)
    {
        var uri = new Uri(address);
        var expected = _config.Protocol == StorageProtocol.GoogleDrive ? "www.googleapis.com" : "graph.microsoft.com";
        if (_config.Protocol is not (StorageProtocol.GoogleDrive or StorageProtocol.OneDrive) || uri.Scheme != "https" || uri.Host != expected || !uri.IsDefaultPort)
            throw new InvalidOperationException("Bu sağlayıcı bu işlemi desteklemiyor.");
        using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(method, uri) {
            Content = body == null ? null : new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
        });
        response.EnsureSuccessStatusCode();
        var text = await response.Content.ReadAsStringAsync();
        return JsonDocument.Parse(string.IsNullOrWhiteSpace(text) ? "{}" : text);
    }
    public async Task<bool> MoveToTrashAsync(string path, bool isDirectory)
    {
        if (_config.Protocol != StorageProtocol.GoogleDrive) return await DeleteAsync(path, isDirectory);
        using var result = await ActionAsync(HttpMethod.Patch, $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(path.Trim('/'))}?supportsAllDrives=true", new { trashed = true });
        return true;
    }
    public async Task<Uri> ReadOnlyLinkAsync(string path, bool allowPublicAccess = false)
    {
        var id = Uri.EscapeDataString(path.Trim('/'));
        string address;
        object? body = null;
        if (_config.Protocol == StorageProtocol.GoogleDrive) {
            if (allowPublicAccess) {
                using var permission = await ActionAsync(HttpMethod.Post, $"https://www.googleapis.com/drive/v3/files/{id}/permissions?supportsAllDrives=true", new { type = "anyone", role = "reader" });
            }
            address = $"https://www.googleapis.com/drive/v3/files/{id}?fields=webViewLink&supportsAllDrives=true";
        } else {
            address = $"https://graph.microsoft.com/v1.0/me/drive/items/{id}" + (allowPublicAccess ? "/createLink" : "");
            if (allowPublicAccess) body = new { type = "view", scope = "anonymous" };
        }
        using var json = await ActionAsync(body == null ? HttpMethod.Get : HttpMethod.Post, address, body);
        var root = json.RootElement;
        string? link = root.TryGetProperty("webViewLink", out var google) ? google.GetString()
            : root.TryGetProperty("webUrl", out var one) ? one.GetString()
            : root.TryGetProperty("link", out var data) && data.TryGetProperty("webUrl", out var nested) ? nested.GetString() : null;
        if (!Uri.TryCreate(link, UriKind.Absolute, out var url) || url.Scheme != "https") throw new InvalidDataException("Paylaşım bağlantısı alınamadı.");
        return url;
    }
    public async Task RevokePublicLinksAsync(string path)
    {
        var google = _config.Protocol == StorageProtocol.GoogleDrive;
        var id = Uri.EscapeDataString(path.Trim('/'));
        var address = google ? $"https://www.googleapis.com/drive/v3/files/{id}/permissions" : $"https://graph.microsoft.com/v1.0/me/drive/items/{id}/permissions";
        var initial = address + (google ? "?fields=nextPageToken,permissions(id,type)&pageSize=100&supportsAllDrives=true" : "");
        string? page = initial; var seen = new HashSet<string>(); var publicIds = new List<string>();
        while (page != null) {
            if (!seen.Add(page)) throw new InvalidDataException("Sayfalama bağlantısı tekrarlandı.");
            using var json = await ActionAsync(HttpMethod.Get, page);
            if (json.RootElement.TryGetProperty(google ? "permissions" : "value", out var permissions))
                foreach (var permission in permissions.EnumerateArray()) {
                    var isPublic = permission.TryGetProperty("type", out var type) && type.GetString() == "anyone" ||
                        permission.TryGetProperty("link", out var link) && link.TryGetProperty("scope", out var scope) && scope.GetString() == "anonymous";
                    if (isPublic && permission.TryGetProperty("id", out var key)) publicIds.Add(key.GetString()!);
                }
            page = google ? json.RootElement.TryGetProperty("nextPageToken", out var token) ? initial + "&pageToken=" + Uri.EscapeDataString(token.GetString()!) : null
                : json.RootElement.TryGetProperty("@odata.nextLink", out var next) ? next.GetString() : null;
        }
        foreach (var key in publicIds) {
            using var deleted = await ActionAsync(HttpMethod.Delete, address + "/" + Uri.EscapeDataString(key) + (google ? "?supportsAllDrives=true" : ""));
        }
    }

    public async Task<List<CloudVersion>> VersionsAsync(string path)
    {
        var google = _config.Protocol == StorageProtocol.GoogleDrive;
        var id = Uri.EscapeDataString(path.Trim('/'));
        var initial = google ? $"https://www.googleapis.com/drive/v3/files/{id}/revisions?fields=nextPageToken,revisions(id,modifiedTime)&pageSize=200" : $"https://graph.microsoft.com/v1.0/me/drive/items/{id}/versions";
        string? address = initial;
        var seen = new HashSet<string>();
        var result = new List<CloudVersion>();
        while (address != null) {
            if (!seen.Add(address)) throw new InvalidDataException("Sayfalama bağlantısı tekrarlandı.");
            using var json = await ActionAsync(HttpMethod.Get, address);
            if (json.RootElement.TryGetProperty(google ? "revisions" : "value", out var rows))
                foreach (var row in rows.EnumerateArray()) result.Add(new(row.GetProperty("id").GetString()!, row.TryGetProperty(google ? "modifiedTime" : "lastModifiedDateTime", out var date) ? date.GetString() ?? "" : "", !google));
            address = google ? json.RootElement.TryGetProperty("nextPageToken", out var next) ? initial + "&pageToken=" + Uri.EscapeDataString(next.GetString()!) : null
                : json.RootElement.TryGetProperty("@odata.nextLink", out var link) ? link.GetString() : null;
        }
        return result;
    }
    public async Task RestoreVersionAsync(string path, string version)
    {
        if (_config.Protocol != StorageProtocol.OneDrive) throw new InvalidOperationException("Bu sağlayıcıda geri yükleme web arayüzünden yapılır.");
        using var result = await ActionAsync(HttpMethod.Post, $"https://graph.microsoft.com/v1.0/me/drive/items/{Uri.EscapeDataString(path.Trim('/'))}/versions/{Uri.EscapeDataString(version)}/restoreVersion", new { });
    }
    public async Task<List<CloudTrashItem>> TrashedFilesAsync()
    {
        if (_config.Protocol != StorageProtocol.GoogleDrive) throw new InvalidOperationException("Çöp kutusu listesi bu sağlayıcıda desteklenmiyor.");
        const string initial = "https://www.googleapis.com/drive/v3/files?q=trashed%3Dtrue&fields=nextPageToken,files(id,name)&pageSize=1000";
        string? address = initial;
        var result = new List<CloudTrashItem>(); var seen = new HashSet<string>();
        while (address != null) {
            if (!seen.Add(address)) throw new InvalidDataException("Sayfalama bağlantısı tekrarlandı.");
            using var json = await ActionAsync(HttpMethod.Get, address);
            foreach (var row in json.RootElement.GetProperty("files").EnumerateArray()) result.Add(new(row.GetProperty("id").GetString()!, row.GetProperty("name").GetString()!));
            address = json.RootElement.TryGetProperty("nextPageToken", out var token) ? initial + "&pageToken=" + Uri.EscapeDataString(token.GetString()!) : null;
        }
        return result;
    }
    public async Task RestoreTrashAsync(string path)
    {
        using var result = await ActionAsync(HttpMethod.Patch, $"https://www.googleapis.com/drive/v3/files/{Uri.EscapeDataString(path)}?supportsAllDrives=true", new { trashed = false });
    }
}
