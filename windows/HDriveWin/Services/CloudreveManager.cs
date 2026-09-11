using System;
using System.IO;
using System.Text.Json;
using HDriveWin.Models;

namespace HDriveWin.Services;

public class CloudreveManager
{
    private static CloudreveManager? _instance;
    public static CloudreveManager Instance => _instance ??= new CloudreveManager();

    private readonly string _configFilePath;
    public ServerConfig ActiveServer { get; private set; }

    private CloudreveManager()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var dir = Path.Combine(appData, "HDrive");
        Directory.CreateDirectory(dir);
        _configFilePath = Path.Combine(dir, "config.json");

        ActiveServer = LoadConfig();
    }

    public void SaveConfig(ServerConfig config)
    {
        ActiveServer = config;
        try
        {
            if (!string.IsNullOrEmpty(config.Password))
            {
                CredentialService.SavePassword(config.Username, config.Password);
            }

            var cleanConfig = new ServerConfig
            {
                Name = config.Name,
                ServerURL = config.ServerURL,
                Username = config.Username,
                Password = ""
            };
            var json = JsonSerializer.Serialize(cleanConfig, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(_configFilePath, json);
        }
        catch { }
    }

    private ServerConfig LoadConfig()
    {
        try
        {
            if (File.Exists(_configFilePath))
            {
                var json = File.ReadAllText(_configFilePath);
                var cfg = JsonSerializer.Deserialize<ServerConfig>(json);
                if (cfg != null)
                {
                    var securePass = CredentialService.GetPassword(cfg.Username);
                    if (!string.IsNullOrEmpty(securePass))
                    {
                        cfg.Password = securePass;
                    }
                    else if (!string.IsNullOrEmpty(cfg.Password))
                    {
                        CredentialService.SavePassword(cfg.Username, cfg.Password);
                    }
                    return cfg;
                }
            }
        }
        catch { }

        return new ServerConfig();
    }
}
