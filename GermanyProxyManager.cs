using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

namespace GermanyProxyManager
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            bool createdNew;
            using (var mutex = new System.Threading.Mutex(true, "Local\\GermanyProxyManager", out createdNew))
            {
                if (!createdNew)
                {
                    try
                    {
                        using (var signal = System.Threading.EventWaitHandle.OpenExisting("Local\\GermanyProxyManagerShow"))
                            signal.Set();
                    }
                    catch { }
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var showSignal = new System.Threading.EventWaitHandle(
                    false,
                    System.Threading.EventResetMode.AutoReset,
                    "Local\\GermanyProxyManagerShow"))
                {
                    MainForm form = new MainForm();
                    System.Threading.RegisteredWaitHandle registration =
                        System.Threading.ThreadPool.RegisterWaitForSingleObject(
                            showSignal,
                            delegate
                            {
                                if (!form.IsDisposed && form.IsHandleCreated)
                                    form.BeginInvoke(new Action(form.ShowFromTray));
                            },
                            null,
                            System.Threading.Timeout.Infinite,
                            false
                        );
                    Application.Run(form);
                    registration.Unregister(null);
                }
            }
        }
    }

    internal sealed class MainForm : Form
    {
        private const string RouterDir = @"C:\Users\250010031\.ssh\GermanyRouter";
        private const string ModeFile = @"C:\Users\250010031\.ssh\GermanyRouter\mode.txt";
        private const string RouteHealthFile = @"C:\Users\250010031\.ssh\GermanyRouter\route-health.txt";
        private const string UpstreamHealthFile = @"C:\Users\250010031\.ssh\GermanyRouter\upstream-health.txt";
        private const string UpstreamChoiceFile = @"C:\Users\250010031\.ssh\GermanyRouter\upstream-choice.txt";
        private const string ClashEndpointFile = @"C:\Users\250010031\.ssh\GermanyRouter\clash-upstream.txt";
        private const string RouterTask = "Germany Rule Router 18484";
        private const string CleanupScript = @"C:\Users\250010031\.ssh\Stop-Germany-Proxy.ps1";
        private const string RestartScript = @"C:\Users\250010031\.ssh\Restart-Germany-Router.ps1";
        private const string StartScript = @"C:\Users\250010031\.ssh\Start-Germany-Router.ps1";
        private const string UpstreamScript = @"C:\Users\250010031\.ssh\GermanyRouter\Set-Germany-Upstream.ps1";
        private const string InternetSettings = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

        private readonly Color Navy = Color.FromArgb(24, 49, 83);
        private readonly Color Blue = Color.FromArgb(34, 113, 219);
        private readonly Color PaleBlue = Color.FromArgb(235, 244, 255);
        private readonly Color Green = Color.FromArgb(26, 151, 92);
        private readonly Color Red = Color.FromArgb(205, 64, 68);
        private readonly Color Orange = Color.FromArgb(215, 126, 28);
        private readonly Color Gray = Color.FromArgb(101, 112, 126);

        private Label modeValue;
        private Label systemProxyValue;
        private Label wandaStatus;
        private Label tunnelStatus;
        private Label routerStatus;
        private Label resultLabel;
        private Button offButton;
        private Button foreignButton;
        private Button globalButton;
        private Button appsButton;
        private Button testButton;
        private Button reconnectButton;
        private TextBox clashEndpointBox;
        private Button applyClashButton;
        private Timer statusTimer;
        private NotifyIcon trayIcon;
        private ToolStripMenuItem trayStatusItem;
        private bool allowExit;
        private bool cleanupDone;
        private bool trayNoticeShown;

        public MainForm()
        {
            Text = "落地代理配置器";
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(1100, 900);
            MinimumSize = new Size(1100, 900);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(246, 248, 251);
            Font = new Font("Microsoft YaHei UI", 18F, FontStyle.Regular, GraphicsUnit.Pixel);

            BuildUi();
            BuildTray();
            RefreshStatus();

            FormClosing += HandleFormClosing;
            Resize += delegate
            {
                if (WindowState == FormWindowState.Minimized)
                    HideToTray();
            };

            statusTimer = new Timer();
            statusTimer.Interval = 2000;
            statusTimer.Tick += delegate { RefreshStatus(); };
            statusTimer.Start();

            if (Environment.GetCommandLineArgs().Any(
                value => string.Equals(value, "--tray", StringComparison.OrdinalIgnoreCase)))
            {
                Shown += delegate { BeginInvoke(new Action(HideToTray)); };
            }
        }

        private void BuildUi()
        {
            Panel header = new Panel();
            header.Dock = DockStyle.Top;
            header.Height = 110;
            header.BackColor = Navy;
            Controls.Add(header);

            Label title = new Label();
            title.Text = "落地代理配置器";
            title.ForeColor = Color.White;
            title.Font = new Font("Microsoft YaHei UI", 40F, FontStyle.Bold, GraphicsUnit.Pixel);
            title.AutoSize = true;
            title.Location = new Point(34, 18);
            header.Controls.Add(title);

            Label subtitle = new Label();
            subtitle.Text = "连接任意 Clash 兼容本地接口；订阅和节点在 Clash 内选择，最终固定从德国出口";
            subtitle.ForeColor = Color.FromArgb(194, 211, 232);
            subtitle.AutoSize = true;
            subtitle.Font = new Font("Microsoft YaHei UI", 17F, FontStyle.Regular, GraphicsUnit.Pixel);
            subtitle.Location = new Point(38, 76);
            header.Controls.Add(subtitle);

            Panel statusCard = CreateCard(new Point(28, 134), new Size(1044, 154));
            Controls.Add(statusCard);

            Label statusTitle = CreateSectionTitle("运行状态", new Point(26, 17));
            statusCard.Controls.Add(statusTitle);

            wandaStatus = CreateStatusLabel("● Clash 接口 读取中", new Point(26, 62));
            tunnelStatus = CreateStatusLabel("● 德国落地 443", new Point(370, 62));
            routerStatus = CreateStatusLabel("● 分流入口 18484", new Point(715, 62));
            statusCard.Controls.Add(wandaStatus);
            statusCard.Controls.Add(tunnelStatus);
            statusCard.Controls.Add(routerStatus);

            modeValue = new Label();
            modeValue.AutoSize = true;
            modeValue.Location = new Point(26, 108);
            modeValue.ForeColor = Gray;
            statusCard.Controls.Add(modeValue);

            systemProxyValue = new Label();
            systemProxyValue.AutoSize = true;
            systemProxyValue.Location = new Point(540, 108);
            systemProxyValue.ForeColor = Gray;
            statusCard.Controls.Add(systemProxyValue);

            Label interfaceTitle = CreateSectionTitle("Clash 接口", new Point(32, 310));
            Controls.Add(interfaceTitle);

            Label interfaceHint = new Label();
            interfaceHint.Text = "在 Clash / Clash Verge 中选择订阅和节点，这里只填写它提供的本地 HTTP/SOCKS 接口。";
            interfaceHint.ForeColor = Gray;
            interfaceHint.AutoSize = true;
            interfaceHint.Font = new Font("Microsoft YaHei UI", 15F, FontStyle.Regular, GraphicsUnit.Pixel);
            interfaceHint.Location = new Point(34, 348);
            Controls.Add(interfaceHint);

            clashEndpointBox = new TextBox();
            clashEndpointBox.Location = new Point(34, 378);
            clashEndpointBox.Size = new Size(360, 42);
            clashEndpointBox.Font = new Font("Microsoft YaHei UI", 18F, FontStyle.Regular, GraphicsUnit.Pixel);
            clashEndpointBox.Text = ReadClashEndpoint();
            Controls.Add(clashEndpointBox);

            applyClashButton = new Button();
            applyClashButton.Text = "应用接口";
            applyClashButton.Size = new Size(130, 42);
            applyClashButton.Location = new Point(410, 378);
            StyleActionButton(applyClashButton, Blue, Color.White);
            applyClashButton.Click += delegate { ApplyClashEndpoint(); };
            Controls.Add(applyClashButton);

            Label interfaceDefault = new Label();
            interfaceDefault.Text = "常见默认值：127.0.0.1:7980（Clash Verge）";
            interfaceDefault.ForeColor = Gray;
            interfaceDefault.AutoSize = true;
            interfaceDefault.Font = new Font("Microsoft YaHei UI", 15F, FontStyle.Regular, GraphicsUnit.Pixel);
            interfaceDefault.Location = new Point(560, 388);
            Controls.Add(interfaceDefault);

            Label selectTitle = CreateSectionTitle("选择转发模式", new Point(32, 448));
            Controls.Add(selectTitle);

            offButton = CreateModeButton(
                "关闭德国转发",
                "停止德国转发和分流服务\r\n系统代理保持 127.0.0.1:7892",
                new Point(28, 488)
            );
            foreignButton = CreateModeButton(
                "仅非中国走德国",
                "中国域名/IP 直接访问\r\n其余流量走德国",
                new Point(294, 488)
            );
            globalButton = CreateModeButton(
                "全局走德国",
                "本机/局域网保持直连\r\n所有公共流量走德国",
                new Point(560, 488)
            );
            appsButton = CreateModeButton(
                "仅 Claude/浏览器",
                "不改全局代理；\r\n用专用启动器走德国",
                new Point(826, 488)
            );
            Controls.Add(offButton);
            Controls.Add(foreignButton);
            Controls.Add(globalButton);
            Controls.Add(appsButton);

            offButton.Click += delegate { ApplyMode("off"); };
            foreignButton.Click += delegate { ApplyMode("foreign"); };
            globalButton.Click += delegate { ApplyMode("global"); };
            appsButton.Click += delegate { ApplyMode("apps"); };

            Panel testCard = CreateCard(new Point(28, 660), new Size(1044, 150));
            Controls.Add(testCard);

            Label testTitle = CreateSectionTitle("出口检测", new Point(26, 17));
            testCard.Controls.Add(testTitle);

            resultLabel = new Label();
            resultLabel.Text = "点击“检测出口”查看当前公网 IP";
            resultLabel.ForeColor = Gray;
            resultLabel.AutoEllipsis = true;
            resultLabel.Location = new Point(26, 62);
            resultLabel.Size = new Size(700, 58);
            testCard.Controls.Add(resultLabel);

            testButton = new Button();
            testButton.Text = "检测出口";
            testButton.Size = new Size(120, 50);
            testButton.Location = new Point(766, 60);
            StyleActionButton(testButton, Blue, Color.White);
            testButton.Click += async delegate { await TestExitAsync(); };
            testCard.Controls.Add(testButton);

            reconnectButton = new Button();
            reconnectButton.Text = "重新连接";
            reconnectButton.Size = new Size(120, 50);
            reconnectButton.Location = new Point(900, 60);
            StyleActionButton(reconnectButton, Color.White, Navy);
            reconnectButton.FlatAppearance.BorderColor = Color.FromArgb(190, 201, 214);
            reconnectButton.Click += delegate { Reconnect(); };
            testCard.Controls.Add(reconnectButton);

            Label footer = new Label();
            footer.Text = "点 × 会最小化到托盘并保持转发；托盘右键“彻底退出”才会停止服务并恢复网络。";
            footer.ForeColor = Gray;
            footer.AutoSize = true;
            footer.Location = new Point(32, 842);
            Controls.Add(footer);
        }

        private void BuildTray()
        {
            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem openItem = new ToolStripMenuItem("打开窗口");
            openItem.Font = new Font(openItem.Font, FontStyle.Bold);
            openItem.Click += delegate { ShowFromTray(); };

            trayStatusItem = new ToolStripMenuItem("当前模式：读取中");
            trayStatusItem.Enabled = false;

            ToolStripMenuItem exitItem = new ToolStripMenuItem("彻底退出");
            exitItem.Click += delegate
            {
                allowExit = true;
                CleanupOnExit();
                trayIcon.Visible = false;
                Close();
            };

            menu.Items.Add(openItem);
            menu.Items.Add(trayStatusItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(exitItem);

            trayIcon = new NotifyIcon();
            trayIcon.Icon = SystemIcons.Application;
            trayIcon.Text = "落地代理配置器";
            trayIcon.ContextMenuStrip = menu;
            trayIcon.Visible = true;
            trayIcon.DoubleClick += delegate { ShowFromTray(); };
        }

        private void HandleFormClosing(object sender, FormClosingEventArgs e)
        {
            bool systemExit =
                e.CloseReason == CloseReason.WindowsShutDown ||
                e.CloseReason == CloseReason.TaskManagerClosing;

            if (!allowExit && !systemExit)
            {
                e.Cancel = true;
                HideToTray();
                return;
            }

            CleanupOnExit();
            if (trayIcon != null)
            {
                trayIcon.Visible = false;
                trayIcon.Dispose();
            }
        }

        private void HideToTray()
        {
            Hide();
            if (!trayNoticeShown && trayIcon != null)
            {
                trayNoticeShown = true;
                trayIcon.ShowBalloonTip(
                    2500,
                    "德国代理切换器仍在运行",
                    "双击托盘图标可恢复；右键选择“彻底退出”才会关闭转发。",
                    ToolTipIcon.Info
                );
            }
        }

        public void ShowFromTray()
        {
            Show();
            WindowState = FormWindowState.Normal;
            Activate();
            BringToFront();
        }

        private Panel CreateCard(Point location, Size size)
        {
            Panel panel = new Panel();
            panel.Location = location;
            panel.Size = size;
            panel.BackColor = Color.White;
            panel.BorderStyle = BorderStyle.FixedSingle;
            return panel;
        }

        private Label CreateSectionTitle(string text, Point location)
        {
            Label label = new Label();
            label.Text = text;
            label.Font = new Font("Microsoft YaHei UI", 22F, FontStyle.Bold, GraphicsUnit.Pixel);
            label.ForeColor = Navy;
            label.AutoSize = true;
            label.Location = location;
            return label;
        }

        private Label CreateStatusLabel(string text, Point location)
        {
            Label label = new Label();
            label.Text = text;
            label.AutoSize = true;
            label.Location = location;
            label.ForeColor = Gray;
            return label;
        }

        private Button CreateModeButton(string title, string description, Point location)
        {
            Button button = new Button();
            button.Text = title + "\r\n" + description;
            button.TextAlign = ContentAlignment.MiddleLeft;
            button.Padding = new Padding(20, 14, 14, 14);
            button.Location = location;
            button.Size = new Size(250, 142);
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 1;
            button.FlatAppearance.BorderColor = Color.FromArgb(205, 214, 224);
            button.BackColor = Color.White;
            button.ForeColor = Navy;
            button.Font = new Font("Microsoft YaHei UI", 18F, FontStyle.Regular, GraphicsUnit.Pixel);
            button.UseCompatibleTextRendering = true;
            button.Cursor = Cursors.Hand;
            return button;
        }

        private void StyleActionButton(Button button, Color background, Color foreground)
        {
            button.FlatStyle = FlatStyle.Flat;
            button.FlatAppearance.BorderSize = 1;
            button.FlatAppearance.BorderColor = background;
            button.BackColor = background;
            button.ForeColor = foreground;
            button.Cursor = Cursors.Hand;
        }

        private string ReadMode()
        {
            try
            {
                string mode = File.ReadAllText(ModeFile).Trim().ToLowerInvariant();
                if (mode == "off" || mode == "foreign" || mode == "global" || mode == "apps")
                    return mode;
            }
            catch { }
            return "off";
        }

        private void ApplyMode(string mode)
        {
            try
            {
                Directory.CreateDirectory(RouterDir);
                string previousMode = ReadMode();

                if (mode == "off")
                {
                    File.WriteAllText(ModeFile, mode);
                    RunCleanup();
                    resultLabel.ForeColor = Green;
                    resultLabel.Text = "德国转发已关闭，后台服务已停止，网络已恢复。";
                }
                else
                {
                    File.WriteAllText(ModeFile, mode);
                    if (previousMode == "foreign" || previousMode == "global" || previousMode == "apps")
                        RunRestart();
                    else
                        RunStart();
                    resultLabel.ForeColor = Orange;
                    resultLabel.Text = mode == "apps"
                        ? "正在启动仅应用模式；请使用桌面上的 Claude/浏览器落地启动器。"
                        : "正在通过 Clash 接口验证德国出口；异常时保持 18484，防止出口泄露。";
                }
                RefreshStatus();
            }
            catch (Exception ex)
            {
                resultLabel.ForeColor = Red;
                resultLabel.Text = "切换失败：" + ex.Message;
            }
        }

        private void Reconnect()
        {
            try
            {
                string mode = ReadMode();
                if (mode == "off")
                {
                    resultLabel.ForeColor = Gray;
                    resultLabel.Text = "德国转发当前已关闭，无需重新连接。";
                    return;
                }

                RunRestart();
                resultLabel.ForeColor = Orange;
                resultLabel.Text = "正在通过 Clash 接口重连；系统代理保持 18484，验证前不会暴露其他出口。";
            }
            catch (Exception ex)
            {
                resultLabel.ForeColor = Red;
                resultLabel.Text = "重连失败：" + ex.Message;
            }
        }

        private void ApplyClashEndpoint()
        {
            try
            {
                string endpoint = NormalizeEndpoint(clashEndpointBox.Text);
                clashEndpointBox.Text = endpoint;
                RunHiddenChecked(
                    "powershell.exe",
                    "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" +
                    UpstreamScript + "\" -Choice clash -Endpoint \"" + endpoint + "\""
                );
                resultLabel.ForeColor = Orange;
                resultLabel.Text = "Clash 接口已应用；请在 Clash 中选择订阅和节点，再点击“重新连接”。";
                RefreshStatus();
            }
            catch (Exception ex)
            {
                resultLabel.ForeColor = Red;
                resultLabel.Text = "Clash 接口应用失败：" + ex.Message;
            }
        }

        private static string NormalizeEndpoint(string value)
        {
            string endpoint = (value ?? "").Trim();
            if (endpoint.StartsWith("http://", StringComparison.OrdinalIgnoreCase)) endpoint = endpoint.Substring(7);
            if (endpoint.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) endpoint = endpoint.Substring(8);
            string[] parts = endpoint.Split(':');
            int port;
            if (parts.Length != 2 || String.IsNullOrWhiteSpace(parts[0]) || !Int32.TryParse(parts[1], out port) || port < 1 || port > 65535)
                throw new InvalidOperationException("接口格式应为 host:port，例如 127.0.0.1:7980");
            IPAddress parsed;
            if (!IPAddress.TryParse(parts[0], out parsed) && parts[0].IndexOfAny(new[] { ' ', '/', '\\' }) >= 0)
                throw new InvalidOperationException("接口主机名无效");
            return parts[0] + ":" + port;
        }

        private async Task TestExitAsync()
        {
            testButton.Enabled = false;
            resultLabel.ForeColor = Gray;
            resultLabel.Text = "正在检测出口……";

            try
            {
                string mode = ReadMode();
                if (mode != "off" && !IsListening(18484))
                    throw new InvalidOperationException("德国转发未连接，请点击“重新连接”。");

                bool wandaAvailable = IsListening(7892);
                string proxy;
                string url;
                if (mode == "off")
                {
                    proxy = wandaAvailable ? "http://127.0.0.1:7892" : null;
                    url = wandaAvailable ? "https://api.ipify.org" : "http://myip.ipip.net";
                }
                else
                {
                    proxy = "http://127.0.0.1:18484";
                    url = "https://api.ipify.org";
                }

                string response = await DownloadStringAsync(url, proxy);
                string value = response.Trim();
                if (mode == "off")
                {
                    resultLabel.ForeColor = Blue;
                    resultLabel.Text = wandaAvailable
                        ? "WandaCloud 当前出口：" + value
                        : "本地网络：" + value;
                }
                else
                {
                    bool isGermany = value == "192.248.188.234" || value == "2a05:f480:1800:2d04:5400:5ff:fe92:1848";
                    string expected = isGermany ? "德国服务器" : "其他出口";
                    resultLabel.ForeColor = isGermany ? Green : Red;
                    resultLabel.Text = "公网 IP：" + value + "    判定：" + expected;
                }
            }
            catch (Exception ex)
            {
                resultLabel.ForeColor = Red;
                resultLabel.Text = "检测失败：" + ex.Message;
            }
            finally
            {
                testButton.Enabled = true;
            }
        }

        private static Task<string> DownloadStringAsync(string url, string proxyUrl)
        {
            return Task.Run(delegate
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                ServicePointManager.CheckCertificateRevocationList = false;
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
                request.Proxy = string.IsNullOrEmpty(proxyUrl) ? null : new WebProxy(proxyUrl);
                request.Timeout = 15000;
                request.ReadWriteTimeout = 15000;
                request.UserAgent = "GermanyProxyManager/1.0";
                using (WebResponse response = request.GetResponse())
                using (StreamReader reader = new StreamReader(response.GetResponseStream()))
                    return reader.ReadToEnd();
            });
        }

        private void RefreshStatus()
        {
            string mode = ReadMode();
            bool port7892 = IsListening(7892) || IsListening(ParseEndpointPort(ReadClashEndpoint()));
            bool port18484 = IsListening(18484);

            SetUpstreamStatus(mode, port7892);
            SetLandingStatus(mode, port18484);
            SetStatus(routerStatus, "● 分流入口 18484", port18484);

            modeValue.Text = "当前模式：" + ModeDisplay(mode);
            if (trayStatusItem != null)
                trayStatusItem.Text = "当前模式：" + ModeDisplay(mode);
            if (trayIcon != null)
                trayIcon.Text = "德国代理切换器 - " + ModeDisplay(mode);
            string proxy = GetSystemProxy();
            if (mode == "off" && port7892 && proxy != "127.0.0.1:7892")
            {
                SetSystemProxy("127.0.0.1:7892");
                proxy = "127.0.0.1:7892";
            }
            else if (mode != "off" && mode != "apps" && port18484 && IsRouteHealthy() && proxy != "127.0.0.1:18484")
            {
                SetSystemProxy("127.0.0.1:18484");
                proxy = "127.0.0.1:18484";
            }
            systemProxyValue.Text = "系统代理：" + (string.IsNullOrEmpty(proxy) ? "未启用" : proxy);

            HighlightMode(offButton, mode == "off");
            HighlightMode(foreignButton, mode == "foreign");
            HighlightMode(globalButton, mode == "global");
            HighlightMode(appsButton, mode == "apps");
            if (clashEndpointBox != null && !clashEndpointBox.Focused) clashEndpointBox.Text = ReadClashEndpoint();
        }

        private void SetStatus(Label label, string text, bool ok)
        {
            label.Text = text + (ok ? "  正常" : "  未连接");
            label.ForeColor = ok ? Green : Red;
        }

        private void SetUpstreamStatus(string mode, bool clashListening)
        {
            string endpoint = ReadClashEndpoint();
            if (mode == "off")
            {
                SetStatus(wandaStatus, "● Clash 接口 " + endpoint, clashListening);
                return;
            }
            try
            {
                FileInfo health = new FileInfo(UpstreamHealthFile);
                string value = health.Exists ? File.ReadAllText(UpstreamHealthFile) : "";
                double ageSeconds = health.Exists ? (DateTime.Now - health.LastWriteTime).TotalSeconds : 999;
                string active = ReadHealthValue(value, "active");
                if (ageSeconds > 60)
                {
                    wandaStatus.Text = "● Clash 接口 " + endpoint + "  状态待更新";
                    wandaStatus.ForeColor = Orange;
                }
                else if (active == "Clash-Upstream")
                {
                    wandaStatus.Text = "● Clash 接口 " + endpoint;
                    wandaStatus.ForeColor = value.Contains("state=healthy") || value.Contains("state=manual") ? Green : Orange;
                }
                else if (active == "Wanda-Upstream")
                {
                    wandaStatus.Text = "● 兼容接口 WandaCloud 7892";
                    wandaStatus.ForeColor = value.Contains("state=manual") ? Green : Orange;
                }
                else
                {
                    wandaStatus.Text = "● Clash 接口 " + endpoint + "  验证中";
                    wandaStatus.ForeColor = Orange;
                }
            }
            catch
            {
                wandaStatus.Text = "● Clash 接口 " + endpoint + "  状态未知";
                wandaStatus.ForeColor = Orange;
            }
        }

        private static string ReadHealthValue(string content, string key)
        {
            string prefix = key + "=";
            string line = content.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .FirstOrDefault(item => item.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
            return line == null ? "" : line.Substring(prefix.Length).Trim();
        }

        private static string ReadClashEndpoint()
        {
            try
            {
                string value = File.ReadAllText(ClashEndpointFile).Trim();
                return NormalizeEndpoint(value);
            }
            catch { return "127.0.0.1:7980"; }
        }

        private static string ReadUpstreamChoice()
        {
            try
            {
                string value = File.ReadAllText(UpstreamChoiceFile).Trim().ToLowerInvariant();
                if (value == "bigairport" || value == "wanda") return value;
            }
            catch { }
            return "wanda";
        }

        private void SetLandingStatus(string mode, bool routerListening)
        {
            try
            {
                FileInfo health = new FileInfo(RouteHealthFile);
                string value = health.Exists ? File.ReadAllText(RouteHealthFile) : "";
                double ageSeconds = health.Exists ? (DateTime.Now - health.LastWriteTime).TotalSeconds : 999;
                if (mode == "off" && value.Contains("state=fallback"))
                {
                    tunnelStatus.Text = "● 德国落地 443  历史回退状态";
                    tunnelStatus.ForeColor = Orange;
                }
                else if (mode == "off")
                {
                    tunnelStatus.Text = "● 德国落地 443  待命";
                    tunnelStatus.ForeColor = Gray;
                }
                else if (routerListening && ageSeconds <= 30 && value.Contains("state=healthy"))
                {
                    tunnelStatus.Text = "● 德国落地 443  健康";
                    tunnelStatus.ForeColor = Green;
                }
                else if (value.Contains("state=starting"))
                {
                    tunnelStatus.Text = "● 德国落地 443  验证中";
                    tunnelStatus.ForeColor = Orange;
                }
                else if (value.Contains("state=degraded"))
                {
                    tunnelStatus.Text = "● 德国落地 443  波动，保持德国出口";
                    tunnelStatus.ForeColor = Orange;
                }
                else if (value.Contains("state=fallback"))
                {
                    tunnelStatus.Text = "● 德国落地 443  历史回退状态";
                    tunnelStatus.ForeColor = Red;
                }
                else
                {
                    tunnelStatus.Text = "● 德国落地 443  未连接";
                    tunnelStatus.ForeColor = Orange;
                }
            }
            catch
            {
                tunnelStatus.Text = "● 德国落地 443  状态未知";
                tunnelStatus.ForeColor = Orange;
            }
        }

        private static bool IsRouteHealthy()
        {
            try
            {
                FileInfo health = new FileInfo(RouteHealthFile);
                if (!health.Exists || (DateTime.Now - health.LastWriteTime).TotalSeconds > 30)
                    return false;
                return File.ReadAllText(RouteHealthFile).Contains("state=healthy");
            }
            catch { return false; }
        }

        private void HighlightMode(Button button, bool selected)
        {
            button.BackColor = selected ? PaleBlue : Color.White;
            button.FlatAppearance.BorderColor = selected ? Blue : Color.FromArgb(205, 214, 224);
            button.FlatAppearance.BorderSize = selected ? 2 : 1;
        }

        private static string ModeDisplay(string mode)
        {
            if (mode == "foreign") return "仅非中国走德国";
            if (mode == "global") return "全局走德国";
            if (mode == "apps") return "仅 Claude/浏览器";
            return "关闭德国转发";
        }

        private static int ParseEndpointPort(string endpoint)
        {
            int port;
            return Int32.TryParse(endpoint.Split(':').Last(), out port) ? port : 7980;
        }

        private static bool IsListening(int port)
        {
            try
            {
                return IPGlobalProperties.GetIPGlobalProperties()
                    .GetActiveTcpListeners()
                    .Any(endpoint => endpoint.Port == port);
            }
            catch { return false; }
        }

        private static string GetSystemProxy()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(InternetSettings))
                {
                    int enabled = Convert.ToInt32(key.GetValue("ProxyEnable", 0));
                    return enabled == 1 ? Convert.ToString(key.GetValue("ProxyServer", "")) : "";
                }
            }
            catch { return ""; }
        }

        private static void SetSystemProxy(string proxy)
        {
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(InternetSettings, true))
            {
                key.SetValue("ProxyEnable", 1, RegistryValueKind.DWord);
                key.SetValue("ProxyServer", proxy, RegistryValueKind.String);
                string proxyOverride = Convert.ToString(key.GetValue("ProxyOverride", ""));
                var overrideItems = new System.Collections.Generic.List<string>(
                    proxyOverride.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries));
                foreach (string schoolBypass in new[] { "slai.edu.cn", "*.slai.edu.cn" })
                {
                    if (!overrideItems.Exists(item => string.Equals(item, schoolBypass, StringComparison.OrdinalIgnoreCase)))
                        overrideItems.Add(schoolBypass);
                }
                key.SetValue("ProxyOverride", string.Join(";", overrideItems), RegistryValueKind.String);
            }
            InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
            InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
        }

        private void CleanupOnExit()
        {
            if (cleanupDone) return;
            cleanupDone = true;
            try { RunCleanup(); }
            catch { }
        }

        private static void RunCleanup()
        {
            RunHidden(
                "powershell.exe",
                "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + CleanupScript + "\""
            );
        }

        private static void RunRestart()
        {
            RunHidden(
                "powershell.exe",
                "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + RestartScript + "\""
            );
        }

        private static void RunTask(string taskName)
        {
            RunHidden("schtasks.exe", "/Run /TN \"" + taskName + "\"");
        }

        private static void RunStart()
        {
            RunHidden("powershell.exe", "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + StartScript + "\"");
        }

        private static void EndTask(string taskName)
        {
            RunHidden("schtasks.exe", "/End /TN \"" + taskName + "\"");
        }

        private static void RunHidden(string file, string arguments)
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = file;
            info.Arguments = arguments;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            Process process = Process.Start(info);
            process.WaitForExit(5000);
        }

        private static void RunHiddenChecked(string file, string arguments)
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = file;
            info.Arguments = arguments;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            Process process = Process.Start(info);
            if (!process.WaitForExit(30000))
                throw new InvalidOperationException("操作超时");
            if (process.ExitCode != 0)
                throw new InvalidOperationException("操作失败，退出码 " + process.ExitCode);
        }

        [DllImport("wininet.dll", SetLastError = true)]
        private static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int length);
    }
}
