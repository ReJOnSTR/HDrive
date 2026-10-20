using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using HDriveWin.Models;

namespace HDriveWin.Services;

/// <summary>Creates complete, isolated local copies before handing files to another app.</summary>
public static class FileExportService
{
    public static async Task<List<string>> PrepareAsync(WebDAVClient client, IReadOnlyList<FileItem> selection)
    {
        var paths = new List<string>();
        foreach (var item in selection)
        {
            var path = item.IsDirectory
                ? await client.DownloadFolderToCacheAsync(item.Path, item.Name)
                : await client.DownloadFileToCacheAsync(item.Path, item.Name);
            if (string.IsNullOrEmpty(path) || (item.IsDirectory ? !Directory.Exists(path) : !File.Exists(path)))
                throw new IOException($"Dosya indirilemedi: {item.Name}");

            // Other downloads must not evict a copy while the receiving app uses it.
            WorkingCache.Protect(path);
            paths.Add(path);
        }
        return paths;
    }
}
