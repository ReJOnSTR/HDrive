using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using HDriveWin.Models;

namespace HDriveWin.Services;

public class CloudreveManager
{
    private static CloudreveManager? _instance;
    public static CloudreveManager Instance => _instance ??= new CloudreveManager();

    private readonly string _serversFilePath;
    private readonly string _legacyConfigFilePath;
    private readonly string _activeIdFilePath;

    public ObservableCollection<ServerConfig> Servers { get; } = new();

    private ServerConfig? _activeServer;
    public ServerConfig ActiveServer
    {
        get => _activeServer ??= Servers.FirstOrDefault() ?? new ServerConfig();
        private set => _activeServer = value;
    }

    private CloudreveManager()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var dir = Path.Combine(appData, "HDrive");
        Directory.CreateDirectory(dir);
        _serversFilePath = Path.Combine(dir, "servers.json");
        _activeIdFilePath = Path.Combine(dir, "active_server_id.txt");
        _legacyConfigFilePath = Path.Combine(dir, "config.json");

        LoadServers();
    }

    public void SaveServer(ServerConfig config)
    {
        if (!string.IsNullOrEmpty(config.Password))
        {
            CredentialService.SavePassword(config.Username, config.Password);
        }

        var existing = Servers.FirstOrDefault(s => s.Id == config.Id);
        if (existing != null)
        {
            var idx = Servers.IndexOf(existing);
            Servers[idx] = config;
        }
        else
        {
            Servers.Add(config);
        }

        ActiveServer = config;
        Persist();
    }

    public void SaveConfig(ServerConfig config) => SaveServer(config);

    public void SetActiveServer(ServerConfig config)
    {
        ActiveServer = config;
        try
        {
            File.WriteAllText(_activeIdFilePath, config.Id);
        }
        catch { }
    }

    public void DeleteServer(ServerConfig config)
    {
        Servers.Remove(config);
        if (ActiveServer?.Id == config.Id)
        {
            ActiveServer = Servers.FirstOrDefault() ?? new ServerConfig();
        }
        Persist();
    }

    private void Persist()
    {
        try
        {
            var sanitized = Servers.Select(s => new ServerConfig
            {
                Id = s.Id,
                Name = s.Name,
                ServerURL = s.ServerURL,
                Username = s.Username,
                Password = "", // Güvenlik: Düz metin şifre JSON'a yazılmaz, CredentialManager kullanılır
                Protocol = s.Protocol,
                BucketName = s.BucketName,
                Region = s.Region,
                SmbShareName = s.SmbShareName,
                AutoSyncEnabled = s.AutoSyncEnabled
            }).ToList();

            var json = JsonSerializer.Serialize(sanitized, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_serversFilePath, json);

            if (ActiveServer != null)
            {
                File.WriteAllText(_activeIdFilePath, ActiveServer.Id);
            }
        }
        catch { }
    }

    private void LoadServers()
    {
        try
        {
            if (File.Exists(_serversFilePath))
            {
                var json = File.ReadAllText(_serversFilePath);
                var list = JsonSerializer.Deserialize<List<ServerConfig>>(json);
                if (list != null && list.Count > 0)
                {
                    Servers.Clear();
                    foreach (var s in list)
                    {
                        var pass = CredentialService.GetPassword(s.Username);
                        if (!string.IsNullOrEmpty(pass))
                        {
                            s.Password = pass;
                        }
                        Servers.Add(s);
                    }

                    string? activeId = null;
                    if (File.Exists(_activeIdFilePath))
                    {
                        activeId = File.ReadAllText(_activeIdFilePath).Trim();
                    }

                    _activeServer = Servers.FirstOrDefault(s => s.Id == activeId) ?? Servers.FirstOrDefault();
                    return;
                }
            }
        }
        catch { }

        // Eski config.json'dan geçiş (Migration)
        try
        {
            if (File.Exists(_legacyConfigFilePath))
            {
                var json = File.ReadAllText(_legacyConfigFilePath);
                var legacy = JsonSerializer.Deserialize<ServerConfig>(json);
                if (legacy != null)
                {
                    var pass = CredentialService.GetPassword(legacy.Username);
                    if (!string.IsNullOrEmpty(pass)) legacy.Password = pass;
                    Servers.Clear();
                    Servers.Add(legacy);
                    _activeServer = legacy;
                    Persist();
                    return;
                }
            }
        }
        catch { }

        // Varsayılan hesap
        var def = new ServerConfig();
        Servers.Clear();
        Servers.Add(def);
        _activeServer = def;
    }
}
