using System;

namespace HDriveWin.Models;

public enum StorageProtocol
{
    WebDAV,
    S3,
    SMB
}

public class ServerConfig
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "Bulut Sunucum";
    public string ServerURL { get; set; } = "http://driver-cloudreve-75b736-45-147-47-56.sslip.io/dav";
    public string Username { get; set; } = "hallsak55@gmail.com";
    public string Password { get; set; } = "";
    public StorageProtocol Protocol { get; set; } = StorageProtocol.WebDAV;
    public string BucketName { get; set; } = "";
    public string Region { get; set; } = "us-east-1";
    public string SmbShareName { get; set; } = "";
    public bool AutoSyncEnabled { get; set; } = true;
}
