using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using HDriveWin.Models;

namespace HDriveWin.Services;

public class OAuthHelper
{
    internal static Func<HttpClient> HttpClientFactory { get; set; } = () => new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
    public const string DefaultOneDriveClientId = "232843cb-b028-4bbf-97d4-039b8a611dbd";

    public static string GetDefaultGoogleClientId()
    {
        try
        {
            var env = Environment.GetEnvironmentVariable("GOOGLE_OAUTH_CLIENT_ID");
            if (!string.IsNullOrWhiteSpace(env)) return env.Trim();

            var candidates = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config", "HDrive", "google_credentials.json"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "HDrive", "google_credentials.json"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive", "google_credentials.json"),
                Path.Combine(AppContext.BaseDirectory, "google_credentials.json"),
                Path.Combine(AppContext.BaseDirectory, "Config", "google_credentials.json")
            };

            foreach (var path in candidates)
            {
                if (File.Exists(path))
                {
                    var content = File.ReadAllText(path);
                    using var doc = JsonDocument.Parse(content);
                    if (doc.RootElement.TryGetProperty("client_id", out var cid))
                    {
                        var val = cid.GetString();
                        if (!string.IsNullOrEmpty(val)) return val.Trim();
                    }
                }
            }
        }
        catch { }
        return "";
    }

    public static string GetDefaultGoogleClientSecret()
    {
        try
        {
            var env = Environment.GetEnvironmentVariable("GOOGLE_OAUTH_CLIENT_SECRET");
            if (!string.IsNullOrWhiteSpace(env)) return env.Trim();

            var candidates = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config", "HDrive", "google_credentials.json"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "HDrive", "google_credentials.json"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HDrive", "google_credentials.json"),
                Path.Combine(AppContext.BaseDirectory, "google_credentials.json"),
                Path.Combine(AppContext.BaseDirectory, "Config", "google_credentials.json")
            };

            foreach (var path in candidates)
            {
                if (File.Exists(path))
                {
                    var content = File.ReadAllText(path);
                    using var doc = JsonDocument.Parse(content);
                    if (doc.RootElement.TryGetProperty("client_secret", out var cs))
                    {
                        var val = cs.GetString();
                        if (!string.IsNullOrEmpty(val)) return val.Trim();
                    }
                }
            }
        }
        catch { }
        return "";
    }

    public static async Task<(bool Success, string Token, string RefreshToken, string Message)> StartOAuthLoginAsync(
        StorageProtocol protocol, string? customClientId = null, string? customClientSecret = null)
    {
        if (protocol is not (StorageProtocol.GoogleDrive or StorageProtocol.OneDrive))
            return (false, "", "", "Bu hesap OAuth kullanmıyor.");
        var google = protocol == StorageProtocol.GoogleDrive;
        var clientId = !string.IsNullOrWhiteSpace(customClientId) ? customClientId.Trim()
            : google ? GetDefaultGoogleClientId() : DefaultOneDriveClientId;
        if (string.IsNullOrEmpty(clientId)) return (false, "", "", "OAuth Client ID bulunamadı.");
        var secret = customClientSecret ?? (google ? GetDefaultGoogleClientSecret() : "");
        var redirect = google ? "http://127.0.0.1:8080/oauth/callback" : "http://localhost:8080";
        var session = new OAuthLoginSession();
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMinutes(2.5));
        using var listener = new HttpListener();
        try
        {
            listener.Prefixes.Add(google ? "http://127.0.0.1:8080/" : "http://localhost:8080/");
            listener.Start();
            var parameters = new System.Collections.Generic.Dictionary<string, string> {
                ["client_id"] = clientId, ["response_type"] = "code", ["redirect_uri"] = redirect,
                ["scope"] = google ? "https://www.googleapis.com/auth/drive" : "offline_access Files.ReadWrite User.Read",
                ["state"] = session.State, ["code_challenge"] = session.Challenge, ["code_challenge_method"] = "S256"
            };
            if (google) { parameters["access_type"] = "offline"; parameters["prompt"] = "consent"; }
            using var query = new FormUrlEncodedContent(parameters);
            var endpoint = google ? "https://accounts.google.com/o/oauth2/v2/auth" : "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
            var url = endpoint + "?" + await query.ReadAsStringAsync();
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            while (true)
            {
                var context = await listener.GetContextAsync().WaitAsync(cancellation.Token);
                var expectedPath = google ? "/oauth/callback" : "/";
                if (context.Request.HttpMethod != "GET" || context.Request.Url?.AbsolutePath != expectedPath ||
                    !session.Matches(context.Request.QueryString["state"]))
                {
                    context.Response.StatusCode = 400;
                    context.Response.Close();
                    continue; // A favicon or a forged callback cannot terminate the real login.
                }
                var code = context.Request.QueryString["code"];
                if (string.IsNullOrEmpty(code))
                {
                    context.Response.StatusCode = 400;
                    context.Response.Close();
                    return (false, "", "", context.Request.QueryString["error_description"] ?? "Yetkilendirme iptal edildi.");
                }
                var tokenValues = new System.Collections.Generic.Dictionary<string, string> {
                    ["client_id"] = clientId, ["code"] = code, ["grant_type"] = "authorization_code",
                    ["redirect_uri"] = redirect, ["code_verifier"] = session.Verifier
                };
                if (google && !string.IsNullOrEmpty(secret)) tokenValues["client_secret"] = secret;
                var result = await RequestTokensAsync(google, tokenValues, cancellation.Token);
                var html = "<!doctype html><html lang=tr><meta charset=utf-8><title>HDrive</title><body><h2>" +
                    (result.Success ? "Oturum açıldı. Uygulamaya dönebilirsiniz." : "Oturum açılamadı. Uygulamadaki hata mesajını kontrol edin.") + "</h2></body></html>";
                var bytes = Encoding.UTF8.GetBytes(html);
                context.Response.ContentType = "text/html; charset=utf-8";
                context.Response.ContentLength64 = bytes.Length;
                await context.Response.OutputStream.WriteAsync(bytes, cancellation.Token);
                context.Response.Close();
                return result;
            }
        }
        catch (OperationCanceledException) { return (false, "", "", "Oturum açma süresi doldu."); }
        catch (Exception error) { return (false, "", "", "Oturum açılamadı: " + error.Message); }
        finally { listener.Stop(); }
    }

    private static async Task<(bool Success, string Token, string RefreshToken, string Message)> RequestTokensAsync(
        bool google, System.Collections.Generic.Dictionary<string, string> values, CancellationToken ct)
    {
        using var client = HttpClientFactory();
        using var body = new FormUrlEncodedContent(values);
        var endpoint = google ? "https://oauth2.googleapis.com/token" : "https://login.microsoftonline.com/common/oauth2/v2.0/token";
        using var response = await client.PostAsync(endpoint, body, ct);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
        if (response.IsSuccessStatusCode && json.RootElement.TryGetProperty("access_token", out var token))
            return (true, token.GetString() ?? "", json.RootElement.TryGetProperty("refresh_token", out var refresh) ? refresh.GetString() ?? "" : "", "Oturum doğrulandı.");
        return (false, "", "", json.RootElement.TryGetProperty("error_description", out var error) ? error.GetString() ?? "Yetkilendirme başarısız." : "Yetkilendirme başarısız.");
    }

    public static async Task<(bool Success, string NewAccessToken, string NewRefreshToken, string Message)> RefreshOAuthTokenAsync(
        StorageProtocol protocol, string refreshToken, string? customClientId = null, string? customClientSecret = null)
    {
        if (string.IsNullOrEmpty(refreshToken)) return (false, "", "", "Yenileme token'ı bulunamadı.");
        if (protocol is not (StorageProtocol.GoogleDrive or StorageProtocol.OneDrive)) return (false, "", "", "Bu hesap OAuth kullanmıyor.");
        var google = protocol == StorageProtocol.GoogleDrive;
        var values = new System.Collections.Generic.Dictionary<string, string> {
            ["grant_type"] = "refresh_token", ["refresh_token"] = refreshToken,
            ["client_id"] = !string.IsNullOrWhiteSpace(customClientId) ? customClientId.Trim() : google ? GetDefaultGoogleClientId() : DefaultOneDriveClientId
        };
        var secret = customClientSecret ?? (google ? GetDefaultGoogleClientSecret() : "");
        if (google && !string.IsNullOrEmpty(secret)) values["client_secret"] = secret;
        try { return await RequestTokensAsync(google, values, CancellationToken.None); }
        catch (Exception error) { return (false, "", "", "Token yenilenemedi: " + error.Message); }
    }
}
