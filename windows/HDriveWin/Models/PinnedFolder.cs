using System;

namespace HDriveWin.Models;

public class PinnedFolder
{
    public string Name { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;

    public PinnedFolder() { }

    public PinnedFolder(string name, string path)
    {
        Name = name;
        Path = path;
    }
}
