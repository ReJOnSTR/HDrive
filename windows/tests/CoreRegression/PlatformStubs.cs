// Real production services run against fake OS vault, dispatcher and presentation types.
// HTTP is supplied through HttpClient, so these tests never contact a cloud account.
namespace HDriveWin.Services
{
    public static class CredentialService
    {
        internal static readonly Dictionary<string, string> Values = new();
        internal static bool FailWrites;
        public static string? GetPassword(string key) => Values.GetValueOrDefault(key);
        public static void SavePassword(string key, string value)
        {
            if (FailWrites) throw new IOException("Injected vault failure");
            Values[key] = value;
        }
        public static void DeletePassword(string key) => Values.Remove(key);
    }
}
namespace HDriveWin.Models
{
    public class FileItem
    {
        public string Name { get; set; } = "";
        public string Path { get; set; } = "";
        public bool IsDirectory { get; set; }
        public long Size { get; set; }
        public DateTime ModifiedDate { get; set; }
    }
}
namespace Windows.UI
{
    public struct Color { public static Color FromArgb(byte a, byte r, byte g, byte b) => new(); }
}
namespace Microsoft.UI.Xaml.Media
{
    public class SolidColorBrush { public SolidColorBrush(Windows.UI.Color color) { } }
}
namespace Microsoft.UI.Dispatching
{
    public class DispatcherQueue
    {
        public static DispatcherQueue? GetForCurrentThread() => null;
        public bool HasThreadAccess => true;
        public bool TryEnqueue(Action action) { action(); return true; }
    }
}
