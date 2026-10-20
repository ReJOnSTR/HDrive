using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using HDriveWin.Models;
using HDriveWin.Services;

var failures = new List<string>();
var root = Path.Combine(Path.GetTempPath(), "hdrive-regression-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
string Profile() { var path = Path.Combine(root, Guid.NewGuid().ToString("N")); Directory.CreateDirectory(path); return path; }
ServerConfig Account(StorageProtocol protocol = StorageProtocol.WebDAV) => new() {
    Id = Guid.NewGuid().ToString(), ServerURL = "https://storage.example/dav", Name = "Fixture", Username = "access", Password = "secret", Protocol = protocol,
    ClientId = "fixture-client", ClientSecret = "fixture-client-secret", RefreshToken = "fixture-refresh", BucketName = "bucket"
};
WebDAVClient Client(ServerConfig config, Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler) => new(config, new HttpClient(new FixtureHandler(handler)));
HttpResponseMessage Json(string value, HttpStatusCode status = HttpStatusCode.OK) => new(status) { Content = new StringContent(value, Encoding.UTF8, "application/json") };
async Task Check(string name, Func<Task> action)
{
    CredentialService.FailWrites = false;
    try { await action(); Console.WriteLine("PASS: " + name); }
    catch (Exception error) { failures.Add(name + ": " + error); Console.Error.WriteLine("FAIL: " + name + ": " + error.Message); }
    finally { CredentialService.FailWrites = false; }
}
void Require(bool value, string message) { if (!value) throw new Exception(message); }
async Task MustFail(Func<Task> action) { try { await action(); } catch { return; } throw new Exception("Operation unexpectedly succeeded"); }

await Check("Legacy migration preserves credentials and a deleted account stays deleted", () => {
    var path = Profile(); var account = Account();
    File.WriteAllText(Path.Combine(path, "config.json"), JsonSerializer.Serialize(account));
    var manager = new CloudreveManager(path);
    Require(manager.Servers.Single().Password == "secret", "Password lost");
    var saved = File.ReadAllText(Path.Combine(path, "servers.json"));
    Require(!saved.Contains("fixture-refresh") && !saved.Contains("fixture-client-secret"), "Plaintext secrets persisted");
    Require(CredentialService.Values[account.Id + "_rt"] == "fixture-refresh", "Refresh token not migrated");
    manager.DeleteServer(manager.Servers.Single());
    Require(new CloudreveManager(path).Servers.Count == 0, "Deleted legacy account resurrected");
    return Task.CompletedTask;
});
await Check("Disconnect survives restart and legitimate server names are retained", () => {
    var path = Profile(); var manager = new CloudreveManager(path); var account = Account();
    account.ServerURL = "https://driver-cloudreve.example/dav";
    manager.SaveServer(account); manager.DisconnectServer(account);
    var restored = new CloudreveManager(path);
    Require(restored.Servers.Count == 1 && !restored.Servers[0].IsConnected && restored.ActiveServer == null, "Disconnected account reactivated or discarded");
    return Task.CompletedTask;
});
await Check("Vault failure preserves the last account file", async () => {
    var path = Profile(); var manager = new CloudreveManager(path); manager.SaveServer(Account());
    var saved = File.ReadAllText(Path.Combine(path, "servers.json"));
    manager.Servers[0].Password = "changed-secret";
    CredentialService.FailWrites = true;
    await MustFail(() => { manager.Persist(); return Task.CompletedTask; });
    Require(File.ReadAllText(Path.Combine(path, "servers.json")) == saved, "Account file was overwritten after vault failure");
});
await Check("Corrupt primary recovers from sanitized backup; corrupt backup blocks overwrites", async () => {
    var path = Profile(); var manager = new CloudreveManager(path); manager.SaveServer(Account());
    var main = Path.Combine(path, "servers.json"); File.WriteAllText(main, "invalid-json");
    var restored = new CloudreveManager(path);
    Require(restored.Servers.Count == 1 && restored.StartupWarning != null, "Backup recovery failed");
    File.WriteAllText(main, "invalid-json"); File.WriteAllText(main + ".bak", "invalid-backup");
    restored = new CloudreveManager(path);
    await MustFail(() => { restored.Persist(); return Task.CompletedTask; });
    Require(File.ReadAllText(main) == "invalid-json", "Corrupt profile was silently overwritten");
});
await Check("403 download preserves destination and removes partial files", async () => {
    var path = Path.Combine(Profile(), "report.txt"); File.WriteAllText(path, "original");
    var client = Client(Account(), (_, _) => Task.FromResult(Json("denied", HttpStatusCode.Forbidden)));
    await MustFail(() => client.DownloadToAsync("report.txt", path));
    Require(File.ReadAllText(path) == "original", "Existing destination was destroyed");
    Require(Directory.GetFiles(Path.GetDirectoryName(path)!).Length == 1, "Partial download left behind");
});
await Check("WebDAV rejects foreign origins before sending account credentials", async () => {
    var contacted = false;
    var client = Client(Account(), (_, _) => { contacted = true; return Task.FromResult(Json("{}")); });
    await MustFail(() => client.DownloadToAsync("https://attacker.example/file.txt", Path.Combine(Profile(), "file.txt")));
    Require(!contacted, "WebDAV account credentials were sent to a foreign server");
});
await Check("Cache isolates accounts, preserves filenames and fetches fresh copies", async () => {
    int count = 0;
    var account = Account();
    var first = Client(account, (_, _) => Task.FromResult(Json("version-" + ++count)));
    var one = await first.DownloadFileToCacheAsync("folder/report.txt", "report.txt");
    var two = await first.DownloadFileToCacheAsync("folder/report.txt", "report.txt");
    var second = Client(Account(), (_, _) => Task.FromResult(Json("other-account")));
    var three = await second.DownloadFileToCacheAsync("folder/report.txt", "report.txt");
    Require(one != two && one != three && File.ReadAllText(one!) != File.ReadAllText(two!), "Stale/cross-account cache reused");
    Require(Path.GetFileName(one) == "report.txt" && File.ReadAllText(three!) == "other-account", "Filename or account content changed");
});
await Check("Google download resolves native Sheets through the export API", async () => {
    var client = Client(Account(StorageProtocol.GoogleDrive), (request, _) => Task.FromResult(
        request.RequestUri!.Query.Contains("fields=") ? Json("{\"mimeType\":\"application/vnd.google-apps.spreadsheet\"}") :
        request.RequestUri.AbsolutePath.EndsWith("/export") && request.RequestUri.Query.Contains("spreadsheetml") ? Json("sheet-data") : Json("wrong-route", HttpStatusCode.BadRequest)));
    var path = Path.Combine(Profile(), "sheet.xlsx"); await client.DownloadToAsync("sheet-id", path, fileName: "sheet.xlsx");
    Require(File.ReadAllText(path) == "sheet-data", "Native file was not exported correctly");
});
await Check("Drag export downloads uncached files with matching names from different folders", async () => {
    var client = Client(Account(), (request, _) => Task.FromResult(Json(request.RequestUri!.AbsolutePath)));
    var paths = await FileExportService.PrepareAsync(client, new[] {
        new FileItem { Name = "report.txt", Path = "first/report.txt" },
        new FileItem { Name = "report.txt", Path = "second/report.txt" }
    });
    Require(paths.Count == 2 && paths[0] != paths[1], "Selected files collided");
    Require(File.ReadAllText(paths[0]).EndsWith("/first/report.txt") &&
        File.ReadAllText(paths[1]).EndsWith("/second/report.txt"), "Wrong content exported");
    Require(paths.All(path => Path.GetFileName(path) == "report.txt"), "Export filename changed");
    Require(paths.All(path => File.Exists(Path.Combine(Path.GetDirectoryName(path)!, ".hdrive-protected"))), "Export can be evicted while in use");
});
await Check("Drag export preserves a cloud folder name and downloads its nested content", async () => {
    var client = Client(Account(StorageProtocol.OneDrive), (request, _) => Task.FromResult(
        request.RequestUri!.AbsolutePath.EndsWith("/folder-id/children")
            ? Json("""{"value":[{"id":"nested-id","name":"Nested","folder":{}}]}""")
        : request.RequestUri.AbsolutePath.EndsWith("/nested-id/children")
            ? Json("""{"value":[{"id":"file-id","name":"notes.txt","file":{"mimeType":"text/plain"},"size":7}]}""")
        : request.RequestUri.AbsolutePath.EndsWith("/file-id/content")
            ? Json("content")
        : Json("wrong-route", HttpStatusCode.BadRequest)));
    var paths = await FileExportService.PrepareAsync(client, new[] {
        new FileItem { Name = "My Folder", Path = "folder-id", IsDirectory = true }
    });
    Require(Path.GetFileName(paths.Single()) == "My Folder", "Folder ID leaked into its local name");
    Require(File.ReadAllText(Path.Combine(paths.Single(), "Nested", "notes.txt")) == "content", "Folder exported empty/incomplete");
});
await Check("Drag export reports download failure instead of returning partial selection", async () => {
    var client = Client(Account(), (request, _) => Task.FromResult(
        request.RequestUri!.AbsolutePath.EndsWith("/missing.txt")
            ? Json("denied", HttpStatusCode.Forbidden) : Json("ready")));
    await MustFail(() => FileExportService.PrepareAsync(client, new[] {
        new FileItem { Name = "ready.txt", Path = "ready.txt" },
        new FileItem { Name = "missing.txt", Path = "missing.txt" }
    }));
});
await Check("OneDrive downloads use item content instead of generic WebDAV GET", async () => {
    var client = Client(Account(StorageProtocol.OneDrive), (request, _) => {
        Require(request.RequestUri!.AbsolutePath == "/v1.0/me/drive/items/item-id/content", "Wrong OneDrive download route");
        return Task.FromResult(Json("file-data"));
    });
    var path = Path.Combine(Profile(), "file.txt"); await client.DownloadToAsync("item-id", path);
    Require(File.ReadAllText(path) == "file-data", "Download content lost");
});
await Check("Google uploads use multipart/related and existing files use PATCH", async () => {
    var path = Path.Combine(Profile(), "report.txt"); File.WriteAllText(path, "content");
    var calls = 0;
    var client = Client(Account(StorageProtocol.GoogleDrive), async (request, _) => {
        if (++calls == 1) {
            Require(request.Method == HttpMethod.Post && request.Content!.Headers.ContentType!.MediaType == "multipart/related", "Wrong Google upload method/content type");
            Require((await request.Content!.ReadAsStringAsync()).Contains("folder-id"), "Parent folder missing");
        } else Require(request.Method == HttpMethod.Patch && request.RequestUri!.AbsolutePath.EndsWith("/original-id"), "Edited file was duplicated");
        return Json("{}");
    });
    await client.UploadAsync(path, "folder-id");
    await client.UploadAsync(path, "folder-id", existingRemotePath: "original-id");
});
await Check("OneDrive uploads address the selected parent folder", async () => {
    var path = Path.Combine(Profile(), "report.txt"); File.WriteAllText(path, "content");
    var client = Client(Account(StorageProtocol.OneDrive), (request, _) => {
        Require(request.Method == HttpMethod.Put && request.RequestUri!.AbsolutePath == "/v1.0/me/drive/items/folder-id:/report.txt:/content", "Wrong OneDrive upload route");
        return Task.FromResult(Json("{}"));
    });
    await client.UploadAsync(path, "folder-id");
});
await Check("401 retries once, saves rotated refresh token and keeps account selection", async () => {
    var profile = new CloudreveManager(Profile()); var account = Account(StorageProtocol.OneDrive); profile.SaveServer(account);
    var other = Account(); profile.SaveServer(other);
    var previousFactory = OAuthHelper.HttpClientFactory;
    OAuthHelper.HttpClientFactory = () => new HttpClient(new FixtureHandler((_, _) => Task.FromResult(Json("{\"access_token\":\"new-access\",\"refresh_token\":\"rotated-refresh\"}"))));
    try {
        var calls = 0;
        var client = Client(account, (request, _) => Task.FromResult(++calls == 1 ? Json("{}", HttpStatusCode.Unauthorized) : Json("content")));
        client.PersistCredentials = profile.UpdateCredentials;
        await client.DownloadToAsync("id", Path.Combine(Profile(), "file.txt"));
        Require(calls == 2 && account.RefreshToken == "rotated-refresh" && profile.ActiveServer?.Id == other.Id, "Refresh switched accounts or lost rotated token");
        Require(CredentialService.Values[account.Id + "_rt"] == "rotated-refresh", "Rotated token not saved securely");
    } finally { OAuthHelper.HttpClientFactory = previousFactory; }
});
await Check("Google and OneDrive listing follows all pages", async () => {
    var calls = 0;
    var google = Client(Account(StorageProtocol.GoogleDrive), (request, _) => {
        var second = request.RequestUri!.Query.Contains("pageToken="); calls++;
        return Task.FromResult(Json(second ? "{\"files\":[{\"id\":\"2\",\"name\":\"two\",\"mimeType\":\"text/plain\"}]}" : "{\"nextPageToken\":\"next\",\"files\":[{\"id\":\"1\",\"name\":\"one\",\"mimeType\":\"text/plain\"}]}"));
    });
    Require((await google.ListDirectoryAsync("")).Count == 2 && calls == 2, "Google pagination incomplete");
    calls = 0;
    var one = Client(Account(StorageProtocol.OneDrive), (_, _) => Task.FromResult(Json(++calls == 1 ? "{\"value\":[{\"id\":\"1\",\"name\":\"one\"}],\"@odata.nextLink\":\"https://graph.microsoft.com/next\"}" : "{\"value\":[{\"id\":\"2\",\"name\":\"two\"}]}")));
    Require((await one.ListDirectoryAsync("")).Count == 2 && calls == 2, "OneDrive pagination incomplete");
});
await Check("Foreign pagination URL is rejected before credentials can be sent", async () => {
    var calls = 0;
    var client = Client(Account(StorageProtocol.OneDrive), (_, _) => { calls++; return Task.FromResult(Json("{\"value\":[],\"@odata.nextLink\":\"https://attacker.example/steal\"}")); });
    await MustFail(async () => { await client.ListDirectoryAsync(""); });
    Require(calls == 1, "Foreign URL was contacted");
});
await Check("S3 listing signs requests and follows continuation tokens", async () => {
    var calls = 0; var account = Account(StorageProtocol.S3); account.ServerURL = "https://s3.example";
    var client = Client(account, (request, _) => {
        calls++;
        Require(request.Method == HttpMethod.Get && request.Headers.Authorization?.Scheme == "AWS4-HMAC-SHA256", "S3 request was not signed");
        Require(request.RequestUri!.AbsolutePath == "/bucket/" && request.RequestUri.Query.Contains("list-type=2"), "S3 used WebDAV listing");
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(calls == 1 ? "<ListBucketResult><Contents><Key>a.txt</Key><Size>1</Size></Contents><NextContinuationToken>next</NextContinuationToken></ListBucketResult>" : "<ListBucketResult><Contents><Key>b.txt</Key><Size>2</Size></Contents></ListBucketResult>") });
    });
    Require((await client.ListDirectoryAsync("")).Count == 2 && calls == 2, "S3 pagination incomplete");
    var denied = Client(account, (_, _) => Task.FromResult(Json("denied", HttpStatusCode.Forbidden)));
    Require(!(await denied.TestConnectionAsync()).Success, "S3 access denied reported as success");
});
await Check("Live edits stay on their owner account and preserve the original remote path", async () => {
    var account = Account(); var other = Account();
    var path = Path.Combine(Profile(), "report.txt"); File.WriteAllText(path, "initial");
    ServerConfig? owner = account; var sent = false;
    using var watcher = new LiveEditWatcherService(id => id == account.Id ? owner : other, config => Client(config, (request, _) => {
        Require(config.Id == account.Id && request.RequestUri!.AbsolutePath == "/dav/folder/report.txt", "Edit uploaded to wrong account/name");
        sent = true; return Task.FromResult(Json("{}"));
    }));
    watcher.WatchFile(path, "folder/report.txt", "folder", account);
    File.WriteAllText(path, "updated"); File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(2));
    await watcher.SyncFileAsync(path); Require(sent, "Edit was not uploaded");
    sent = false;
    account.BucketName = "other-bucket";
    File.WriteAllText(path, "after-account-edit"); File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(4));
    await watcher.SyncFileAsync(path); Require(!sent, "Edit followed a changed storage target");
    owner = null;
    File.WriteAllText(path, "after-deletion"); File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(5));
    await watcher.SyncFileAsync(path); Require(!sent, "Deleted account was silently reconnected");
});
await Check("OAuth sessions use independent state and an S256 PKCE challenge", () => {
    var a = new OAuthLoginSession(); var b = new OAuthLoginSession();
    Require(a.Matches(a.State) && !a.Matches(b.State) && !a.Matches(null), "OAuth state validation failed");
    Require(a.Verifier.Length >= 43 && a.Verifier.Length <= 128 && a.Challenge == OAuthLoginSession.Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(a.Verifier))), "Invalid PKCE challenge");
    return Task.CompletedTask;
});

await Check("Interrupted downloads resume with If-Range and preserve the existing target", async () => {
    var destination = Path.Combine(Profile(), "resume.txt"); File.WriteAllText(destination, "original");
    var calls = 0;
    var client = Client(Account(), (request, _) => {
        calls++;
        var response = new HttpResponseMessage(calls == 1 ? HttpStatusCode.OK : HttpStatusCode.PartialContent) { Content = new StringContent(calls == 1 ? "abc" : "def") };
        response.Headers.ETag = new EntityTagHeaderValue("\"revision-one\"");
        if (calls == 1) response.Content.Headers.ContentLength = 6;
        else {
            Require(request.Headers.Range?.Ranges.Single().From == 3 && request.Headers.IfRange?.EntityTag?.Tag == "\"revision-one\"", "Missing protected byte range");
            response.Content.Headers.ContentRange = new ContentRangeHeaderValue(3, 5, 6);
        }
        return Task.FromResult(response);
    });
    await MustFail(() => client.DownloadToAsync("file.txt", destination, allowResume: true));
    Require(File.ReadAllText(destination) == "original", "Interrupted download replaced destination");
    await client.DownloadToAsync("file.txt", destination, allowResume: true);
    Require(File.ReadAllText(destination) == "abcdef" && Directory.GetFiles(Path.GetDirectoryName(destination)!).Length == 1, "Resume corrupted content or leaked staging files");
});
await Check("Changed representations restart instead of appending stale bytes", async () => {
    var destination = Path.Combine(Profile(), "changed.txt"); var calls = 0;
    var client = Client(Account(), (_, _) => {
        var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(++calls == 1 ? "old" : "new-version") };
        response.Headers.ETag = new EntityTagHeaderValue(calls == 1 ? "\"old\"" : "\"new\"");
        if (calls == 1) response.Content.Headers.ContentLength = 20;
        return Task.FromResult(response);
    });
    await MustFail(() => client.DownloadToAsync("file", destination, allowResume: true));
    await client.DownloadToAsync("file", destination, allowResume: true);
    Require(File.ReadAllText(destination) == "new-version", "Changed resource was appended to stale bytes");
});
await Check("Transfer journals recover backups and never serialize account credentials", async () => {
    var path = Path.Combine(Profile(), "transfers.json"); var journal = new TransferJournal(path);
    journal.Load();
    var record = new TransferRecord(Guid.NewGuid(), "file.txt", "remote", "local", TransferDirection.Download, TransferStatus.Running, "account", "identity-hash", 12);
    journal.Save(new() { record }); File.WriteAllText(path, "broken");
    Require(new TransferJournal(path).Load().Single() == record, "Transfer backup failed");
    Require(!File.ReadAllText(path + ".bak").Contains("Password"), "Credentials persisted in transfer queue");
    File.WriteAllText(path + ".bak", "also-broken"); journal = new TransferJournal(path);
    await MustFail(() => { journal.Load(); return Task.CompletedTask; });
    await MustFail(() => { journal.Save(new()); return Task.CompletedTask; });
    Require(File.ReadAllText(path) == "broken", "Corrupt transfer queue was overwritten");
});
await Check("Offline copies isolate edited account targets and cache cleanup preserves working copies", () => {
    var directory = Profile(); var account = Account();
    var first = OfflineLibrary.Destination(account, "id", "report.txt", directory);
    account.ServerURL = "https://another.example";
    var second = OfflineLibrary.Destination(account, "id", "report.txt", directory);
    Require(first != second, "Offline copies leaked across storage identities");
    var cache = Profile(); var protectedDirectory = Path.Combine(cache, "working"); Directory.CreateDirectory(protectedDirectory);
    var keep = Path.Combine(protectedDirectory, "edit.txt"); File.WriteAllText(keep, "edited");
    File.WriteAllText(Path.Combine(protectedDirectory, ".hdrive-protected"), "");
    File.WriteAllText(Path.Combine(cache, "preview.txt"), "preview");
    WorkingCache.Trim(0, cache);
    Require(File.Exists(keep) && !File.Exists(Path.Combine(cache, "preview.txt")), "Cache cleanup removed a protected edit");
    return Task.CompletedTask;
});
await Check("Private sharing does not grant public permission and trash uses reversible metadata", async () => {
    var requests = new List<HttpMethod>();
    var client = Client(Account(StorageProtocol.GoogleDrive), async (request, _) => {
        requests.Add(request.Method);
        if (request.Method == HttpMethod.Get) return Json("{\"webViewLink\":\"https://drive.google.com/file/d/id/view\"}");
        Require(request.Method == HttpMethod.Patch && (await request.Content!.ReadAsStringAsync()).Contains("\"trashed\":true"), "Trash used permanent deletion");
        return Json("{}");
    });
    await client.ReadOnlyLinkAsync("id");
    Require(requests.SequenceEqual(new[] { HttpMethod.Get }), "Reading an access link granted public permission");
    await client.MoveToTrashAsync("id", false);
});
await Check("Version pagination rejects credential forwarding to foreign providers", async () => {
    var calls = 0;
    var client = Client(Account(StorageProtocol.OneDrive), (_, _) => { calls++; return Task.FromResult(Json("{\"value\":[],\"@odata.nextLink\":\"https://www.googleapis.com/steal\"}")); });
    await MustFail(async () => { await client.VersionsAsync("id"); });
    Require(calls == 1, "Version pagination forwarded credentials to another provider");
});

await Check("Folder sync detects both-side changes and does not silently propagate deletions", () => {
    var baseline = new SyncBaseline("local", "remote");
    Require(FolderSynchronizer.Decide("local", "remote", baseline) == SyncAction.None, "Unchanged pair was transferred");
    Require(FolderSynchronizer.Decide("changed", "remote", baseline) == SyncAction.Upload, "Local edit not uploaded");
    Require(FolderSynchronizer.Decide("local", "changed", baseline) == SyncAction.Download, "Remote edit not downloaded");
    Require(FolderSynchronizer.Decide("changed", "changed", baseline) == SyncAction.Conflict, "Two-side edit was overwritten");
    Require(FolderSynchronizer.Decide(null, "remote", baseline) == SyncAction.Conflict, "Deletion propagated silently");
    return Task.CompletedTask;
});
await Check("Two-way sync transfers additions, preserves both conflict copies and persists its baseline", async () => {
    var directory = Profile(); File.WriteAllText(Path.Combine(directory, "local.txt"), "local-data");
    var remote = new Dictionary<string, (string Id, string Data)> { ["remote.txt"] = ("remote-id", "remote-data"), ["same.txt"] = ("same-id", "cloud-version") };
    File.WriteAllText(Path.Combine(directory, "same.txt"), "local-version");
    var client = Client(Account(StorageProtocol.GoogleDrive), async (request, _) => {
        if (request.Method == HttpMethod.Post) {
            var parts = ((MultipartContent)request.Content!).ToList();
            using var metadata = JsonDocument.Parse(await parts[0].ReadAsStringAsync());
            var name = metadata.RootElement.GetProperty("name").GetString()!;
            remote[name] = (S3RequestSigner.Hash(name)[..12], await parts[1].ReadAsStringAsync()); return Json("{}");
        }
        var uri = request.RequestUri!;
        if (uri.AbsolutePath.EndsWith("/files")) return Json(JsonSerializer.Serialize(new { files = remote.Select(entry => new { id = entry.Value.Id, name = entry.Key, mimeType = "text/plain", size = entry.Value.Data.Length.ToString(), modifiedTime = "2026-01-01T00:00:00Z" }) }));
        var file = remote.Single(entry => uri.AbsolutePath.EndsWith("/" + entry.Value.Id));
        if (uri.Query.Contains("fields=")) return Json(JsonSerializer.Serialize(new { mimeType = "text/plain", name = file.Key }));
        return Json(file.Value.Data);
    });
    var engine = new FolderSynchronizer(client, directory, "");
    var rows = await engine.PreviewAsync();
    Require(rows.Count(row => row.Action == SyncAction.Upload) == 1 && rows.Count(row => row.Action == SyncAction.Download) == 1, "Additions were not classified in both directions");
    Require((await engine.ApplyAsync(rows, SyncConflictPolicy.KeepBoth)).Count == 0, "Sync failed");
    Require(File.ReadAllText(Path.Combine(directory, "same.txt")) == "cloud-version" && remote.Any(pair => pair.Key.Contains("yerel") && pair.Value.Data == "local-version"), "Keep-both lost a conflict version");
    Require(File.ReadAllText(Path.Combine(directory, "remote.txt")) == "remote-data" && remote["local.txt"].Data == "local-data", "Sync lost file data");
    Require((await new FolderSynchronizer(client, directory, "").PreviewAsync()).All(row => row.Action == SyncAction.None), "Restart lost the sync baseline");
});
await Check("System WebDAV paths exclude credentials and preserve HTTPS and custom ports", () => {
    var account = Account(); account.ServerURL = "https://username:password@storage.example:8443/dav/folder";
    var target = Client(account, (_, _) => Task.FromResult(Json("{}"))).SystemConnectionTarget();
    Require(target.StartsWith("\\\\storage.example@SSL@8443\\DavWWWRoot") && !target.Contains("password") && !target.Contains("username"), "System connection leaked credentials or lost origin details");
    return Task.CompletedTask;
});

await Check("Revoking public links visits every permissions page and retains private collaborators", async () => {
    var removed = new List<string>();
    var client = Client(Account(StorageProtocol.GoogleDrive), (request, _) => {
        if (request.Method == HttpMethod.Delete) { removed.Add(request.RequestUri!.Segments.Last()); return Task.FromResult(Json("{}")); }
        return Task.FromResult(Json(request.RequestUri!.Query.Contains("pageToken=")
            ? "{\"permissions\":[{\"id\":\"public-two\",\"type\":\"anyone\"}]}"
            : "{\"permissions\":[{\"id\":\"private-user\",\"type\":\"user\"},{\"id\":\"public-one\",\"type\":\"anyone\"}],\"nextPageToken\":\"next\"}"));
    });
    await client.RevokePublicLinksAsync("id");
    Require(removed.Count == 2 && removed.All(id => id.StartsWith("public-")), "Public link revocation skipped a page or removed a private collaborator");
});

if (failures.Count > 0) throw new AggregateException(failures.Select(message => new Exception(message)));
Console.WriteLine("All core regression checks passed.");
Directory.Delete(root, recursive: true);

sealed class FixtureHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) => handler(request, ct);
}
