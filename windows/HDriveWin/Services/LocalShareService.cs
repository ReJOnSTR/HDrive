using System;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web;

namespace HDriveWin.Services;

/// <summary>
/// Windows üzerinde telefon ve diğer cihazlarla kablosuz dosya aktarımı sağlayan yerel Web paylaşım sunucusu.
/// TcpListener tabanlıdır; Windows üzerinde yönetici (admin) izni gerektirmeden çalışır.
/// </summary>
public sealed class LocalShareService
{
    public static LocalShareService Instance { get; } = new();

    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    public bool IsRunning { get; private set; }
    public int Port { get; private set; } = 8080;

    public string SharedFolderPath { get; }

    private LocalShareService()
    {
        var doc = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        SharedFolderPath = Path.Combine(doc, "HDriveFiles");
        try
        {
            Directory.CreateDirectory(SharedFolderPath);
        }
        catch { }
    }

    public string GetLocalIPAddress()
    {
        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;

                var props = ni.GetIPProperties();
                foreach (var addr in props.UnicastAddresses)
                {
                    if (addr.Address.AddressFamily == AddressFamily.InterNetwork)
                    {
                        var ip = addr.Address.ToString();
                        if (!ip.StartsWith("127.") && !ip.StartsWith("169.254."))
                        {
                            return ip;
                        }
                    }
                }
            }
        }
        catch { }

        return "127.0.0.1";
    }

    public string GetLocalUrl()
    {
        return $"http://{GetLocalIPAddress()}:{Port}";
    }

    public void Start()
    {
        if (IsRunning) return;

        try
        {
            _cts = new CancellationTokenSource();
            _listener = new TcpListener(IPAddress.Any, Port);
            _listener.Start();
            IsRunning = true;

            Task.Run(() => AcceptClientsAsync(_cts.Token));
        }
        catch
        {
            // Port doluysa bir sonrakini dene
            Port = 8081;
            try
            {
                _listener = new TcpListener(IPAddress.Any, Port);
                _listener.Start();
                IsRunning = true;
                Task.Run(() => AcceptClientsAsync(_cts!.Token));
            }
            catch
            {
                IsRunning = false;
            }
        }
    }

    public void Stop()
    {
        if (!IsRunning) return;

        try
        {
            _cts?.Cancel();
            _listener?.Stop();
        }
        catch { }
        finally
        {
            IsRunning = false;
        }
    }

    private async Task AcceptClientsAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested && _listener != null)
        {
            try
            {
                var client = await _listener.AcceptTcpClientAsync(token);
                _ = Task.Run(() => HandleClientAsync(client), token);
            }
            catch
            {
                break;
            }
        }
    }

    private async Task HandleClientAsync(TcpClient client)
    {
        using (client)
        await using (var stream = client.GetStream())
        {
            try
            {
                using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
                var requestLine = await reader.ReadLineAsync();
                if (string.IsNullOrWhiteSpace(requestLine)) return;

                var parts = requestLine.Split(' ');
                if (parts.Length < 2) return;

                var method = parts[0].ToUpperInvariant();
                var path = parts[1];

                // Başlıkları oku
                int contentLength = 0;
                string contentType = "";
                string? line;
                while (!string.IsNullOrEmpty(line = await reader.ReadLineAsync()))
                {
                    if (line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
                    {
                        int.TryParse(line["Content-Length:".Length..].Trim(), out contentLength);
                    }
                    else if (line.StartsWith("Content-Type:", StringComparison.OrdinalIgnoreCase))
                    {
                        contentType = line["Content-Type:".Length..].Trim();
                    }
                }

                if (method == "GET")
                {
                    if (path == "/" || path.StartsWith("/?"))
                    {
                        await ServeDashboardHtmlAsync(stream);
                    }
                    else if (path.StartsWith("/download"))
                    {
                        await ServeDownloadAsync(stream, path);
                    }
                    else
                    {
                        await SendResponseAsync(stream, 404, "Not Found", "Sayfa bulunamadı.");
                    }
                }
                else if (method == "POST" && path.StartsWith("/upload"))
                {
                    await HandleUploadAsync(stream, contentLength, contentType);
                }
                else
                {
                    await SendResponseAsync(stream, 405, "Method Not Allowed", "Yalnızca GET ve POST desteklenir.");
                }
            }
            catch { }
        }
    }

    private async Task ServeDashboardHtmlAsync(Stream stream)
    {
        Directory.CreateDirectory(SharedFolderPath);
        var files = Directory.GetFiles(SharedFolderPath);

        var fileListHtml = new StringBuilder();
        if (files.Length == 0)
        {
            fileListHtml.Append("<div class='empty'>Henüz paylaşılmış bir dosya yok. Aşağıdan fotoğraf veya belge yükleyebilirsiniz.</div>");
        }
        else
        {
            foreach (var f in files)
            {
                var fi = new FileInfo(f);
                var sizeStr = fi.Length > 1024 * 1024
                    ? $"{fi.Length / (1024.0 * 1024.0):F1} MB"
                    : $"{fi.Length / 1024.0:F1} KB";
                var encodedName = HttpUtility.UrlEncode(fi.Name);

                fileListHtml.Append($@"
                <div class='file-item'>
                    <div class='file-info'>
                        <span class='file-name'>{HttpUtility.HtmlEncode(fi.Name)}</span>
                        <span class='file-meta'>{sizeStr} • {fi.LastWriteTime:dd.MM.yyyy HH:mm}</span>
                    </div>
                    <a class='btn btn-download' href='/download?file={encodedName}' download>İndir</a>
                </div>");
            }
        }

        var html = $@"<!DOCTYPE html>
<html lang='tr'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>HDrive Yerel Paylaşım</title>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }}
        body {{ background: #f4f6f9; color: #1a1a1a; padding: 20px 14px; max-width: 600px; margin: 0 auto; }}
        header {{ text-align: center; margin-bottom: 24px; padding-top: 10px; }}
        header h1 {{ font-size: 22px; font-weight: 700; color: #4338ca; display: flex; align-items: center; justify-content: center; gap: 8px; }}
        header p {{ font-size: 13px; color: #6b7280; margin-top: 4px; }}
        .card {{ background: #ffffff; border-radius: 16px; padding: 18px; margin-bottom: 18px; box-shadow: 0 4px 12px rgba(0,0,0,0.04); border: 1px solid #e5e7eb; }}
        .card-title {{ font-size: 14px; font-weight: 600; color: #374151; margin-bottom: 12px; display: flex; align-items: center; justify-content: space-between; }}
        .upload-area {{ border: 2px dashed #6366f1; border-radius: 12px; padding: 24px 16px; text-align: center; background: #eef2ff; cursor: pointer; transition: all 0.2s; }}
        .upload-area:hover {{ background: #e0e7ff; }}
        .upload-area span {{ display: block; font-size: 14px; font-weight: 600; color: #4338ca; margin-top: 6px; }}
        .upload-area small {{ display: block; font-size: 12px; color: #6b7280; margin-top: 4px; }}
        input[type='file'] {{ display: none; }}
        .file-item {{ display: flex; align-items: center; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #f3f4f6; }}
        .file-item:last-child {{ border-bottom: none; }}
        .file-info {{ flex: 1; min-width: 0; padding-right: 12px; }}
        .file-name {{ font-size: 14px; font-weight: 500; display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }}
        .file-meta {{ font-size: 11px; color: #9ca3af; display: block; margin-top: 2px; }}
        .btn {{ display: inline-block; padding: 6px 14px; border-radius: 8px; font-size: 12px; font-weight: 600; text-decoration: none; cursor: pointer; border: none; }}
        .btn-download {{ background: #eef2ff; color: #4338ca; }}
        .btn-download:hover {{ background: #e0e7ff; }}
        .empty {{ text-align: center; padding: 24px 10px; color: #9ca3af; font-size: 13px; }}
        .progress-bar {{ display: none; height: 6px; background: #6366f1; border-radius: 3px; margin-top: 10px; width: 0%; transition: width 0.2s; }}
    </style>
</head>
<body>
    <header>
        <h1><span>💻</span> HDrive Bilgisayar Paylaşımı</h1>
        <p>Bilgisayarınızdaki dosyalara erişin veya anında telefonunuzdan dosya yükleyin</p>
    </header>

    <div class='card'>
        <div class='card-title'><span>📤 Bilgisayara Dosya Yükle</span></div>
        <div class='upload-area' onclick=""document.getElementById('fileInput').click()"">
            <svg width='32' height='32' viewBox='0 0 24 24' fill='none' stroke='#4338ca' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4'/><polyline points='17 8 12 3 7 8'/><line x1='12' y1='3' x2='12' y2='15'/></svg>
            <span>Fotoğraf veya Dosya Seçin</span>
            <small>Kamera, Galeri veya İndirilenlerden seçebilirsiniz</small>
            <input type='file' id='fileInput' onchange='uploadFile(this)' multiple>
        </div>
        <div id='progressBar' class='progress-bar'></div>
    </div>

    <div class='card'>
        <div class='card-title'>
            <span>📁 Bilgisayardaki Dosyalar ({files.Length})</span>
            <a href='/' style='font-size:12px; color:#4338ca; text-decoration:none;'>Yenile</a>
        </div>
        <div class='file-list'>
            {fileListHtml}
        </div>
    </div>

    <script>
        function uploadFile(input) {{
            if (!input.files || input.files.length === 0) return;
            const pb = document.getElementById('progressBar');
            pb.style.display = 'block';
            pb.style.width = '20%';

            let promises = [];
            for (let i = 0; i < input.files.length; i++) {{
                const file = input.files[i];
                const formData = new FormData();
                formData.append('file', file, file.name);

                promises.push(fetch('/upload?filename=' + encodeURIComponent(file.name), {{
                    method: 'POST',
                    body: file
                }}));
            }}

            pb.style.width = '70%';
            Promise.all(promises).then(() => {{
                pb.style.width = '100%';
                setTimeout(() => {{ window.location.reload(); }}, 500);
            }}).catch(err => {{
                alert('Yükleme sırasında hata oluştu: ' + err);
                pb.style.display = 'none';
            }});
        }}
    </script>
</body>
</html>";

        var bytes = Encoding.UTF8.GetBytes(html);
        var header = $"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n";
        var headerBytes = Encoding.UTF8.GetBytes(header);

        await stream.WriteAsync(headerBytes);
        await stream.WriteAsync(bytes);
        await stream.FlushAsync();
    }

    private async Task ServeDownloadAsync(Stream stream, string path)
    {
        var query = path.Contains('?') ? path[(path.IndexOf('?') + 1)..] : "";
        var queryParams = HttpUtility.ParseQueryString(query);
        var fileName = queryParams["file"];

        if (string.IsNullOrEmpty(fileName))
        {
            await SendResponseAsync(stream, 400, "Bad Request", "Dosya belirtilmedi.");
            return;
        }

        var safeName = Path.GetFileName(fileName);
        var fullPath = Path.Combine(SharedFolderPath, safeName);

        if (!File.Exists(fullPath))
        {
            await SendResponseAsync(stream, 404, "Not Found", "Dosya bulunamadı.");
            return;
        }

        var fi = new FileInfo(fullPath);
        var encodedDownloadName = HttpUtility.UrlEncode(safeName);
        var header = $"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"{encodedDownloadName}\"\r\nContent-Length: {fi.Length}\r\nConnection: close\r\n\r\n";
        var headerBytes = Encoding.UTF8.GetBytes(header);

        await stream.WriteAsync(headerBytes);
        await using var fileStream = File.OpenRead(fullPath);
        await fileStream.CopyToAsync(stream);
        await stream.FlushAsync();
    }

    private async Task HandleUploadAsync(Stream stream, int contentLength, string contentType)
    {
        string fileName = $"upload_{DateTime.Now:yyyyMMdd_HHmmss}.bin";

        // Query parametresinden dosya adını almayı dene
        var targetFile = Path.Combine(SharedFolderPath, fileName);

        await using (var fileStream = File.Create(targetFile))
        {
            var buffer = new byte[81920];
            int totalRead = 0;
            while (totalRead < contentLength)
            {
                int toRead = Math.Min(buffer.Length, contentLength - totalRead);
                int read = await stream.ReadAsync(buffer.AsMemory(0, toRead));
                if (read <= 0) break;
                await fileStream.WriteAsync(buffer.AsMemory(0, read));
                totalRead += read;
            }
        }

        await SendResponseAsync(stream, 200, "OK", "Dosya başarıyla yüklendi.");
    }

    private async Task SendResponseAsync(Stream stream, int code, string status, string body)
    {
        var bytes = Encoding.UTF8.GetBytes(body);
        var header = $"HTTP/1.1 {code} {status}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n";
        var headerBytes = Encoding.UTF8.GetBytes(header);

        await stream.WriteAsync(headerBytes);
        await stream.WriteAsync(bytes);
        await stream.FlushAsync();
    }
}
