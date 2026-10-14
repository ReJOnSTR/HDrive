using System.Text.Json;
using HDriveWin.Models;

// Exercise the same default serializer options used by CloudreveManager.Persist.
// Evaluating IsActive or a brush getter fails immediately in PresentationStubs.
string[] expectedProperties =
[
    "Id", "Name", "ServerURL", "Username", "Password", "Protocol", "BucketName",
    "Region", "SmbShareName", "ClientId", "ClientSecret", "RefreshToken",
    "AutoSyncEnabled", "IsConnected"
];

foreach (var protocol in Enum.GetValues<StorageProtocol>())
{
    var config = new ServerConfig
    {
        Id = "serialization-fixture",
        Name = "Test account",
        ServerURL = "http://127.0.0.1:18087/dav",
        Username = "test-user",
        Password = "",
        Protocol = protocol,
        BucketName = "test-bucket",
        Region = "eu-west-1",
        SmbShareName = "test-share",
        ClientId = "test-client",
        ClientSecret = "test-secret",
        RefreshToken = "test-token",
        AutoSyncEnabled = false,
        IsConnected = false
    };

    var json = JsonSerializer.Serialize(new[] { config }, new JsonSerializerOptions { WriteIndented = true });
    using var document = JsonDocument.Parse(json);
    var names = document.RootElement[0].EnumerateObject().Select(p => p.Name).Order().ToArray();
    Require(names.SequenceEqual(expectedProperties.Order()), "Only account data should be persisted.");
    var reloaded = JsonSerializer.Deserialize<List<ServerConfig>>(json)!.Single();
    foreach (var name in expectedProperties)
    {
        var property = typeof(ServerConfig).GetProperty(name)!;
        Require(Equals(property.GetValue(config), property.GetValue(reloaded)), $"{protocol}: {name} was lost.");
    }
    Console.WriteLine($"PASS: {protocol} serializes without accessing the manager or WinUI and preserves account fields.");
}

// v1.2.7 has no Protocol, IsConnected, or presentation fields.
var legacy = JsonSerializer.Deserialize<ServerConfig>("""
    {"Id":"legacy-account","Name":"Legacy WebDAV","ServerURL":"http://127.0.0.1:18087/dav",
     "Username":"test-user","Password":"","AutoSyncEnabled":false}
    """)!;
Require(legacy.Protocol == StorageProtocol.WebDAV && legacy.IsConnected, "Legacy account defaults changed.");
Require(legacy.Id == "legacy-account" && !legacy.AutoSyncEnabled, "Legacy account data was lost.");
var migrated = JsonSerializer.Serialize(new[] { legacy });
var restored = JsonSerializer.Deserialize<List<ServerConfig>>(migrated)!.Single();
Require(restored.Id == legacy.Id && restored.ServerURL == legacy.ServerURL, "Legacy account cannot be persisted.");
Console.WriteLine("PASS: v1.2.7 account deserializes and can be saved in the multi-account format.");

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
