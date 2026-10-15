using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Xml.Linq;
using System.Runtime.InteropServices;
using System.Diagnostics;
using HDriveWin.Models;

namespace HDriveWin.Services;

public partial class WebDAVClient
{
    private readonly ServerConfig _config;
    private readonly ServerConfig _sourceConfig;
    private readonly HttpClient _httpClient;
    public ServerConfig Config => _config;
    public HttpClient HttpClient => _httpClient;
    internal Action<ServerConfig> PersistCredentials { get; set; } = config => CloudreveManager.Instance.UpdateCredentials(config);

    public WebDAVClient(ServerConfig config, HttpClient? httpClient = null)
    {
        _sourceConfig = config;
        _config = new ServerConfig {
            Id = config.Id, Name = config.Name, ServerURL = config.ServerURL, Username = config.Username,
            Password = config.Password, Protocol = config.Protocol, BucketName = config.BucketName,
            Region = config.Region, SmbShareName = config.SmbShareName, ClientId = config.ClientId,
            ClientSecret = config.ClientSecret, RefreshToken = config.RefreshToken,
            AutoSyncEnabled = config.AutoSyncEnabled, IsConnected = config.IsConnected
        };
        var handler = new HttpClientHandler
        {
            AllowAutoRedirect = true
        };

        _httpClient = httpClient ?? new HttpClient(handler)
        {
            Timeout = TimeSpan.FromMinutes(30)
        };

        if (_config.Protocol == StorageProtocol.GoogleDrive || _config.Protocol == StorageProtocol.OneDrive)
        {
            if (!string.IsNullOrEmpty(_config.Password))
            {
                _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _config.Password);
            }
        }
        else if (_config.Protocol != StorageProtocol.S3 && !string.IsNullOrEmpty(_config.Username) && !string.IsNullOrEmpty(_config.Password))
        {
            var credentials = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{_config.Username}:{_config.Password}"));
            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", credentials);
        }
    }

    private async Task<bool> TryRefreshOAuthTokenAsync()
    {
        if (string.IsNullOrEmpty(_config.RefreshToken)) return false;

        try
        {
            var (success, newToken, newRefreshToken, _) = await OAuthHelper.RefreshOAuthTokenAsync(
                _config.Protocol, 
                _config.RefreshToken, 
                _config.ClientId, 
                _config.ClientSecret);

            if (success && !string.IsNullOrEmpty(newToken))
            {
                _config.Password = newToken;
                if (!string.IsNullOrEmpty(newRefreshToken)) _config.RefreshToken = newRefreshToken;
                PersistCredentials(_config);
                if (_sourceConfig.ServerURL == _config.ServerURL && _sourceConfig.Protocol == _config.Protocol && _sourceConfig.Username == _config.Username && _sourceConfig.BucketName == _config.BucketName && _sourceConfig.SmbShareName == _config.SmbShareName)
                {
                    _sourceConfig.Password = _config.Password;
                    _sourceConfig.RefreshToken = _config.RefreshToken;
                }
                _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", newToken);
                return true;
            }
        }
        catch { }

        return false;
    }

    public Uri BuildUri(string relativePath)
    {
        var trimmed = relativePath?.Trim() ?? "";
        if (trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            var absolute = new Uri(trimmed);
            var origin = new Uri(_config.ServerURL);
            if (absolute.Scheme != origin.Scheme || absolute.Host != origin.Host || absolute.Port != origin.Port)
                throw new InvalidOperationException("Hesap kimliği farklı bir sunucuya gönderilemez.");
            return absolute;
        }

        var baseUriStr = _config.ServerURL.TrimEnd('/');
        if (_config.Protocol == StorageProtocol.S3 && !string.IsNullOrEmpty(_config.BucketName))
        {
            if (!baseUriStr.EndsWith("/" + _config.BucketName, StringComparison.OrdinalIgnoreCase))
            {
                baseUriStr = $"{baseUriStr}/{_config.BucketName}";
            }
        }
        var cleanPath = trimmed.TrimStart('/');

        // ServerURL'in yol bileşenini kontrol et (Örn: "/dav") ve çift eklemeyi önle
        if (Uri.TryCreate(_config.ServerURL, UriKind.Absolute, out var baseUri))
        {
            var basePath = baseUri.AbsolutePath.Trim('/');
            if (!string.IsNullOrEmpty(basePath))
            {
                if (cleanPath.Equals(basePath, StringComparison.OrdinalIgnoreCase))
                {
                    cleanPath = "";
                }
                else if (cleanPath.StartsWith(basePath + "/", StringComparison.OrdinalIgnoreCase))
                {
                    cleanPath = cleanPath.Substring(basePath.Length + 1);
                }
            }
        }

        if (string.IsNullOrEmpty(cleanPath))
        {
            return new Uri(baseUriStr + "/");
        }

        var segments = cleanPath.Split('/', StringSplitOptions.None);
        var encodedSegments = segments.Select(s => Uri.EscapeDataString(Uri.UnescapeDataString(s)));
        var encodedPath = string.Join("/", encodedSegments);

        var result = $"{baseUriStr}/{encodedPath}";
        if (trimmed.EndsWith("/") && !result.EndsWith("/"))
        {
            result += "/";
        }
        return new Uri(result);
    }

    #region Win32 SMB Authentication
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NETRESOURCE
    {
        public int dwScope;
        public int dwType;
        public int dwDisplayType;
        public int dwUsage;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? lpLocalName;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? lpRemoteName;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? lpComment;
        [MarshalAs(UnmanagedType.LPWStr)]
        public string? lpProvider;
    }

    [DllImport("mpr.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int WNetAddConnection2(ref NETRESOURCE lpNetResource, [MarshalAs(UnmanagedType.LPWStr)] string? lpPassword, [MarshalAs(UnmanagedType.LPWStr)] string? lpUsername, int dwFlags);

    public async Task<bool> EnsureSmbConnectedAsync()
    {
        if (_config.Protocol != StorageProtocol.SMB) return true;

        return await Task.Run(() =>
        {
            try
            {
                var unc = GetUncPath("/");
                if (Directory.Exists(unc)) return true;

                if (!string.IsNullOrEmpty(_config.Username) || !string.IsNullOrEmpty(_config.Password))
                {
                    var nr = new NETRESOURCE
                    {
                        dwType = 1, // RESOURCETYPE_DISK
                        lpRemoteName = unc
                    };
                    int ret = WNetAddConnection2(ref nr, _config.Password, _config.Username, 0);
                    // 0: NO_ERROR, 1219: ERROR_SESSION_CREDENTIAL_CONFLICT
                    if (ret == 0 || ret == 1219)
                    {
                        return Directory.Exists(unc);
                    }
                }
                return Directory.Exists(unc);
            }
            catch
            {
                return false;
            }
        });
    }
    #endregion

    public string GetUncPath(string relativePath)
    {
        var raw = _config.ServerURL.Trim().Replace('/', '\\');
        if (raw.StartsWith("smb:\\\\", StringComparison.OrdinalIgnoreCase))
        {
            raw = "\\\\" + raw.Substring(6).TrimStart('\\');
        }
        else if (raw.StartsWith("smb:\\", StringComparison.OrdinalIgnoreCase))
        {
            raw = "\\\\" + raw.Substring(5).TrimStart('\\');
        }
        else if (!raw.StartsWith("\\\\"))
        {
            raw = "\\\\" + raw.TrimStart('\\');
        }

        if (!string.IsNullOrEmpty(_config.SmbShareName) && !raw.EndsWith(_config.SmbShareName, StringComparison.OrdinalIgnoreCase))
        {
            raw = Path.Combine(raw, _config.SmbShareName);
        }

        var rel = relativePath.Trim('/').Replace('/', '\\');
        return string.IsNullOrEmpty(rel) ? raw : Path.Combine(raw, rel);
    }

    public async Task<(bool Success, string Message)> TestConnectionAsync()
    {
        try
        {
            if (_config.Protocol == StorageProtocol.SMB)
            {
                await EnsureSmbConnectedAsync();
                return await Task.Run(() =>
                {
                    try
                    {
                        var unc = GetUncPath("/");
                        if (Directory.Exists(unc))
                        {
                            return (true, "SMB Ağ Paylaşımına başarıyla bağlanıldı!");
                        }
                        return (false, $"Ağ paylaşımına erişilemedi: {unc}\nLütfen sunucu adresi, paylaşım adı veya kimlik bilgilerini kontrol edin.");
                    }
                    catch (Exception ex)
                    {
                        return (false, $"SMB erişim hatası: {ex.Message}");
                    }
                });
            }

            if (_config.Protocol == StorageProtocol.S3)
            {
                await ListS3DirectoryAsync("");
                return (true, "S3 hesabı doğrulandı ve bucket listelendi.");
            }

            if (_config.Protocol == StorageProtocol.GoogleDrive)
            {
                if (string.IsNullOrEmpty(_config.Password))
                {
                    return (false, "Google Drive erişim tokenı bulunamadı. Lütfen 'Tarayıcı ile Giriş Yap' butonuna tıklayarak hesabınızı bağlayın.");
                }
                var gReq = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/drive/v3/files?pageSize=1&supportsAllDrives=true");
                var gResp = await _httpClient.SendAsync(gReq);
                if (gResp.IsSuccessStatusCode)
                {
                    return (true, "Google Drive bağlantısı başarılı!");
                }
                if ((int)gResp.StatusCode == 401)
                {
                    if (await TryRefreshOAuthTokenAsync())
                    {
                        var retryReq = new HttpRequestMessage(HttpMethod.Get, "https://www.googleapis.com/drive/v3/files?pageSize=1&supportsAllDrives=true");
                        var retryResp = await _httpClient.SendAsync(retryReq);
                        if (retryResp.IsSuccessStatusCode)
                        {
                            return (true, "Google Drive bağlantısı başarılı (Token yenilendi)!");
                        }
                    }
                    return (false, "Google Drive oturumunun süresi dolmuş. Lütfen 'Tarayıcı ile Giriş Yap' butonuna tıklayarak yeniden bağlanın.");
                }
                return (false, $"Google Drive yanıtı: HTTP {(int)gResp.StatusCode} {gResp.ReasonPhrase}");
            }

            if (_config.Protocol == StorageProtocol.OneDrive)
            {
                if (string.IsNullOrEmpty(_config.Password))
                {
                    return (false, "OneDrive erişim tokenı bulunamadı. Lütfen 'Tarayıcı ile Giriş Yap' butonuna tıklayarak hesabınızı bağlayın.");
                }
                var odReq = new HttpRequestMessage(HttpMethod.Get, "https://graph.microsoft.com/v1.0/me/drive/root/children?$top=1");
                var odResp = await _httpClient.SendAsync(odReq);
                if (odResp.IsSuccessStatusCode)
                {
                    return (true, "Microsoft OneDrive bağlantısı başarılı!");
                }
                if ((int)odResp.StatusCode == 401)
                {
                    if (await TryRefreshOAuthTokenAsync())
                    {
                        var retryReq = new HttpRequestMessage(HttpMethod.Get, "https://graph.microsoft.com/v1.0/me/drive/root/children?$top=1");
                        var retryResp = await _httpClient.SendAsync(retryReq);
                        if (retryResp.IsSuccessStatusCode)
                        {
                            return (true, "Microsoft OneDrive bağlantısı başarılı (Token yenilendi)!");
                        }
                    }
                    return (false, "OneDrive oturumunun süresi dolmuş. Lütfen 'Tarayıcı ile Giriş Yap' butonuna tıklayarak yeniden bağlanın.");
                }
                return (false, $"OneDrive yanıtı: HTTP {(int)odResp.StatusCode} {odResp.ReasonPhrase}");
            }

            var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), BuildUri("/"))
            {
                Headers = { { "Depth", "0" } }
            };

            var response = await _httpClient.SendAsync(request);
            if (response.IsSuccessStatusCode || (int)response.StatusCode == 207)
            {
                return (true, "Bağlantı başarılı!");
            }

            return (false, $"Sunucu hatası: {(int)response.StatusCode} {response.ReasonPhrase}");
        }
        catch (Exception ex)
        {
            return (false, $"Bağlantı başarısız: {ex.Message}");
        }
    }

    public async Task<List<FileItem>> ListDirectoryAsync(string relativePath)
    {
        if (_config.Protocol == StorageProtocol.S3) return await ListS3DirectoryAsync(relativePath);
        if (_config.Protocol == StorageProtocol.GoogleDrive)
        {
            return await ListGoogleDriveDirectoryAsync(relativePath);
        }

        if (_config.Protocol == StorageProtocol.OneDrive)
        {
            return await ListOneDriveDirectoryAsync(relativePath);
        }

        if (_config.Protocol == StorageProtocol.SMB)
        {
            await EnsureSmbConnectedAsync();
            return await Task.Run(() =>
            {
                var list = new List<FileItem>();
                var unc = GetUncPath(relativePath);
                if (!Directory.Exists(unc)) return list;

                var dirInfo = new DirectoryInfo(unc);
                foreach (var dir in dirInfo.GetDirectories())
                {
                    list.Add(new FileItem
                    {
                        Name = dir.Name,
                        Path = (relativePath.TrimEnd('/') + "/" + dir.Name).TrimStart('/'),
                        IsDirectory = true,
                        ModifiedDate = dir.LastWriteTime
                    });
                }
                foreach (var file in dirInfo.GetFiles())
                {
                    list.Add(new FileItem
                    {
                        Name = file.Name,
                        Path = (relativePath.TrimEnd('/') + "/" + file.Name).TrimStart('/'),
                        IsDirectory = false,
                        Size = file.Length,
                        ModifiedDate = file.LastWriteTime
                    });
                }
                return list;
            });
        }

        var items = new List<FileItem>();
        var uri = BuildUri(relativePath);

        var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), uri)
        {
            Headers = { { "Depth", "1" } }
        };

        var response = await _httpClient.SendAsync(request);
        if (!response.IsSuccessStatusCode && (int)response.StatusCode != 207)
        {
            return items;
        }

        var xmlContent = await response.Content.ReadAsStringAsync();
        if (string.IsNullOrWhiteSpace(xmlContent)) return items;

        try
        {
            var doc = XDocument.Parse(xmlContent);
            XNamespace d = "DAV:";
            if (doc.Root != null && doc.Root.Name.Namespace != XNamespace.None)
            {
                d = doc.Root.Name.Namespace;
            }

            var responses = doc.Descendants(d + "response");
            var cleanTarget = uri.AbsolutePath.TrimEnd('/');
            bool isFirst = true;

            foreach (var resp in responses)
            {
                var href = resp.Element(d + "href")?.Value ?? "";
                if (string.IsNullOrEmpty(href)) continue;

                var decodedHref = Uri.UnescapeDataString(href);
                var cleanHref = decodedHref.TrimEnd('/');

                // İstek atılan klasörün kendisini atla (ilk öğe veya hedef yol eşleşmesi)
                if (isFirst || cleanHref.Equals(cleanTarget, StringComparison.OrdinalIgnoreCase))
                {
                    isFirst = false;
                    continue;
                }
                isFirst = false;

                var isDirectory = resp.Descendants(d + "collection").Any() || decodedHref.EndsWith("/");

                var displayName = resp.Descendants(d + "displayname").FirstOrDefault()?.Value;
                if (string.IsNullOrEmpty(displayName))
                {
                    var cleanPathStr = decodedHref.TrimEnd('/');
                    var lastSlash = cleanPathStr.LastIndexOf('/');
                    displayName = lastSlash >= 0 ? cleanPathStr.Substring(lastSlash + 1) : cleanPathStr;
                }

                if (string.IsNullOrEmpty(displayName) || displayName == "." || displayName == "..") continue;

                long size = 0;
                var sizeStr = resp.Descendants(d + "getcontentlength").FirstOrDefault()?.Value;
                if (!string.IsNullOrEmpty(sizeStr))
                {
                    long.TryParse(sizeStr, out size);
                }

                DateTime modDate = DateTime.MinValue;
                var dateStr = resp.Descendants(d + "getlastmodified").FirstOrDefault()?.Value;
                if (!string.IsNullOrEmpty(dateStr) && DateTime.TryParse(dateStr, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsedDate))
                {
                    modDate = parsedDate;
                }

                var itemPath = relativePath.TrimEnd('/') + "/" + displayName;
                if (items.Any(i => i.Path.Equals(itemPath, StringComparison.OrdinalIgnoreCase))) continue;

                items.Add(new FileItem
                {
                    Name = displayName,
                    Path = itemPath,
                    IsDirectory = isDirectory,
                    Size = size,
                    ModifiedDate = modDate
                });
            }
        }
        catch { }

        // Mükerrer öğeleri temizle
        items = items.GroupBy(x => x.Path, StringComparer.OrdinalIgnoreCase).Select(g => g.First()).ToList();

        // Klasörleri önce, sonra dosyaları alfabetik sırala
        items.Sort((a, b) =>
        {
            if (a.IsDirectory != b.IsDirectory)
                return a.IsDirectory ? -1 : 1;
            return string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase);
        });

        return items;
    }

    public async Task<string?> DownloadFileToCacheAsync(string remotePath, string? preferredFileName = null)
    {
        var name = SafeFileName(preferredFileName ?? Path.GetFileName(remotePath.TrimEnd('/')));
        if (_config.Protocol == StorageProtocol.GoogleDrive)
        {
            var info = await GoogleMetadataAsync(remotePath);
            if (string.IsNullOrWhiteSpace(preferredFileName) && !string.IsNullOrWhiteSpace(info.Name)) name = SafeFileName(info.Name);
            name = NativeFileName(name, info.Mime);
        }
        var destination = CachePath(remotePath, name);
        await DownloadToAsync(remotePath, destination, fileName: name);
        return destination;
    }

    public async Task<string?> DownloadFolderToCacheAsync(string remotePath)
    {
        var folderName = Path.GetFileName(remotePath.TrimEnd('/'));
        if (string.IsNullOrEmpty(folderName)) folderName = "HDriveFolder";
        var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
        var localFolder = Path.Combine(Path.GetDirectoryName(CachePath(remotePath, "folder"))!, SafeFileName(folderName));
        Directory.CreateDirectory(localFolder);

        await DownloadFolderRecursiveInternalAsync(remotePath, localFolder);
        return localFolder;
    }

    private async Task DownloadFolderRecursiveInternalAsync(string remotePath, string localFolder)
    {
        Directory.CreateDirectory(localFolder);
        foreach (var item in await ListDirectoryAsync(remotePath))
        {
            var destination = Path.Combine(localFolder, SafeFileName(item.Name));
            if (item.IsDirectory) await DownloadFolderRecursiveInternalAsync(item.Path, destination);
            else await DownloadToAsync(item.Path, destination, fileName: item.Name);
        }
    }

    public async Task<bool> UploadFolderRecursiveAsync(string localFolderPath, string remoteParentPath)
    {
        var folderName = Path.GetFileName(localFolderPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (string.IsNullOrEmpty(folderName)) folderName = "YeniKlasor";
        var remoteFolder = remoteParentPath.TrimEnd('/') + "/" + folderName;
        if (!await CreateFolderAsync(remoteFolder)) return false;

        try
        {
            foreach (var file in Directory.GetFiles(localFolderPath))
            {
                if (!await UploadFileAsync(file, remoteFolder)) return false;
            }

            foreach (var subDir in Directory.GetDirectories(localFolderPath))
            {
                if (!await UploadFolderRecursiveAsync(subDir, remoteFolder)) return false;
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> UploadFileAsync(string localFilePath, string remoteDirectoryPath)
    {
        try { await UploadAsync(localFilePath, remoteDirectoryPath); return true; }
        catch (Exception error) { Debug.WriteLine(error); return false; }
    }

    public async Task<bool> CreateFolderAsync(string remotePath)
    {
        if (_config.Protocol == StorageProtocol.S3) return await CreateS3FolderAsync(remotePath);
        if (_config.Protocol == StorageProtocol.SMB)
        {
            await EnsureSmbConnectedAsync();
            return await Task.Run(() =>
            {
                try
                {
                    var unc = GetUncPath(remotePath);
                    Directory.CreateDirectory(unc);
                    return true;
                }
                catch
                {
                    return false;
                }
            });
        }

        if (_config.Protocol == StorageProtocol.GoogleDrive)
        {
            try
            {
                var folderName = Path.GetFileName(remotePath.TrimEnd('/'));
                var parentId = Path.GetDirectoryName(remotePath.TrimEnd('/'))?.Replace('\\', '/').Trim('/');
                if (string.IsNullOrEmpty(parentId) || parentId == ".") parentId = "root";

                var metadata = new { name = folderName, mimeType = "application/vnd.google-apps.folder", parents = new[] { parentId } };
                var json = JsonSerializer.Serialize(metadata);
                using var content = new StringContent(json, Encoding.UTF8, "application/json");
                var resp = await _httpClient.PostAsync("https://www.googleapis.com/drive/v3/files?supportsAllDrives=true", content);
                return resp.IsSuccessStatusCode;
            }
            catch
            {
                return false;
            }
        }

        if (_config.Protocol == StorageProtocol.OneDrive)
        {
            try
            {
                var folderName = Path.GetFileName(remotePath.TrimEnd('/'));
                var parentId = Path.GetDirectoryName(remotePath.TrimEnd('/'))?.Replace('\\', '/').Trim('/');
                string url = (string.IsNullOrEmpty(parentId) || parentId == "root" || parentId == ".")
                    ? "https://graph.microsoft.com/v1.0/me/drive/root/children"
                    : $"https://graph.microsoft.com/v1.0/me/drive/items/{parentId}/children";

                var body = new { name = folderName, folder = new { } };
                var json = JsonSerializer.Serialize(body);
                using var content = new StringContent(json, Encoding.UTF8, "application/json");
                var resp = await _httpClient.PostAsync(url, content);
                return resp.IsSuccessStatusCode;
            }
            catch
            {
                return false;
            }
        }

        var uri = BuildUri(remotePath);
        try
        {
            var request = new HttpRequestMessage(new HttpMethod("MKCOL"), uri);
            var response = await _httpClient.SendAsync(request);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> DeleteAsync(string remotePath, bool isDirectory = false)
    {
        if (_config.Protocol == StorageProtocol.S3) return await DeleteS3Async(remotePath, isDirectory);
        if (_config.Protocol == StorageProtocol.SMB)
        {
            await EnsureSmbConnectedAsync();
            return await Task.Run(() =>
            {
                try
                {
                    var unc = GetUncPath(remotePath);
                    if (Directory.Exists(unc))
                    {
                        Directory.Delete(unc, true);
                        return true;
                    }
                    if (File.Exists(unc))
                    {
                        File.Delete(unc);
                        return true;
                    }
                    return true;
                }
                catch
                {
                    return false;
                }
            });
        }

        if (_config.Protocol == StorageProtocol.GoogleDrive)
        {
            try
            {
                var cleanId = (remotePath ?? "").Trim().Trim('/');
                var resp = await _httpClient.DeleteAsync($"https://www.googleapis.com/drive/v3/files/{cleanId}?supportsAllDrives=true");
                return resp.IsSuccessStatusCode || resp.StatusCode == System.Net.HttpStatusCode.NotFound;
            }
            catch
            {
                return false;
            }
        }

        if (_config.Protocol == StorageProtocol.OneDrive)
        {
            try
            {
                var cleanId = (remotePath ?? "").Trim().Trim('/');
                var resp = await _httpClient.DeleteAsync($"https://graph.microsoft.com/v1.0/me/drive/items/{cleanId}");
                return resp.IsSuccessStatusCode || resp.StatusCode == System.Net.HttpStatusCode.NotFound;
            }
            catch
            {
                return false;
            }
        }

        var path = remotePath;
        if (isDirectory && !path.EndsWith("/"))
        {
            path += "/";
        }

        var uri = BuildUri(path);
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Delete, uri);
            request.Headers.Add("Depth", "infinity");
            var response = await _httpClient.SendAsync(request);

            if (response.IsSuccessStatusCode || response.StatusCode == System.Net.HttpStatusCode.NotFound || response.StatusCode == System.Net.HttpStatusCode.NoContent)
            {
                return true;
            }

            // Alternatif eğik çizgi ile dene (Bazı WebDAV sunucuları klasörler için / beklerken bazıları beklemez)
            var altPath = path.EndsWith("/") ? path.TrimEnd('/') : path + "/";
            var altUri = BuildUri(altPath);
            using var altRequest = new HttpRequestMessage(HttpMethod.Delete, altUri);
            altRequest.Headers.Add("Depth", "infinity");
            var altResponse = await _httpClient.SendAsync(altRequest);

            return altResponse.IsSuccessStatusCode || altResponse.StatusCode == System.Net.HttpStatusCode.NotFound || altResponse.StatusCode == System.Net.HttpStatusCode.NoContent;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> MoveAsync(string sourceRemotePath, string destRemotePath, bool overwrite = false)
    {
        if (_config.Protocol == StorageProtocol.S3) return await MoveS3Async(sourceRemotePath, destRemotePath, overwrite);
        if (_config.Protocol == StorageProtocol.SMB)
        {
            await EnsureSmbConnectedAsync();
            return await Task.Run(() =>
            {
                try
                {
                    var src = GetUncPath(sourceRemotePath);
                    var dst = GetUncPath(destRemotePath);
                    if (Directory.Exists(src))
                    {
                        Directory.Move(src, dst);
                        return true;
                    }
                    if (File.Exists(src))
                    {
                        if (overwrite && File.Exists(dst)) File.Delete(dst);
                        File.Move(src, dst);
                        return true;
                    }
                    return false;
                }
                catch
                {
                    return false;
                }
            });
        }

        var sourceUri = BuildUri(sourceRemotePath);
        var destUri = BuildUri(destRemotePath);
        try
        {
            var request = new HttpRequestMessage(new HttpMethod("MOVE"), sourceUri);
            request.Headers.Add("Destination", destUri.AbsoluteUri);
            request.Headers.Add("Overwrite", overwrite ? "T" : "F");
            var response = await _httpClient.SendAsync(request);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// RFC 4331 WebDAV depolama kotası ve kullanılan alanı sorgular
    /// </summary>
    public async Task<(long usedBytes, long totalBytes)?> GetQuotaAsync()
    {
        try
        {
            var uri = BuildUri("/");
            var request = new HttpRequestMessage(new HttpMethod("PROPFIND"), uri)
            {
                Headers = { { "Depth", "0" } },
                Content = new StringContent(
                    "<?xml version=\"1.0\" encoding=\"utf-8\" ?><D:propfind xmlns:D=\"DAV:\"><D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop></D:propfind>",
                    Encoding.UTF8,
                    "application/xml"
                )
            };

            var response = await _httpClient.SendAsync(request);
            if (!response.IsSuccessStatusCode && (int)response.StatusCode != 207) return null;

            var xml = await response.Content.ReadAsStringAsync();
            var doc = System.Xml.Linq.XDocument.Parse(xml);
            System.Xml.Linq.XNamespace d = "DAV:";
            if (doc.Root != null && doc.Root.Name.Namespace != System.Xml.Linq.XNamespace.None)
            {
                d = doc.Root.Name.Namespace;
            }

            var usedStr = doc.Descendants(d + "quota-used-bytes").FirstOrDefault()?.Value;
            var availStr = doc.Descendants(d + "quota-available-bytes").FirstOrDefault()?.Value;

            if (long.TryParse(usedStr, out long used) && long.TryParse(availStr, out long avail))
            {
                return (used, used + avail);
            }
        }
        catch { }
        return null;
    }

    #region Google Drive & OneDrive REST Helpers
    private async Task<List<FileItem>> ListGoogleDriveDirectoryAsync(string folderIdOrPath)
    {
        var clean = (folderIdOrPath ?? "").Trim().Trim('/');
        var parent = string.IsNullOrEmpty(clean) || clean == "." ? "root" : clean;
        var query = Uri.EscapeDataString($"'{parent.Replace("'", "\\'")}' in parents and trashed = false");
        var initial = $"https://www.googleapis.com/drive/v3/files?q={query}&fields=nextPageToken,files(id,name,mimeType,size,modifiedTime)&pageSize=1000&supportsAllDrives=true";
        var result = new List<FileItem>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        string? token = null;
        do
        {
            var url = initial + (token == null ? "" : "&pageToken=" + Uri.EscapeDataString(token));
            using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Get, url));
            response.EnsureSuccessStatusCode();
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            foreach (var file in document.RootElement.GetProperty("files").EnumerateArray())
            {
                var size = file.TryGetProperty("size", out var value) && long.TryParse(value.ToString(), out var bytes) ? bytes : 0;
                var modified = file.TryGetProperty("modifiedTime", out value) && DateTime.TryParse(value.GetString(), out var date) ? date : DateTime.MinValue;
                result.Add(new FileItem {
                    Name = NativeFileName(file.GetProperty("name").GetString() ?? "", file.GetProperty("mimeType").GetString() ?? ""),
                    Path = file.GetProperty("id").GetString() ?? "",
                    IsDirectory = file.GetProperty("mimeType").GetString() == "application/vnd.google-apps.folder",
                    Size = size, ModifiedDate = modified
                });
            }
            token = document.RootElement.TryGetProperty("nextPageToken", out var next) ? next.GetString() : null;
            if (token != null && !seen.Add(token)) throw new InvalidOperationException("Google Drive aynı sayfayı tekrarladı.");
        } while (!string.IsNullOrEmpty(token));
        return SortItems(result);
    }

    private async Task<List<FileItem>> ListOneDriveDirectoryAsync(string folderIdOrPath)
    {
        var clean = (folderIdOrPath ?? "").Trim().Trim('/');
        var folder = string.IsNullOrEmpty(clean) || clean is "root" or "."
            ? "root" : clean.Contains('/') ? "root:/" + string.Join("/", clean.Split('/').Select(Uri.EscapeDataString)) + ":" : "items/" + Uri.EscapeDataString(clean);
        string? url = $"https://graph.microsoft.com/v1.0/me/drive/{folder}/children?$top=1000";
        var result = new List<FileItem>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        while (!string.IsNullOrEmpty(url))
        {
            var uri = new Uri(url);
            if (uri.Scheme != "https" || uri.Host != "graph.microsoft.com" || !uri.IsDefaultPort || !seen.Add(url))
                throw new InvalidOperationException("OneDrive geçersiz bir sonraki sayfa bağlantısı döndürdü.");
            using var response = await SendAuthorizedAsync(() => new HttpRequestMessage(HttpMethod.Get, uri));
            response.EnsureSuccessStatusCode();
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            foreach (var file in document.RootElement.GetProperty("value").EnumerateArray())
            {
                var size = file.TryGetProperty("size", out var value) && long.TryParse(value.ToString(), out var bytes) ? bytes : 0;
                var modified = file.TryGetProperty("lastModifiedDateTime", out value) && DateTime.TryParse(value.GetString(), out var date) ? date : DateTime.MinValue;
                result.Add(new FileItem {
                    Name = file.GetProperty("name").GetString() ?? "", Path = file.GetProperty("id").GetString() ?? "",
                    IsDirectory = file.TryGetProperty("folder", out _), Size = size, ModifiedDate = modified
                });
            }
            url = document.RootElement.TryGetProperty("@odata.nextLink", out var next) ? next.GetString() : null;
        }
        return SortItems(result);
    }

    private static List<FileItem> SortItems(List<FileItem> items) => items
        .OrderByDescending(i => i.IsDirectory).ThenBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    #endregion
}
