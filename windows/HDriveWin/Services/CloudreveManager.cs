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
    private bool _loadFailed;
    public string? StartupWarning { get; private set; }
    public ObservableCollection<ServerConfig> Servers { get; } = new();
    public ServerConfig? ActiveServer { get; private set; }

    private CloudreveManager() : this(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive")) { }

    internal CloudreveManager(string directory)
    {
        Directory.CreateDirectory(directory);
        _serversFilePath = Path.Combine(directory, "servers.json");
        _activeIdFilePath = Path.Combine(directory, "active_server_id.txt");
        _legacyConfigFilePath = Path.Combine(directory, "config.json");
        LoadServers();
    }

    public void SaveServer(ServerConfig config)
    {
        SaveSecrets(config); // Never remove plaintext until secure storage succeeds.
        config.IsConnected = true;
        var existing = Servers.FirstOrDefault(s => s.Id == config.Id);
        if (existing != null) Servers[Servers.IndexOf(existing)] = config;
        else Servers.Add(config);
        ActiveServer = config;
        Persist();
    }

    public void UpdateCredentials(ServerConfig config)
    {
        var saved = Servers.FirstOrDefault(s => s.Id == config.Id);
        if (saved == null || !saved.IsConnected || saved.Protocol != config.Protocol || saved.ServerURL != config.ServerURL || saved.Username != config.Username || saved.BucketName != config.BucketName || saved.SmbShareName != config.SmbShareName) return;
        saved.Password = config.Password;
        saved.RefreshToken = config.RefreshToken;
        saved.ClientSecret = config.ClientSecret;
        Persist();
    }

    public void SaveConfig(ServerConfig config) => SaveServer(config);

    public void SetActiveServer(ServerConfig config)
    {
        var saved = Servers.FirstOrDefault(s => s.Id == config.Id)
            ?? throw new InvalidOperationException("Hesap artık kayıtlı değil.");
        saved.IsConnected = true;
        ActiveServer = saved;
        Persist();
    }

    public void ClearActiveSelection()
    {
        ActiveServer = null;
        Persist();
    }

    public void ConnectServer(ServerConfig config) => SetActiveServer(config);

    public void DisconnectServer(ServerConfig config)
    {
        config.IsConnected = false;
        if (ActiveServer?.Id == config.Id)
            ActiveServer = Servers.FirstOrDefault(s => s.IsConnected && s.Id != config.Id);
        Persist();
    }

    public void DisconnectActiveServer()
    {
        if (ActiveServer != null) DisconnectServer(ActiveServer);
    }

    public void DeleteServer(ServerConfig config)
    {
        var existing = Servers.FirstOrDefault(server => server.Id == config.Id);
        if (existing == null) return;
        Servers.Remove(existing);
        if (ActiveServer?.Id == config.Id)
            ActiveServer = Servers.FirstOrDefault(s => s.IsConnected);
        Persist(); // Save the deletion before removing credentials.
        foreach (var key in new[] { config.Id, config.Id + "_rt", config.Id + "_cs" })
            CredentialService.DeletePassword(key);
        if (!string.IsNullOrEmpty(config.Username) && !Servers.Any(s => s.Username == config.Username))
            CredentialService.DeletePassword(config.Username);
    }

    private static void SaveSecrets(ServerConfig config)
    {
        if (!string.IsNullOrEmpty(config.Password) && CredentialService.GetPassword(config.Id) != config.Password) CredentialService.SavePassword(config.Id, config.Password);
        if (!string.IsNullOrEmpty(config.RefreshToken) && CredentialService.GetPassword(config.Id + "_rt") != config.RefreshToken) CredentialService.SavePassword(config.Id + "_rt", config.RefreshToken);
        if (!string.IsNullOrEmpty(config.ClientSecret) && CredentialService.GetPassword(config.Id + "_cs") != config.ClientSecret) CredentialService.SavePassword(config.Id + "_cs", config.ClientSecret);
    }

    private static ServerConfig WithoutSecrets(ServerConfig s) => new()
    {
        Id = s.Id, Name = s.Name, ServerURL = s.ServerURL, Username = s.Username,
        Protocol = s.Protocol, BucketName = s.BucketName, Region = s.Region,
        SmbShareName = s.SmbShareName, ClientId = s.ClientId,
        Password = "", ClientSecret = "", RefreshToken = "",
        AutoSyncEnabled = s.AutoSyncEnabled, IsConnected = s.IsConnected
    };

    public void Persist()
    {
        if (_loadFailed)
            throw new IOException("Hesap dosyası okunamadığı için üzerine yazılmadı. Dosyayı ve yedeğini kontrol edin.");
        foreach (var server in Servers) SaveSecrets(server);
        var json = JsonSerializer.Serialize(Servers.Select(WithoutSecrets).ToList(), new JsonSerializerOptions { WriteIndented = true });
        AtomicFile.WriteAllText(_serversFilePath, json);
        // Backups are sanitized too; never copy an old plaintext credential file.
        AtomicFile.WriteAllText(_serversFilePath + ".bak", json);
        if (ActiveServer is { IsConnected: true }) AtomicFile.WriteAllText(_activeIdFilePath, ActiveServer.Id);
        else if (File.Exists(_activeIdFilePath)) File.Delete(_activeIdFilePath);
    }

    private void LoadSecrets(ServerConfig server)
    {
        var password = CredentialService.GetPassword(server.Id);
        if (string.IsNullOrEmpty(password) && !string.IsNullOrEmpty(server.Username))
            password = CredentialService.GetPassword(server.Username);
        if (!string.IsNullOrEmpty(password)) server.Password = password;
        server.RefreshToken = CredentialService.GetPassword(server.Id + "_rt") ?? server.RefreshToken;
        server.ClientSecret = CredentialService.GetPassword(server.Id + "_cs") ?? server.ClientSecret;
        SaveSecrets(server);
    }

    private void LoadServers()
    {
        try
        {
            List<ServerConfig> accounts;
            var modernExists = File.Exists(_serversFilePath) || File.Exists(_serversFilePath + ".bak");
            if (modernExists)
            {
                try { accounts = ReadAccounts(_serversFilePath); }
                catch (Exception error)
                {
                    accounts = ReadAccounts(_serversFilePath + ".bak");
                    StartupWarning = "Hesap dosyası yedekten kurtarıldı: " + error.Message;
                }
                // An empty modern list is authoritative: do not resurrect config.json.
            }
            else if (File.Exists(_legacyConfigFilePath))
            {
                var legacy = JsonSerializer.Deserialize<ServerConfig>(File.ReadAllText(_legacyConfigFilePath))
                    ?? throw new InvalidDataException("Eski hesap dosyası boş.");
                accounts = new List<ServerConfig> { legacy };
            }
            else return;

            foreach (var account in accounts)
            {
                if (string.IsNullOrWhiteSpace(account.Id)) account.Id = Guid.NewGuid().ToString();
                LoadSecrets(account);
                Servers.Add(account);
            }
            var activeId = File.Exists(_activeIdFilePath) ? File.ReadAllText(_activeIdFilePath).Trim() : null;
            ActiveServer = Servers.FirstOrDefault(s => s.Id == activeId && s.IsConnected)
                ?? Servers.FirstOrDefault(s => s.IsConnected);
            Persist();
            if (!modernExists && File.Exists(_legacyConfigFilePath))
                AtomicFile.WriteAllText(_legacyConfigFilePath,
                    JsonSerializer.Serialize(WithoutSecrets(accounts.Single())));
        }
        catch (Exception error)
        {
            _loadFailed = true;
            StartupWarning = "Hesaplar yüklenemedi; mevcut dosyalar korundu. " + error.Message;
        }
    }

    private static List<ServerConfig> ReadAccounts(string path) =>
        JsonSerializer.Deserialize<List<ServerConfig>>(File.ReadAllText(path))
            ?? throw new InvalidDataException("Hesap dosyası geçersiz.");
}
