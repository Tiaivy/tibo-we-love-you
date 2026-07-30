using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace TiboWeLoveYou.Windows;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext());
    }
}

internal sealed class TrayApplicationContext : ApplicationContext
{
    private const string FeedUrl =
        "https://tiboweloveyou-feed.tiboweloveyou.workers.dev/v1/reset/latest";

    private readonly HttpClient _httpClient = new()
    {
        Timeout = TimeSpan.FromSeconds(15)
    };
    private readonly NotifyIcon _trayIcon;
    private readonly System.Windows.Forms.Timer _pollTimer;
    private readonly HashSet<string> _seenIds;
    private readonly string _statePath;

    private ResetAlertForm? _resetAlert;
    private bool _isFirstCheck;
    private bool _isChecking;

    internal TrayApplicationContext()
    {
        _statePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TiboWeLoveYou",
            "state.json"
        );
        _seenIds = LoadSeenIds();
        _isFirstCheck = _seenIds.Count == 0;

        var menu = new ContextMenuStrip();
        menu.Items.Add(
            "Check now",
            null,
            async (_, _) => await CheckAsync(showStatus: true)
        );
        menu.Items.Add(
            "Test button animation",
            null,
            (_, _) => ShowResetAlert(
                new FeedEvent(
                    "demo",
                    "confirmed",
                    "ChatGPT and Codex limits have been reset.",
                    "https://x.com/thsottiaux",
                    DateTimeOffset.Now.ToString("O")
                )
            )
        );
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => ExitThread());

        _trayIcon = new NotifyIcon
        {
            ContextMenuStrip = menu,
            Icon = AssetLoader.CreateTrayIcon(),
            Text = "Tibo, We Love You",
            Visible = true
        };

        _pollTimer = new System.Windows.Forms.Timer
        {
            Interval = 60_000,
            Enabled = true
        };
        _pollTimer.Tick += async (_, _) => await CheckAsync();

        _ = CheckAsync(seedIfNeeded: true);
    }

    protected override void ExitThreadCore()
    {
        _pollTimer.Stop();
        _pollTimer.Dispose();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _resetAlert?.Close();
        _httpClient.Dispose();
        base.ExitThreadCore();
    }

    private async Task CheckAsync(
        bool showStatus = false,
        bool seedIfNeeded = false
    )
    {
        if (_isChecking)
        {
            return;
        }

        _isChecking = true;
        try
        {
            using var response = await _httpClient.GetAsync(FeedUrl);
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync();
            var snapshot = await JsonSerializer.DeserializeAsync<FeedSnapshot>(
                stream,
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                }
            );
            if (snapshot is null)
            {
                throw new InvalidDataException("The central feed returned no data.");
            }

            var lastResetAt = ParseDate(snapshot.LastResetAt);
            var didAlert = ProcessSnapshot(
                snapshot,
                seedIfNeeded && _isFirstCheck
            );
            if (
                showStatus
                && !didAlert
                && _resetAlert?.Visible != true
            )
            {
                StatusPopupForm.ShowStatus(lastResetAt);
            }
        }
        catch when (showStatus)
        {
            StatusPopupForm.ShowUnavailable();
        }
        catch
        {
            // Background checks retry automatically on the next minute.
        }
        finally
        {
            _isChecking = false;
        }
    }

    private bool ProcessSnapshot(FeedSnapshot snapshot, bool seedOnly)
    {
        if (snapshot.Event is null)
        {
            _isFirstCheck = false;
            return false;
        }

        if (seedOnly)
        {
            _seenIds.Add(snapshot.Event.Id);
            _isFirstCheck = false;
            SaveSeenIds();
            return false;
        }

        if (_seenIds.Contains(snapshot.Event.Id))
        {
            return false;
        }

        _seenIds.Add(snapshot.Event.Id);
        _isFirstCheck = false;
        SaveSeenIds();

        if (
            !string.Equals(
                snapshot.Event.Signal,
                "confirmed",
                StringComparison.OrdinalIgnoreCase
            )
            || !Uri.TryCreate(
                snapshot.Event.Url,
                UriKind.Absolute,
                out _
            )
        )
        {
            return false;
        }

        ShowResetAlert(snapshot.Event);
        return true;
    }

    private void ShowResetAlert(FeedEvent resetEvent)
    {
        _resetAlert?.Close();
        _resetAlert = new ResetAlertForm(resetEvent);
        _resetAlert.FormClosed += (_, _) => _resetAlert = null;
        _resetAlert.ShowAtTray();
    }

    private HashSet<string> LoadSeenIds()
    {
        try
        {
            if (!File.Exists(_statePath))
            {
                return [];
            }

            return JsonSerializer.Deserialize<HashSet<string>>(
                File.ReadAllText(_statePath)
            ) ?? [];
        }
        catch
        {
            return [];
        }
    }

    private void SaveSeenIds()
    {
        try
        {
            var directory = Path.GetDirectoryName(_statePath);
            if (directory is not null)
            {
                Directory.CreateDirectory(directory);
            }

            var limited = _seenIds
                .OrderBy(id => id, StringComparer.Ordinal)
                .TakeLast(300)
                .ToArray();
            File.WriteAllText(
                _statePath,
                JsonSerializer.Serialize(limited)
            );
        }
        catch
        {
            // A failed local save must not stop the reminder.
        }
    }

    private static DateTimeOffset? ParseDate(string? rawValue)
    {
        return DateTimeOffset.TryParse(rawValue, out var date)
            ? date
            : null;
    }
}

internal sealed class StatusPopupForm : PopupForm
{
    private readonly DateTimeOffset? _lastResetAt;
    private readonly bool _isUnavailable;
    private readonly Image _emoji = AssetLoader.LoadImage(
        "CheckStatusEmoji.jpg"
    );
    private readonly System.Windows.Forms.Timer _dismissTimer;

    private StatusPopupForm(
        DateTimeOffset? lastResetAt,
        bool isUnavailable
    )
        : base(new Size(342, 124))
    {
        _lastResetAt = lastResetAt;
        _isUnavailable = isUnavailable;
        _dismissTimer = new System.Windows.Forms.Timer
        {
            Interval = 4_000
        };
        _dismissTimer.Tick += (_, _) => Close();
        Shown += (_, _) => _dismissTimer.Start();
    }

    internal static void ShowStatus(DateTimeOffset? lastResetAt)
    {
        new StatusPopupForm(lastResetAt, isUnavailable: false).ShowAtTray();
    }

    internal static void ShowUnavailable()
    {
        new StatusPopupForm(null, isUnavailable: true).ShowAtTray();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _dismissTimer.Dispose();
            _emoji.Dispose();
        }
        base.Dispose(disposing);
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);

        var graphics = eventArgs.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.InterpolationMode =
            InterpolationMode.HighQualityBicubic;

        graphics.DrawImage(
            _emoji,
            new Rectangle(18, 35, 72, 52),
            new Rectangle(0, 400, 560, 410),
            GraphicsUnit.Pixel
        );

        using var titleFont = new Font(
            "Segoe UI",
            15,
            FontStyle.Bold,
            GraphicsUnit.Pixel
        );
        using var bodyFont = new Font(
            "Segoe UI",
            12,
            FontStyle.Regular,
            GraphicsUnit.Pixel
        );
        using var finalFont = new Font(
            "Segoe UI",
            12,
            FontStyle.Bold,
            GraphicsUnit.Pixel
        );
        using var titleBrush = new SolidBrush(Color.FromArgb(18, 19, 22));
        using var bodyBrush = new SolidBrush(Color.FromArgb(110, 117, 125));
        using var finalBrush = new SolidBrush(Color.FromArgb(66, 71, 77));

        if (_isUnavailable)
        {
            graphics.DrawString(
                "Couldn’t check right now",
                titleFont,
                titleBrush,
                102,
                30
            );
            graphics.DrawString(
                "We’ll try again automatically.",
                bodyFont,
                bodyBrush,
                102,
                58
            );
            return;
        }

        graphics.DrawString(
            "Nothing new yet",
            titleFont,
            titleBrush,
            102,
            19
        );
        graphics.DrawString(
            LastResetText(),
            bodyFont,
            bodyBrush,
            102,
            47
        );
        graphics.DrawString(
            ElapsedText(),
            bodyFont,
            bodyBrush,
            102,
            68
        );
        graphics.DrawString(
            "Next reset? Only God knows.",
            finalFont,
            finalBrush,
            102,
            91
        );
    }

    private string LastResetText()
    {
        return _lastResetAt is null
            ? "No Tibo reset recorded yet"
            : $"Last Tibo reset · {_lastResetAt.Value.ToLocalTime():MMM d, yyyy HH:mm}";
    }

    private string ElapsedText()
    {
        if (_lastResetAt is null)
        {
            return "Waiting for the first confirmed reset";
        }

        var elapsed = DateTimeOffset.Now - _lastResetAt.Value.ToLocalTime();
        var totalMinutes = Math.Max(0, (int)elapsed.TotalMinutes);
        if (totalMinutes == 0)
        {
            return "Less than a minute ago";
        }

        var days = totalMinutes / (24 * 60);
        var hours = (totalMinutes % (24 * 60)) / 60;
        var minutes = totalMinutes % 60;

        if (days > 0)
        {
            return JoinElapsed(
                Unit(days, "day"),
                hours > 0 ? Unit(hours, "hour") : null
            );
        }
        if (hours > 0)
        {
            return JoinElapsed(
                Unit(hours, "hour"),
                minutes > 0 ? Unit(minutes, "minute") : null
            );
        }
        return $"{Unit(minutes, "minute")} ago";
    }

    private static string JoinElapsed(string first, string? second)
    {
        return second is null
            ? $"{first} ago"
            : $"{first}, {second} ago";
    }

    private static string Unit(int value, string singular)
    {
        return $"{value} {singular}{(value == 1 ? "" : "s")}";
    }
}

internal sealed class ResetAlertForm : PopupForm
{
    private readonly FeedEvent _resetEvent;
    private readonly Image _buttonImage = AssetLoader.LoadImage(
        "TiboButtonPhoto.png"
    );
    private readonly System.Windows.Forms.Timer _animationTimer;
    private bool _isPressed;
    private int _animationSteps;

    internal ResetAlertForm(FeedEvent resetEvent)
        : base(new Size(342, 134))
    {
        _resetEvent = resetEvent;

        var closeButton = new Button
        {
            Text = "×",
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 14, FontStyle.Regular),
            ForeColor = Color.FromArgb(122, 128, 135),
            BackColor = Color.White,
            Size = new Size(28, 28),
            Location = new Point(306, 6),
            TabStop = false
        };
        closeButton.FlatAppearance.BorderSize = 0;
        closeButton.Click += (_, _) => Close();
        Controls.Add(closeButton);

        var link = new LinkLabel
        {
            Text = "View Tibo’s post on X ↗",
            AutoSize = true,
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
            LinkColor = Color.FromArgb(186, 20, 31),
            ActiveLinkColor = Color.FromArgb(150, 16, 25),
            Location = new Point(96, 96)
        };
        link.LinkClicked += (_, _) => OpenPost();
        Controls.Add(link);

        _animationTimer = new System.Windows.Forms.Timer
        {
            Interval = 180
        };
        _animationTimer.Tick += (_, _) =>
        {
            _animationSteps += 1;
            _isPressed = !_isPressed;
            Invalidate(new Rectangle(12, 26, 76, 76));
            if (_animationSteps >= 28)
            {
                _isPressed = false;
                _animationTimer.Stop();
                Invalidate(new Rectangle(12, 26, 76, 76));
            }
        };
        Shown += (_, _) => _animationTimer.Start();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _animationTimer.Dispose();
            _buttonImage.Dispose();
        }
        base.Dispose(disposing);
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);

        var graphics = eventArgs.Graphics;
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.InterpolationMode =
            InterpolationMode.HighQualityBicubic;

        var buttonY = _isPressed ? 35 : 32;
        graphics.DrawImage(
            _buttonImage,
            new Rectangle(16, buttonY, 66, 66)
        );

        using var titleFont = new Font(
            "Segoe UI",
            18,
            FontStyle.Bold,
            GraphicsUnit.Pixel
        );
        using var bodyFont = new Font(
            "Segoe UI",
            12,
            FontStyle.Regular,
            GraphicsUnit.Pixel
        );
        using var titleBrush = new SolidBrush(Color.FromArgb(18, 19, 22));
        using var bodyBrush = new SolidBrush(Color.FromArgb(110, 117, 125));

        graphics.DrawString(
            "Tibo hit reset!",
            titleFont,
            titleBrush,
            96,
            22
        );
        graphics.DrawString(
            "ChatGPT and Codex limits have\nbeen reset. Back to building!",
            bodyFont,
            bodyBrush,
            new RectangleF(96, 50, 220, 42)
        );
    }

    private void OpenPost()
    {
        try
        {
            Process.Start(
                new ProcessStartInfo(_resetEvent.Url)
                {
                    UseShellExecute = true
                }
            );
        }
        catch
        {
            // The alert remains available if Windows cannot open the browser.
        }
    }
}

internal abstract class PopupForm : Form
{
    protected PopupForm(Size size)
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        BackColor = Color.White;
        Size = size;
        DoubleBuffered = true;
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            const int WsExToolWindow = 0x00000080;
            const int WsExNoActivate = 0x08000000;
            var parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
            return parameters;
        }
    }

    internal void ShowAtTray()
    {
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(
            area.Right - Width - 16,
            area.Bottom - Height - 16
        );
        Show();
    }

    protected override void OnShown(EventArgs eventArgs)
    {
        base.OnShown(eventArgs);
        using var path = RoundedRectangle(
            new Rectangle(0, 0, Width, Height),
            18
        );
        Region = new Region(path);
    }

    protected override void OnPaint(PaintEventArgs eventArgs)
    {
        base.OnPaint(eventArgs);
        eventArgs.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var border = new Pen(Color.FromArgb(222, 224, 229));
        using var path = RoundedRectangle(
            new Rectangle(0, 0, Width - 1, Height - 1),
            18
        );
        eventArgs.Graphics.DrawPath(border, path);
    }

    private static GraphicsPath RoundedRectangle(
        Rectangle bounds,
        int radius
    )
    {
        var diameter = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(
            bounds.Right - diameter,
            bounds.Top,
            diameter,
            diameter,
            270,
            90
        );
        path.AddArc(
            bounds.Right - diameter,
            bounds.Bottom - diameter,
            diameter,
            diameter,
            0,
            90
        );
        path.AddArc(
            bounds.Left,
            bounds.Bottom - diameter,
            diameter,
            diameter,
            90,
            90
        );
        path.CloseFigure();
        return path;
    }
}

internal static class AssetLoader
{
    internal static Image LoadImage(string name)
    {
        using var stream = Assembly
            .GetExecutingAssembly()
            .GetManifestResourceStream(name)
            ?? throw new InvalidOperationException(
                $"Missing embedded resource: {name}"
            );
        using var source = Image.FromStream(stream);
        return new Bitmap(source);
    }

    internal static Icon CreateTrayIcon()
    {
        using var source = LoadImage("TiboButtonPhoto.png");
        using var bitmap = new Bitmap(32, 32, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.Transparent);
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.InterpolationMode =
                InterpolationMode.HighQualityBicubic;
            graphics.DrawImage(source, new Rectangle(0, 0, 32, 32));
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var temporary = Icon.FromHandle(handle);
            return (Icon)temporary.Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);
}

internal sealed record FeedSnapshot(
    int Version,
    string Source,
    string? CheckedAt,
    string? LastResetAt,
    FeedEvent? Event
);

internal sealed record FeedEvent(
    string Id,
    string Signal,
    string Text,
    string Url,
    string CreatedAt
);
