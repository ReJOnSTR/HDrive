using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;
using System.Runtime.InteropServices;
using HDriveWin.Models;

namespace HDriveWin.Services;

public class WebDAVClient
{
    private readonly ServerConfig _config;
    private readonly HttpClient _httpClient;
    public ServerConfig Config => _config;
    public HttpClient HttpClient => _httpClient;

    public WebDAVClient(ServerConfig config)
    {
        _config = config;
        var handler = new HttpClientHandler
        {
            AllowAutoRedirect = true
        };

        _httpClient = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(60)
        };

        if (_config.Protocol == StorageProtocol.GoogleDrive || _config.Protocol == StorageProtocol.OneDrive)
        {
            if (!string.IsNullOrEmpty(_config.Password))
            {
                _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _config.Password);
            }
        }
        else if (!string.IsNullOrEmpty(_config.Username) && !string.IsNullOrEmpty(_config.Password))
        {
            var credentials = Convert.ToBase64String(Encoding.UTF8.GetBytes($"{_config.Username}:{_config.Password}"));
            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", credentials);
        }
    }

    public Uri BuildUri(string relativePath)
    {
        var trimmed = relativePath?.Trim() ?? "";
        if (trimmed.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            trimmed.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return new Uri(trimmed);
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
                var s3Uri = BuildUri("/");
                var s3Req = new HttpRequestMessage(HttpMethod.Get, s3Uri);
                var s3Resp = await _httpClient.SendAsync(s3Req);
                if (s3Resp.IsSuccessStatusCode || s3Resp.StatusCode == System.Net.HttpStatusCode.Forbidden || (int)s3Resp.StatusCode == 400)
                {
                    return (true, "Amazon S3 / MinIO uç noktasına bağlanıldı!");
                }
                return (false, $"S3 sunucu yanıtı: {(int)s3Resp.StatusCode}");
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

    public async Task<string?> DownloadFileToCacheAsync(string remotePath)
    {
        var filename = Path.GetFileName(remotePath);
        var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
        Directory.CreateDirectory(cacheDir);
        var localPath = Path.Combine(cacheDir, filename);

        if (_config.Protocol == StorageProtocol.SMB)
        {
            await EnsureSmbConnectedAsync();
            return await Task.Run(() =>
            {
                try
                {
                    var unc = GetUncPath(remotePath);
                    File.Copy(unc, localPath, true);
                    return localPath;
                }
                catch
                {
                    return null;
                }
            });
        }

        var uri = BuildUri(remotePath);

        try
        {
            var response = await _httpClient.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            using var stream = await response.Content.ReadAsStreamAsync();
            using var fileStream = new FileStream(localPath, FileMode.Create, FileAccess.Write, FileShare.None);
            await stream.CopyToAsync(fileStream);

            return localPath;
        }
        catch
        {
            return null;
        }
    }

    public async Task<string?> DownloadFolderToCacheAsync(string remotePath)
    {
        var folderName = Path.GetFileName(remotePath.TrimEnd('/'));
        if (string.IsNullOrEmpty(folderName)) folderName = "HDriveFolder";
        var cacheDir = Path.Combine(Path.GetTempPath(), "HDriveCache");
        var localFolder = Path.Combine(cacheDir, folderName);
        Directory.CreateDirectory(localFolder);

        await DownloadFolderRecursiveInternalAsync(remotePath, localFolder);
        return localFolder;
    }

    private async Task DownloadFolderRecursiveInternalAsync(string remotePath, string localFolder)
    {
        Directory.CreateDirectory(localFolder);
        var items = await ListDirectoryAsync(remotePath);
        foreach (var item in items)
        {
            if (item.IsDirectory)
            {
                var subFolder = Path.Combine(localFolder, item.Name);
                await DownloadFolderRecursiveInternalAsync(item.Path, subFolder);
            }
            else
            {
                var destFile = Path.Combine(localFolder, item.Name);
                if (_config.Protocol == StorageProtocol.SMB)
                {
                    try
                    {
                        var unc = GetUncPath(item.Path);
                        File.Copy(unc, destFile, true);
                    }
                    catch { }
                }
                else
                {
                    var uri = BuildUri(item.Path);
                    try
                    {
                        var response = await _httpClient.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead);
                        if (response.IsSuccessStatusCode)
                        {
                            using var stream = await response.Content.ReadAsStreamAsync();
                            using var fileStream = new FileStream(destFile, FileMode.Create, FileAccess.Write, FileShare.None);
                            await stream.CopyToAsync(fileStream);
                        }
                    }
                    catch { }
                }
            }
        }
    }

    public async Task<bool> UploadFolderRecursiveAsync(string localFolderPath, string remoteParentPath)
    {
        var folderName = Path.GetFileName(localFolderPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (string.IsNullOrEmpty(folderName)) folderName = "YeniKlasor";
        var remoteFolder = remoteParentPath.TrimEnd('/') + "/" + folderName;
        await CreateFolderAsync(remoteFolder);

        try
        {
            foreach (var file in Directory.GetFiles(localFolderPath))
            {
                await UploadFileAsync(file, remoteFolder);
            }

            foreach (var subDir in Directory.GetDirectories(localFolderPath))
            {
                await UploadFolderRecursiveAsync(subDir, remoteFolder);
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
        var filename = Path.GetFileName(localFilePath);
        var remotePath = remoteDirectoryPath.TrimEnd('/') + "/" + filename;

        if (_config.Protocol == StorageProtocol.SMB)
        {
            await EnsureSmbConnectedAsync();
            return await Task.Run(() =>
            {
                try
                {
                    var uncDest = GetUncPath(remotePath);
                    var dir = Path.GetDirectoryName(uncDest);
                    if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                    {
                        Directory.CreateDirectory(dir);
                    }
                    File.Copy(localFilePath, uncDest, true);
                    return true;
                }
                catch
                {
                    return false;
                }
            });
        }

        var uri = BuildUri(remotePath);

        try
        {
            using var fileStream = File.OpenRead(localFilePath);
            using var content = new StreamContent(fileStream);
            var response = await _httpClient.PutAsync(uri, content);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> CreateFolderAsync(string remotePath)
    {
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
}
