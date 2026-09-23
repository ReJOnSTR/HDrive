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
        StorageProtocol protocol, 
        string? customClientId = null, 
        string? customClientSecret = null)
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromMinutes(2.5));
        HttpListener? listener = null;

        try
        {
            listener = new HttpListener();
            
            // Google ve OneDrive redirect URI uyumu
            var redirectUri = (protocol == StorageProtocol.GoogleDrive) 
                ? "http://127.0.0.1:8080/oauth/callback" 
                : "http://localhost:8080/";

            if (protocol == StorageProtocol.GoogleDrive)
            {
                listener.Prefixes.Add("http://127.0.0.1:8080/");
            }
            else
            {
                listener.Prefixes.Add("http://localhost:8080/");
            }

            listener.Start();

            string authUrl;
            string effectiveClientId;
            string effectiveClientSecret = "";

            if (protocol == StorageProtocol.GoogleDrive)
            {
                effectiveClientId = !string.IsNullOrWhiteSpace(customClientId) ? customClientId.Trim() : GetDefaultGoogleClientId();
                effectiveClientSecret = !string.IsNullOrWhiteSpace(customClientSecret) ? customClientSecret.Trim() : GetDefaultGoogleClientSecret();

                if (string.IsNullOrEmpty(effectiveClientId))
                {
                    listener.Stop();
                    return (false, "", "", "Google OAuth Client ID bulunamadı. Lütfen Ayarlar formundaki Client ID alanına kimliğinizi girin.");
                }

                var encClientId = Uri.EscapeDataString(effectiveClientId);
                authUrl = $"https://accounts.google.com/o/oauth2/v2/auth?client_id={encClientId}&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Foauth%2Fcallback&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive&access_type=offline&prompt=consent";
            }
            else if (protocol == StorageProtocol.OneDrive)
            {
                effectiveClientId = !string.IsNullOrWhiteSpace(customClientId) ? customClientId.Trim() : DefaultOneDriveClientId;
                var encClientId = Uri.EscapeDataString(effectiveClientId);
                authUrl = $"https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id={encClientId}&response_type=code&redirect_uri=http%3A%2F%2Flocalhost%3A8080&scope=offline_access%20Files.ReadWrite%20User.Read";
            }
            else
            {
                listener.Stop();
                return (false, "", "", "Bu protokol için tarayıcı OAuth girişi desteklenmiyor.");
            }

            // Varsayılan tarayıcıda yetkilendirme sayfasını aç
            Process.Start(new ProcessStartInfo(authUrl) { UseShellExecute = true });

            // Tarayıcıdan gelecek yönlendirmeyi dinle
            var contextTask = listener.GetContextAsync();
            var completedTask = await Task.WhenAny(contextTask, Task.Delay(-1, cts.Token));

            if (completedTask != contextTask)
            {
                listener.Stop();
                return (false, "", "", "Oturum açma süresi doldu veya iptal edildi.");
            }

            var context = await contextTask;
            var request = context.Request;
            var query = request.QueryString;
            var code = query["code"];

            // Tarayıcıya kullanıcı dostu başarılı HTML yanıtı döndür
            const string responseHtml = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>HDrive</title></head><body style=\"font-family:system-ui,-apple-system;text-align:center;padding:60px 20px;background:#f8fafc;\"><div style=\"max-width:440px;margin:auto;background:white;padding:40px;border-radius:16px;box-shadow:0 10px 25px rgba(0,0,0,0.06);\"><h2 style=\"color:#10b981;margin-bottom:8px;\">✅ Giriş Başarılı!</h2><p style=\"color:#64748b;font-size:15px;line-height:1.5;\">HDrive bulut oturumunuzu başarıyla doğruladı.<br>Bu sekmeyi kapatıp uygulamaya dönebilirsiniz.</p></div></body></html>";
            var buffer = Encoding.UTF8.GetBytes(responseHtml);
            context.Response.ContentLength64 = buffer.Length;
            context.Response.ContentType = "text/html; charset=utf-8";
            await context.Response.OutputStream.WriteAsync(buffer, 0, buffer.Length);
            context.Response.OutputStream.Close();
            listener.Stop();

            if (string.IsNullOrEmpty(code))
            {
                var errorDesc = query["error_description"] ?? query["error"] ?? "Yetkilendirme kodu alınamadı.";
                return (false, "", "", errorDesc);
            }

            // Kodu erişim tokenı ile takas et
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };

            if (protocol == StorageProtocol.GoogleDrive)
            {
                var tokenReq = new HttpRequestMessage(HttpMethod.Post, "https://oauth2.googleapis.com/token");
                var bodyContent = $"code={Uri.EscapeDataString(code)}&client_id={Uri.EscapeDataString(effectiveClientId)}&client_secret={Uri.EscapeDataString(effectiveClientSecret)}&redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Foauth%2Fcallback&grant_type=authorization_code";
                tokenReq.Content = new StringContent(bodyContent, Encoding.UTF8, "application/x-www-form-urlencoded");

                var resp = await httpClient.SendAsync(tokenReq);
                var respJson = await resp.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(respJson);

                var accessToken = doc.RootElement.TryGetProperty("access_token", out var tokenProp) ? tokenProp.GetString() ?? "" : "";
                var refreshToken = doc.RootElement.TryGetProperty("refresh_token", out var rtProp) ? rtProp.GetString() ?? "" : "";

                if (!string.IsNullOrEmpty(accessToken))
                {
                    return (true, accessToken, refreshToken, "Google Drive oturumu başarıyla açıldı!");
                }

                var errMsg = doc.RootElement.TryGetProperty("error_description", out var ed) ? ed.GetString() : "Token alınamadı.";
                return (false, "", "", $"Google yetkilendirme hatası: {errMsg}");
            }
            else // OneDrive
            {
                var tokenReq = new HttpRequestMessage(HttpMethod.Post, "https://login.microsoftonline.com/common/oauth2/v2.0/token");
                var bodyContent = $"client_id={Uri.EscapeDataString(effectiveClientId)}&grant_type=authorization_code&code={Uri.EscapeDataString(code)}&redirect_uri=http%3A%2F%2Flocalhost%3A8080";
                tokenReq.Content = new StringContent(bodyContent, Encoding.UTF8, "application/x-www-form-urlencoded");

                var resp = await httpClient.SendAsync(tokenReq);
                var respJson = await resp.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(respJson);

                var accessToken = doc.RootElement.TryGetProperty("access_token", out var tokenProp) ? tokenProp.GetString() ?? "" : "";
                var refreshToken = doc.RootElement.TryGetProperty("refresh_token", out var rtProp) ? rtProp.GetString() ?? "" : "";

                if (!string.IsNullOrEmpty(accessToken))
                {
                    return (true, accessToken, refreshToken, "Microsoft OneDrive oturumu başarıyla açıldı!");
                }

                var errMsg = doc.RootElement.TryGetProperty("error_description", out var ed) ? ed.GetString() : "OneDrive tokenı alınamadı.";
                return (false, "", "", $"Microsoft yetkilendirme hatası: {errMsg}");
            }
        }
        catch (Exception ex)
        {
            try { listener?.Stop(); } catch { }
            return (false, "", "", $"Tarayıcı ile oturum açma hatası: {ex.Message}");
        }
    }

    public static async Task<(bool Success, string NewAccessToken, string Message)> RefreshOAuthTokenAsync(
        StorageProtocol protocol,
        string refreshToken,
        string? customClientId = null,
        string? customClientSecret = null)
    {
        if (string.IsNullOrEmpty(refreshToken))
        {
            return (false, "", "Yenileme tokenı (refresh_token) bulunamadı.");
        }

        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(25) };

            if (protocol == StorageProtocol.GoogleDrive)
            {
                var effectiveClientId = !string.IsNullOrWhiteSpace(customClientId) ? customClientId.Trim() : GetDefaultGoogleClientId();
                var effectiveClientSecret = !string.IsNullOrWhiteSpace(customClientSecret) ? customClientSecret.Trim() : GetDefaultGoogleClientSecret();

                var tokenReq = new HttpRequestMessage(HttpMethod.Post, "https://oauth2.googleapis.com/token");
                var bodyContent = $"client_id={Uri.EscapeDataString(effectiveClientId)}&client_secret={Uri.EscapeDataString(effectiveClientSecret)}&refresh_token={Uri.EscapeDataString(refreshToken)}&grant_type=refresh_token";
                tokenReq.Content = new StringContent(bodyContent, Encoding.UTF8, "application/x-www-form-urlencoded");

                var resp = await httpClient.SendAsync(tokenReq);
                var respJson = await resp.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(respJson);

                if (doc.RootElement.TryGetProperty("access_token", out var tokenProp))
                {
                    return (true, tokenProp.GetString() ?? "", "Token yenilendi.");
                }

                return (false, "", "Google token yenileme başarısız.");
            }
            else if (protocol == StorageProtocol.OneDrive)
            {
                var effectiveClientId = !string.IsNullOrWhiteSpace(customClientId) ? customClientId.Trim() : DefaultOneDriveClientId;

                var tokenReq = new HttpRequestMessage(HttpMethod.Post, "https://login.microsoftonline.com/common/oauth2/v2.0/token");
                var bodyContent = $"client_id={Uri.EscapeDataString(effectiveClientId)}&grant_type=refresh_token&refresh_token={Uri.EscapeDataString(refreshToken)}&redirect_uri=http%3A%2F%2Flocalhost%3A8080";
                tokenReq.Content = new StringContent(bodyContent, Encoding.UTF8, "application/x-www-form-urlencoded");

                var resp = await httpClient.SendAsync(tokenReq);
                var respJson = await resp.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(respJson);

                if (doc.RootElement.TryGetProperty("access_token", out var tokenProp))
                {
                    return (true, tokenProp.GetString() ?? "", "Token yenilendi.");
                }

                return (false, "", "OneDrive token yenileme başarısız.");
            }

            return (false, "", "Desteklenmeyen protokol.");
        }
        catch (Exception ex)
        {
            return (false, "", $"Token yenileme hatası: {ex.Message}");
        }
    }
}
