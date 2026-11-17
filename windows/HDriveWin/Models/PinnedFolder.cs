using System;

namespace HDriveWin.Models;

public class PinnedFolder
{
    public string Name { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public bool IsDirectory { get; set; } = true;

    public PinnedFolder() { }

    public PinnedFolder(string name, string path, bool isDirectory = true)
    {
        Name = name;
        Path = path;
        IsDirectory = isDirectory;
    }
}
