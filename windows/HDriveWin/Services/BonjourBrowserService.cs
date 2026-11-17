using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace HDriveWin.Services;

public sealed class DiscoveredWebDavDevice
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string HostName { get; init; } = "";
    public int Port { get; init; } = 80;
    public string IpAddress { get; init; } = "";

    public string ConnectionUrl => !string.IsNullOrEmpty(IpAddress)
        ? $"http://{IpAddress}:{Port}"
        : $"http://{HostName}:{Port}";

    public string DisplaySubtitle => $"({ConnectionUrl})";
}

/// <summary>
/// Yerel ağdaki _webdav._tcp.local. (mDNS / Bonjour) servislerini keşfeder.
/// macOS BonjourBrowser sınıfının Windows karşılığıdır.
/// </summary>
public sealed class BonjourBrowserService : IDisposable
{
    public static BonjourBrowserService Instance { get; } = new();

    public ObservableCollection<DiscoveredWebDavDevice> DiscoveredDevices { get; } = new();
    public bool IsSearching { get; private set; }
    public event EventHandler? DevicesUpdated;

    private CancellationTokenSource? _cts;

    public void StartSearching(Action<Action>? uiDispatcher = null)
    {
        StopSearching();
        DiscoveredDevices.Clear();
        IsSearching = true;
        DevicesUpdated?.Invoke(this, EventArgs.Empty);

        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        _ = Task.Run(() => SearchLoopAsync(uiDispatcher, token), token);
    }

    public void StopSearching()
    {
        IsSearching = false;
        try { _cts?.Cancel(); } catch { }
        try { _cts?.Dispose(); } catch { }
        _cts = null;
        DevicesUpdated?.Invoke(this, EventArgs.Empty);
    }

    private async Task SearchLoopAsync(Action<Action>? uiDispatcher, CancellationToken ct)
    {
        try
        {
            using var udp = new UdpClient(AddressFamily.InterNetwork);
            udp.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
            udp.Client.Bind(new IPEndPoint(IPAddress.Any, 0));

            var multicastEndpoint = new IPEndPoint(IPAddress.Parse("224.0.0.251"), 5353);
            var queryPacket = BuildMdnsPtrQuery("_webdav._tcp.local");
            await udp.SendAsync(queryPacket, queryPacket.Length, multicastEndpoint);

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(4));

            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            while (!timeoutCts.IsCancellationRequested)
            {
                var receiveTask = udp.ReceiveAsync(timeoutCts.Token).AsTask();
                var result = await receiveTask;
                var device = TryParseMdnsResponse(result.Buffer, result.RemoteEndPoint.Address);
                if (device != null && seen.Add(device.ConnectionUrl))
                {
                    void AddDevice()
                    {
                        DiscoveredDevices.Add(device);
                        DevicesUpdated?.Invoke(this, EventArgs.Empty);
                    }

                    if (uiDispatcher != null) uiDispatcher(AddDevice);
                    else AddDevice();
                }
            }
        }
        catch
        {
            // mDNS UDP multicast may time out or be blocked by firewall; ignore gracefully.
        }
        finally
        {
            void CompleteSearch()
            {
                IsSearching = false;
                DevicesUpdated?.Invoke(this, EventArgs.Empty);
            }

            if (uiDispatcher != null) uiDispatcher(CompleteSearch);
            else CompleteSearch();
        }
    }

    internal static byte[] BuildMdnsPtrQuery(string serviceName)
    {
        var bytes = new List<byte>
        {
            0x00, 0x00, // Transaction ID
            0x00, 0x00, // Flags: standard query
            0x00, 0x01, // Questions: 1
            0x00, 0x00, // Answer RRs
            0x00, 0x00, // Authority RRs
            0x00, 0x00  // Additional RRs
        };

        foreach (var label in serviceName.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            var labelBytes = Encoding.UTF8.GetBytes(label);
            bytes.Add((byte)labelBytes.Length);
            bytes.AddRange(labelBytes);
        }
        bytes.Add(0x00); // Root null label
        bytes.AddRange(new byte[] { 0x00, 0x0C }); // Type PTR (12)
        bytes.AddRange(new byte[] { 0x00, 0x01 }); // Class IN (1)
        return bytes.ToArray();
    }

    internal static DiscoveredWebDavDevice? TryParseMdnsResponse(byte[] buffer, IPAddress senderIp)
    {
        if (buffer == null || buffer.Length < 12) return null;
        int anCount = (buffer[6] << 8) | buffer[7];
        int arCount = (buffer[10] << 8) | buffer[11];
        if (anCount + arCount <= 0) return null;

        var ascii = Encoding.UTF8.GetString(buffer);
        if (!ascii.Contains("_webdav", StringComparison.OrdinalIgnoreCase)) return null;

        int port = 80;
        string instanceName = $"WebDAV ({senderIp})";

        // Look for SRV record (Type 0x00 0x21, Class 0x00 0x01 or 0x80 0x01) to extract port
        for (int i = 12; i + 16 < buffer.Length; i++)
        {
            if (buffer[i] == 0x00 && buffer[i + 1] == 0x21 &&
                (buffer[i + 2] == 0x00 || buffer[i + 2] == 0x80) && buffer[i + 3] == 0x01)
            {
                int rdLength = (buffer[i + 8] << 8) | buffer[i + 9];
                if (rdLength >= 6 && i + 10 + 6 <= buffer.Length)
                {
                    int candidatePort = (buffer[i + 14] << 8) | buffer[i + 15];
                    if (candidatePort is > 0 and <= 65535)
                    {
                        port = candidatePort;
                        break;
                    }
                }
            }
        }

        return new DiscoveredWebDavDevice
        {
            Id = $"{senderIp}:{port}",
            Name = instanceName,
            HostName = senderIp.ToString(),
            IpAddress = senderIp.ToString(),
            Port = port
        };
    }

    public void Dispose() => StopSearching();
}

