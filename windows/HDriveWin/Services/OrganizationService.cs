using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using HDriveWin.Models;

namespace HDriveWin.Services;

public sealed class RecentItem
{
    public string Name { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public bool IsDirectory { get; set; }
    public long Size { get; set; }
    public DateTime LastAccessDate { get; set; } = DateTime.UtcNow;
    public string ServerKey { get; set; } = string.Empty;
}

public sealed class TagColorDefinition
{
    public string Name { get; init; } = string.Empty;
    public string Hex { get; init; } = string.Empty;

    public static readonly IReadOnlyList<TagColorDefinition> All = new List<TagColorDefinition>
    {
        new() { Name = "Kırmızı", Hex = "#FF453A" },
        new() { Name = "Turuncu", Hex = "#FF9F0A" },
        new() { Name = "Sarı", Hex = "#FFD60A" },
        new() { Name = "Yeşil", Hex = "#30D158" },
        new() { Name = "Mavi", Hex = "#0A84FF" },
        new() { Name = "Mor", Hex = "#BF5AF2" },
        new() { Name = "Gri", Hex = "#8E8E93" }
    };
}

/// <summary>
/// Son Kullanılanlar (Recents) ve Dosya/Klasör Renk Etiketlerini (Tags) yöneten servis.
/// Owlfiles / macOS Finder eşdeğeridir.
/// </summary>
public sealed class OrganizationService
{
    public static OrganizationService Instance { get; } = new();

    private readonly object _lock = new();
    private readonly Dictionary<string, List<RecentItem>> _recentsCache = new();
    private readonly Dictionary<string, Dictionary<string, string>> _tagsCache = new();

    private OrganizationService() { }

    private static string GetStorageDirectory()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive");
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static string NormalizeServerKey(ServerConfig? server)
    {
        if (server == null) return "global";
        if (!string.IsNullOrEmpty(server.Username))
            return server.Username.Replace("@", "_").Replace(".", "_");
        if (!string.IsNullOrEmpty(server.Name))
            return server.Name.Replace(" ", "_");
        return "global";
    }

    private static string CleanPath(string path)
    {
        return (path ?? string.Empty).Trim('/').Trim();
    }

    public void AddRecent(ServerConfig? server, string path, string name, bool isDirectory, long size)
    {
        var key = NormalizeServerKey(server);
        var cleanPath = CleanPath(path);
        if (string.IsNullOrEmpty(cleanPath)) return;

        lock (_lock)
        {
            var list = EnsureRecentsLoaded(key);
            list.RemoveAll(r => r.Path.Equals(cleanPath, StringComparison.OrdinalIgnoreCase));
            list.Insert(0, new RecentItem
            {
                Name = name,
                Path = cleanPath,
                IsDirectory = isDirectory,
                Size = size,
                LastAccessDate = DateTime.UtcNow,
                ServerKey = key
            });

            if (list.Count > 50)
            {
                list.RemoveRange(50, list.Count - 50);
            }

            SaveRecents(key, list);
        }
    }

    public IReadOnlyList<RecentItem> GetRecents(ServerConfig? server)
    {
        var key = NormalizeServerKey(server);
        lock (_lock)
        {
            return EnsureRecentsLoaded(key).ToList();
        }
    }

    public void ClearRecents(ServerConfig? server)
    {
        var key = NormalizeServerKey(server);
        lock (_lock)
        {
            var list = EnsureRecentsLoaded(key);
            list.Clear();
            SaveRecents(key, list);
        }
    }

    public void SetTag(ServerConfig? server, string path, string colorHex)
    {
        var key = NormalizeServerKey(server);
        var cleanPath = CleanPath(path);
        if (string.IsNullOrEmpty(cleanPath)) return;

        lock (_lock)
        {
            var dict = EnsureTagsLoaded(key);
            dict[cleanPath] = colorHex;
            SaveTags(key, dict);
        }
    }

    public void RemoveTag(ServerConfig? server, string path)
    {
        var key = NormalizeServerKey(server);
        var cleanPath = CleanPath(path);
        if (string.IsNullOrEmpty(cleanPath)) return;

        lock (_lock)
        {
            var dict = EnsureTagsLoaded(key);
            if (dict.Remove(cleanPath))
            {
                SaveTags(key, dict);
            }
        }
    }

    public string? GetTag(ServerConfig? server, string path)
    {
        var key = NormalizeServerKey(server);
        var cleanPath = CleanPath(path);
        if (string.IsNullOrEmpty(cleanPath)) return null;

        lock (_lock)
        {
            var dict = EnsureTagsLoaded(key);
            return dict.TryGetValue(cleanPath, out var color) ? color : null;
        }
    }

    public Dictionary<string, string> GetAllTags(ServerConfig? server)
    {
        var key = NormalizeServerKey(server);
        lock (_lock)
        {
            return new Dictionary<string, string>(EnsureTagsLoaded(key), StringComparer.OrdinalIgnoreCase);
        }
    }

    private List<RecentItem> EnsureRecentsLoaded(string serverKey)
    {
        if (_recentsCache.TryGetValue(serverKey, out var cached))
            return cached;

        var file = Path.Combine(GetStorageDirectory(), $"recents_{serverKey}.json");
        List<RecentItem> list;
        try
        {
            if (File.Exists(file))
            {
                var json = File.ReadAllText(file);
                list = JsonSerializer.Deserialize<List<RecentItem>>(json) ?? new();
            }
            else
            {
                list = new();
            }
        }
        catch
        {
            list = new();
        }

        _recentsCache[serverKey] = list;
        return list;
    }

    private static void SaveRecents(string serverKey, List<RecentItem> list)
    {
        try
        {
            var file = Path.Combine(GetStorageDirectory(), $"recents_{serverKey}.json");
            var json = JsonSerializer.Serialize(list, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(file, json);
        }
        catch { }
    }

    private Dictionary<string, string> EnsureTagsLoaded(string serverKey)
    {
        if (_tagsCache.TryGetValue(serverKey, out var cached))
            return cached;

        var file = Path.Combine(GetStorageDirectory(), $"tags_{serverKey}.json");
        Dictionary<string, string> dict;
        try
        {
            if (File.Exists(file))
            {
                var json = File.ReadAllText(file);
                dict = JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new(StringComparer.OrdinalIgnoreCase);
            }
            else
            {
                dict = new(StringComparer.OrdinalIgnoreCase);
            }
        }
        catch
        {
            dict = new(StringComparer.OrdinalIgnoreCase);
        }

        _tagsCache[serverKey] = dict;
        return dict;
    }

    private static void SaveTags(string serverKey, Dictionary<string, string> dict)
    {
        try
        {
            var file = Path.Combine(GetStorageDirectory(), $"tags_{serverKey}.json");
            var json = JsonSerializer.Serialize(dict, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(file, json);
        }
        catch { }
    }
}

