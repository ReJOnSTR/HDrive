using System;

namespace HDriveWin.Models;

public enum StorageProtocol
{
    WebDAV,
    S3,
    SMB,
    GoogleDrive,
    OneDrive
}

public class ServerConfig
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "Bulut Sunucum";
    public string ServerURL { get; set; } = "";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
    public StorageProtocol Protocol { get; set; } = StorageProtocol.WebDAV;
    public string BucketName { get; set; } = "";
    public string Region { get; set; } = "us-east-1";
    public string SmbShareName { get; set; } = "";
    public string ClientId { get; set; } = "";
    public string ClientSecret { get; set; } = "";
    public bool AutoSyncEnabled { get; set; } = true;

    public string ProviderName => Protocol switch
    {
        StorageProtocol.GoogleDrive => "Google Drive",
        StorageProtocol.OneDrive => "OneDrive",
        StorageProtocol.S3 => "Amazon S3",
        StorageProtocol.SMB => "SMB Paylaşımı",
        _ => "WebDAV"
    };

    public string GlyphIcon => Protocol switch
    {
        StorageProtocol.GoogleDrive => "\uE753", // Drive
        StorageProtocol.OneDrive => "\uE753", // Cloud
        StorageProtocol.S3 => "\uEDA2", // Database / Storage
        StorageProtocol.SMB => "\uE839", // Workstation / LAN
        _ => "\uE753"
    };

    public string Subtitle => $"{ProviderName} • {(string.IsNullOrEmpty(ServerURL) ? "Yerel / Bulut" : ServerURL)}";
}
