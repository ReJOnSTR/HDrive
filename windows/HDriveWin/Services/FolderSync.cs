using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using HDriveWin.Models;

namespace HDriveWin.Services;

public enum SyncAction { None, Upload, Download, Conflict }
public enum SyncConflictPolicy { Skip, KeepLocal, KeepRemote, KeepBoth }
public record SyncBaseline(string LocalHash, string RemoteStamp);
public record SyncRow(string RelativePath, string LocalPath, string? RemotePath, string? LocalHash, string? RemoteStamp, SyncAction Action);
public sealed class FolderSynchronizer
{
    private readonly WebDAVClient _client;
    private readonly string _localRoot, _remoteRoot, _manifest;
    private readonly string[] _excludes;
    private Dictionary<string, SyncBaseline> _baseline = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _remoteDirectories = new(StringComparer.Ordinal);
    private readonly Dictionary<string, FileItem> _remoteFiles = new(StringComparer.Ordinal);
    public FolderSynchronizer(WebDAVClient client, string localRoot, string remoteRoot, string exclusions = ".git/**;node_modules/**;*.tmp;*.part")
    {
        _client = client; _localRoot = Path.GetFullPath(localRoot); _remoteRoot = remoteRoot;
        _excludes = exclusions.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        _manifest = Path.Combine(_localRoot, ".hdrive-sync-" + S3RequestSigner.Hash(WebDAVClient.StorageIdentity(client.Config) + "|" + remoteRoot) + ".json");
    }
    public static SyncAction Decide(string? local, string? remote, SyncBaseline? previous)
    {
        if (local == null && remote == null) return SyncAction.None;
        if (previous == null) return local == null ? SyncAction.Download : remote == null ? SyncAction.Upload : SyncAction.Conflict;
        if (local == null || remote == null) return SyncAction.Conflict; // Deletions require a deliberate choice.
        var localChanged = local != previous.LocalHash; var remoteChanged = remote != previous.RemoteStamp;
        return localChanged && remoteChanged ? SyncAction.Conflict : localChanged ? SyncAction.Upload : remoteChanged ? SyncAction.Download : SyncAction.None;
    }
    private bool Excluded(string path) => path.Split('/').Any(part => part.StartsWith(".hdrive-", StringComparison.Ordinal)) || _excludes.Any(pattern =>
        Regex.IsMatch(path, "^" + Regex.Escape(pattern).Replace("\\*\\*", ".*").Replace("\\*", "[^/]*").Replace("\\?", ".") + "$", RegexOptions.CultureInvariant) ||
        (!pattern.Contains('/') && path.Split('/').Any(part => Regex.IsMatch(part, "^" + Regex.Escape(pattern).Replace("\\*", ".*").Replace("\\?", ".") + "$", RegexOptions.CultureInvariant))));
    private static string Stamp(FileItem item) => item.Path + "|" + item.Size + "|" + item.ModifiedDate?.ToUniversalTime().Ticks;
    private static async Task<string> HashAsync(string file, CancellationToken ct) {
        await using var stream = File.OpenRead(file); return Convert.ToHexString(await SHA256.HashDataAsync(stream, ct));
    }
    public async Task<List<SyncRow>> PreviewAsync(CancellationToken ct = default)
    {
        if (!Directory.Exists(_localRoot)) throw new DirectoryNotFoundException(_localRoot);
        if (File.Exists(_manifest)) _baseline = JsonSerializer.Deserialize<Dictionary<string, SyncBaseline>>(await File.ReadAllTextAsync(_manifest, ct)) ?? throw new InvalidDataException("Eşitleme kaydı bozuk; üzerine yazılmadı.");
        var local = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var file in Directory.EnumerateFiles(_localRoot, "*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = FileAttributes.ReparsePoint })) {
            var relative = Path.GetRelativePath(_localRoot, file).Replace('\\', '/');
            if (!Excluded(relative)) local[relative] = await HashAsync(file, ct);
        }
        _remoteFiles.Clear(); _remoteDirectories.Clear(); _remoteDirectories[""] = _remoteRoot;
        var pending = new Queue<(string Relative, string Remote)>(); pending.Enqueue(("", _remoteRoot));
        var visited = new HashSet<string>(StringComparer.Ordinal);
        while (pending.Count > 0) {
            ct.ThrowIfCancellationRequested(); var folder = pending.Dequeue();
            if (!visited.Add(folder.Remote)) continue;
            foreach (var item in await _client.ListDirectoryAsync(folder.Remote).WaitAsync(ct)) {
                if (item.Name is "." or ".." || item.Name.IndexOfAny(new[] { '/', '\\' }) >= 0 || WebDAVClient.SafeFileName(item.Name) != item.Name) throw new InvalidDataException("Güvenli olmayan uzak dosya adı.");
                var relative = folder.Relative.Length == 0 ? item.Name : folder.Relative + "/" + item.Name;
                if (Excluded(relative)) continue;
                if (item.IsDirectory) { _remoteDirectories[relative] = item.Path; pending.Enqueue((relative, item.Path)); }
                else if (!_remoteFiles.TryAdd(relative, item)) throw new InvalidDataException("Aynı adlı uzak dosyalar eşitleme için belirsiz: " + relative);
            }
        }
        return local.Keys.Union(_remoteFiles.Keys, StringComparer.Ordinal).OrderBy(path => path).Select(path => {
            local.TryGetValue(path, out var hash); _remoteFiles.TryGetValue(path, out var file); _baseline.TryGetValue(path, out var old);
            var stamp = file == null ? null : Stamp(file);
            return new SyncRow(path, Path.Combine(_localRoot, path.Replace('/', Path.DirectorySeparatorChar)), file?.Path, hash, stamp, Decide(hash, stamp, old));
        }).ToList();
    }
    private async Task<string> EnsureRemoteDirectoryAsync(string relative, CancellationToken ct)
    {
        if (_remoteDirectories.TryGetValue(relative, out var existing)) return existing;
        var separator = relative.LastIndexOf('/'); var parent = separator < 0 ? "" : relative[..separator]; var name = separator < 0 ? relative : relative[(separator + 1)..];
        var remoteParent = await EnsureRemoteDirectoryAsync(parent, ct);
        if (!await _client.CreateFolderAsync(remoteParent.TrimEnd('/') + "/" + name)) throw new IOException("Uzak klasör oluşturulamadı: " + relative);
        var folder = (await _client.ListDirectoryAsync(remoteParent).WaitAsync(ct)).Single(item => item.IsDirectory && item.Name == name);
        return _remoteDirectories[relative] = folder.Path;
    }
    public async Task<List<string>> ApplyAsync(IEnumerable<SyncRow> rows, SyncConflictPolicy policy = SyncConflictPolicy.Skip, CancellationToken ct = default)
    {
        var errors = new List<string>();
        foreach (var row in rows.Where(row => row.Action != SyncAction.None)) {
            ct.ThrowIfCancellationRequested();
            if (row.Action == SyncAction.Conflict && policy == SyncConflictPolicy.Skip) continue;
            try {
                var currentLocal = File.Exists(row.LocalPath) ? await HashAsync(row.LocalPath, ct) : null;
                if (currentLocal != row.LocalHash) throw new IOException("Önizlemeden sonra yerel dosya değişti; tekrar tarayın.");
                var separator = row.RelativePath.LastIndexOf('/'); var parent = separator < 0 ? "" : row.RelativePath[..separator]; var name = Path.GetFileName(row.LocalPath);
                var remoteParent = await EnsureRemoteDirectoryAsync(parent, ct);
                var before = (await _client.ListDirectoryAsync(remoteParent).WaitAsync(ct)).Where(item => !item.IsDirectory && item.Name == name).ToList();
                if (before.Count > 1 || (before.Count == 0 ? null : Stamp(before[0])) != row.RemoteStamp) throw new IOException("Önizlemeden sonra uzak dosya değişti; tekrar tarayın.");
                var action = row.Action;
                if (action == SyncAction.Conflict) {
                    if (policy == SyncConflictPolicy.KeepBoth && row.LocalHash != null && row.RemotePath != null) {
                        var copy = Path.Combine(Path.GetDirectoryName(row.LocalPath)!, Path.GetFileNameWithoutExtension(name) + " (yerel " + Guid.NewGuid().ToString("N")[..8] + ")" + Path.GetExtension(name));
                        File.Copy(row.LocalPath, copy);
                        await _client.UploadAsync(copy, remoteParent, ct: ct);
                        var copied = (await _client.ListDirectoryAsync(remoteParent).WaitAsync(ct)).Single(item => !item.IsDirectory && item.Name == Path.GetFileName(copy));
                        var copyPath = parent.Length == 0 ? Path.GetFileName(copy) : parent + "/" + Path.GetFileName(copy);
                        _baseline[copyPath] = new(await HashAsync(copy, ct), Stamp(copied));
                        AtomicFile.WriteAllText(_manifest, JsonSerializer.Serialize(_baseline));
                        action = SyncAction.Download;
                    } else action = policy == SyncConflictPolicy.KeepLocal ? SyncAction.Upload : SyncAction.Download;
                }
                if (action == SyncAction.Upload) {
                    if (row.LocalHash == null) throw new IOException("Yerel dosya yok; silme eşitlemesi otomatik uygulanmaz.");
                    await _client.UploadAsync(row.LocalPath, remoteParent, ct: ct, existingRemotePath: row.RemotePath);
                } else {
                    if (row.RemotePath == null) throw new IOException("Uzak dosya yok; silme eşitlemesi otomatik uygulanmaz.");
                    await _client.DownloadToAsync(row.RemotePath, row.LocalPath, ct: ct, fileName: name);
                }
                var updated = (await _client.ListDirectoryAsync(remoteParent).WaitAsync(ct)).Single(item => !item.IsDirectory && item.Name == name);
                _baseline[row.RelativePath] = new(await HashAsync(row.LocalPath, ct), Stamp(updated));
                AtomicFile.WriteAllText(_manifest, JsonSerializer.Serialize(_baseline));
            } catch (OperationCanceledException) { throw; }
            catch (Exception error) { errors.Add(row.RelativePath + ": " + error.Message); }
        }
        return errors;
    }
}
