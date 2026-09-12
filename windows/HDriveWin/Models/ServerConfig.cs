namespace HDriveWin.Models;

public class ServerConfig
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "Cloudreve Sunucum";
    public string ServerURL { get; set; } = "http://driver-cloudreve-75b736-45-147-47-56.sslip.io/dav";
    public string Username { get; set; } = "hallsak55@gmail.com";
    public string Password { get; set; } = "";
    public bool AutoSyncEnabled { get; set; } = true;
}
