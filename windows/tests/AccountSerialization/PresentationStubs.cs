// Only the presentation dependencies are stubbed. The production ServerConfig
// and System.Text.Json serializer are used directly, without WinUI on this host.
namespace HDriveWin.Services
{
    public class CloudreveManager
    {
        public static CloudreveManager Instance => throw new InvalidOperationException(
            "Account serialization re-entered CloudreveManager during initialization.");

        public HDriveWin.Models.ServerConfig? ActiveServer => null;
    }
}

namespace Windows.UI
{
    public struct Color
    {
        public static Color FromArgb(byte a, byte r, byte g, byte b) => new();
    }
}

namespace Microsoft.UI.Xaml.Media
{
    public class SolidColorBrush
    {
        public SolidColorBrush(Windows.UI.Color color) => throw new InvalidOperationException(
            "Account serialization constructed a WinUI presentation object.");
    }
}
