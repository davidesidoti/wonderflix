using Jellyfin.Plugin.WonderFlixWatchParty.Server;
using Jellyfin.Plugin.WonderFlixWatchParty.Space;
using Xunit;

namespace Jellyfin.Plugin.WonderFlixWatchParty.Tests;

public sealed class LinuxFileProbeTests : IDisposable
{
    private readonly TempFolder temp = new();
    private readonly LinuxFileProbe probe = new();

    public void Dispose() => temp.Dispose();

    private string Make(string relative, long length = 10)
    {
        var path = Path.Combine(temp.Path, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using var stream = File.Create(path);
        stream.SetLength(length);
        return path;
    }

    private string Root(string name) => Path.Combine(temp.Path, name);

    [Fact]
    public void StatOutputIsParsed()
    {
        var stamps = FileProbe.ParseStat("16673\t31119496\t2\t6374799956\t/home/x/Coco (2017).mkv\nrotta\n");

        var (path, stamp) = Assert.Single(stamps);
        Assert.Equal("/home/x/Coco (2017).mkv", path);
        Assert.Equal(new FileId(16673, 31119496), stamp.Id);
        Assert.Equal(2, stamp.Links);
        Assert.Equal(6374799956, stamp.SizeBytes);
    }

    [Fact]
    public void DeleteRefusesOutsideTheRoots()
    {
        var root = Root("downloads");
        var outside = Make(Path.Combine("altro", "film.mkv"));
        var inside = Make(Path.Combine("downloads", "film.mkv"));
        var dotDot = Path.Combine(root, "..", "altro", "film.mkv");

        Assert.False(probe.Delete(outside, [root]));
        Assert.False(probe.Delete(dotDot, [root]));
        Assert.True(File.Exists(outside));
        Assert.True(probe.Delete(inside, [root]));
        Assert.False(File.Exists(inside));
    }

    [Fact]
    public void DeleteRemovesEmptyFolders()
    {
        var root = Root("downloads");
        var film = Make(Path.Combine("downloads", "a", "b", "film.mkv"));

        Assert.True(probe.Delete(film, [root]));

        Assert.False(Directory.Exists(Path.Combine(root, "a")));
        Assert.True(Directory.Exists(root));
    }

    [Fact]
    public void DeleteKeepsFoldersThatAreNotEmpty()
    {
        var root = Root("downloads");
        var film = Make(Path.Combine("downloads", "a", "b", "film.mkv"));
        var other = Make(Path.Combine("downloads", "a", "altro.mkv"));

        Assert.True(probe.Delete(film, [root]));

        Assert.False(Directory.Exists(Path.Combine(root, "a", "b")));
        Assert.True(File.Exists(other));
    }

    [Fact]
    public void DeleteStaysTrueWhenPruningAFolderFails()
    {
        var root = Root("downloads");
        var film = Make(Path.Combine("downloads", "a", "film.mkv"));
        var folder = new DirectoryInfo(Path.Combine(root, "a"));

        // La potatura deve fallire dopo che il file è andato. Su Windows una cartella di sola
        // lettura non si cancella; su Linux serve togliere la scrittura alla cartella sopra.
        var windows = OperatingSystem.IsWindows();
        var rootMode = windows ? default : File.GetUnixFileMode(root);
        if (windows)
        {
            folder.Attributes |= FileAttributes.ReadOnly;
        }
        else
        {
            File.SetUnixFileMode(root, rootMode & ~(UnixFileMode.UserWrite | UnixFileMode.GroupWrite | UnixFileMode.OtherWrite));
        }

        try
        {
            Assert.True(probe.Delete(film, [root]));
            Assert.False(File.Exists(film));
        }
        finally
        {
            if (windows)
            {
                folder.Refresh();
                folder.Attributes &= ~FileAttributes.ReadOnly;
            }
            else
            {
                File.SetUnixFileMode(root, rootMode);
            }
        }
    }

    [Fact]
    public void TheFakeRecordsEveryDeleteCall()
    {
        var fake = new FakeFileProbe();
        fake.Files["/x/film.mkv"] = new FileStamp(new FileId(1, 2), 1, 10);

        Assert.True(fake.Delete("/altrove/film.mkv", ["/srv"]));
        fake.DeleteResult = false;
        Assert.False(fake.Delete("/x/film.mkv", ["/x"]));

        Assert.Equal(["/altrove/film.mkv", "/x/film.mkv"], fake.DeleteCalls.Select(c => c.Path));
        Assert.Equal(["/altrove/film.mkv"], fake.Deleted);
        Assert.True(fake.Files.ContainsKey("/x/film.mkv"));
    }

    [Fact]
    public void VideoFilesSkipsSmallAndOtherExtensions()
    {
        var big = Make(Path.Combine("lib", "x", "Film.mkv"), 150_000_000);
        Make(Path.Combine("lib", "piccolo.mkv"), 1024);
        Make(Path.Combine("lib", "film.nfo"), 150_000_000);

        var found = probe.VideoFiles(Root("lib"));

        Assert.Equal([big], found);
        Assert.Empty(probe.VideoFiles(Root("manca")));
    }

    [Fact]
    public void ReadTextReturnsNullWhenMissing()
    {
        var file = Make("quota.txt", 0);
        File.WriteAllText(file, "ciao");

        Assert.Equal("ciao", probe.ReadText(file));
        Assert.Null(probe.ReadText(Root("manca.txt")));
    }

    [Fact]
    public void LastWriteTimeIsNullWhenMissing()
    {
        var file = Make("quota.txt");
        File.SetLastWriteTimeUtc(file, new DateTime(2026, 10, 30, 12, 0, 0, DateTimeKind.Utc));

        Assert.Equal(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero), probe.LastWriteTime(file));
        Assert.Null(probe.LastWriteTime(Root("manca.txt")));
    }

    [Fact]
    public void IsUnderRejectsDotDot()
    {
        var root = Root("downloads");

        Assert.False(FileProbe.IsUnder(root + "/../altro/film.mkv", [root]));
        Assert.False(FileProbe.IsUnder(root + @"\..\altro\film.mkv", [root]));
        Assert.False(FileProbe.IsUnder(root + "/a/../film.mkv", [root]));
    }

    [Fact]
    public void IsUnderAcceptsAChildAndRejectsASibling()
    {
        string[] roots = ["/srv/downloads"];

        Assert.True(FileProbe.IsUnder("/srv/downloads/film.mkv", roots));
        Assert.True(FileProbe.IsUnder("/srv/downloads/a/b/film.mkv", roots));
        Assert.True(FileProbe.IsUnder("/srv/downloads", roots));
        Assert.True(FileProbe.IsUnder("/srv/downloads/x", ["/srv/downloads/"]));
        Assert.False(FileProbe.IsUnder("/srv/downloads2/film.mkv", roots));
        Assert.False(FileProbe.IsUnder("/srv/altro/film.mkv", roots));
        Assert.False(FileProbe.IsUnder("/srv/downloads/film.mkv", []));
        Assert.False(FileProbe.IsUnder("/srv/downloads/film.mkv", ["/", ""]));
    }
}
