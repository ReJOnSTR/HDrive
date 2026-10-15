using System.Text.Json;
using HDriveWin.Models;

namespace HDriveWin.Services;

public record OfflineEntry(string Id, string AccountName, string AccountId, string Identity, string RemotePath, string Name, string LocalPath);
public static class OfflineLibrary
{
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive", "Offline");
    public static string Destination(ServerConfig config, string remotePath, string name, string? root = null)
    {
        var identity = WebDAVClient.StorageIdentity(config);
        var id = S3RequestSigner.Hash(identity + "|" + remotePath);
        var directory = Path.Combine(root ?? Root, id); Directory.CreateDirectory(directory);
        var destination = Path.Combine(directory, WebDAVClient.SafeFileName(name));
        AtomicFile.WriteAllText(Path.Combine(directory, "entry.json"), JsonSerializer.Serialize(new OfflineEntry(id, config.Name, config.Id, identity, remotePath, name, destination)));
        return destination;
    }
    public static List<OfflineEntry> Entries(string? root = null)
    {
        if (!Directory.Exists(root ?? Root)) return new();
        return Directory.EnumerateDirectories(root ?? Root).Select(directory => JsonSerializer.Deserialize<OfflineEntry>(File.ReadAllText(Path.Combine(directory, "entry.json"))))
            .Where(entry => entry != null && File.Exists(entry.LocalPath)).Cast<OfflineEntry>().OrderBy(entry => entry.Name).ToList();
    }
}
public record CacheEntry(string Path, long Bytes, DateTime Modified, bool Protected);
public static class WorkingCache
{
    public static string Root => Path.Combine(Path.GetTempPath(), "HDriveCache");
    private static string PreferencesPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive", "cache-limit.json");
    public static long LimitBytes {
        get { return File.Exists(PreferencesPath) ? Math.Max(0, JsonSerializer.Deserialize<long>(File.ReadAllText(PreferencesPath))) : 1024L * 1024 * 1024; }
        set { if (value < 0) throw new ArgumentOutOfRangeException(nameof(value)); AtomicFile.WriteAllText(PreferencesPath, JsonSerializer.Serialize(value)); }
    }
    public static void Protect(string file)
    {
        if (Path.GetFullPath(file).StartsWith(Path.GetFullPath(Root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            AtomicFile.WriteAllText(Path.Combine(Path.GetDirectoryName(file)!, ".hdrive-protected"), "");
    }
    public static List<CacheEntry> Entries(string? root = null)
    {
        root ??= Root;
        if (!Directory.Exists(root)) return new();
        return Directory.EnumerateFiles(root, "*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint }).Where(file => !Path.GetFileName(file).StartsWith('.') && !file.EndsWith(".part"))
            .Select(file => {
                var info = new FileInfo(file);
                var directory = info.Directory; var protectedFile = false;
                while (directory != null && directory.FullName.StartsWith(Path.GetFullPath(root), StringComparison.OrdinalIgnoreCase)) {
                    if (File.Exists(Path.Combine(directory.FullName, ".hdrive-protected"))) { protectedFile = true; break; }
                    directory = directory.Parent;
                }
                return new CacheEntry(file, info.Length, info.LastWriteTimeUtc, protectedFile);
            }).ToList();
    }
    public static long Trim(long limit, string? root = null, TimeSpan? minimumAge = null)
    {
        var files = Entries(root); var total = files.Sum(file => file.Bytes); long removed = 0;
        foreach (var file in files.Where(file => !file.Protected && file.Modified <= DateTime.UtcNow - (minimumAge ?? TimeSpan.Zero)).OrderBy(file => file.Modified)) {
            if (total <= limit) break;
            File.Delete(file.Path); total -= file.Bytes; removed += file.Bytes;
        }
        return removed;
    }
}
