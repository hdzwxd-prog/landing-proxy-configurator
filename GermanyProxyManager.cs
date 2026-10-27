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
        private static readonly string RouterDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter");
        private static readonly string ModeFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\mode.txt");
        private static readonly string RouteHealthFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\route-health.txt");
        private static readonly string UpstreamHealthFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\upstream-health.txt");
        private static readonly string UpstreamChoiceFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\upstream-choice.txt");
        private static readonly string ClashEndpointFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\clash-upstream.txt");
        private const string RouterTask = "Germany Rule Router 18484";
        private static readonly string CleanupScript = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\Stop-Germany-Proxy.ps1");
        private static readonly string RestartScript = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\Restart-Germany-Router.ps1");
        private static readonly string StartScript = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\Start-Germany-Router.ps1");
        private static readonly string UpstreamScript = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\Set-Germany-Upstream.ps1");
        private static readonly string LandingChoiceFile = RouterDir + @"\landing-choice.txt";
        private static readonly string LandingScript = RouterDir + @"\Set-Landing-Exit.ps1";
        private const string InternetSettings = @"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
        private static readonly string ProxyBackupFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\proxy-restore.txt");

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
        private Label appConnectionLabel;
        private CheckBox edgeLandingCheck;
        private Label edgePolicyLabel;
        private bool edgePolicyBusy;
        private Button offButton;
        private Button foreignButton;
        private Button globalButton;
        private Button appsButton;
        private Button testButton;
        private Button reconnectButton;
        private Button refreshStatusButton;
        private TextBox clashEndpointBox;
        private Button applyClashButton;
        private ComboBox upstreamChoiceBox;
        private Button applyUpstreamButton;
        private ComboBox landingChoiceBox;
        private Button applyLandingButton;
        private DateTime lastExitTestAt;
        private string lastExitChoice;
        private string lastTestRoute;
        private bool routeBusy;
        private Timer statusTimer;
        private NotifyIcon trayIcon;
        private ToolStripMenuItem trayStatusItem;
        private bool allowExit;
        private bool cleanupDone;
        private bool trayNoticeShown;
        private bool hasExitTest;
        private bool lastExitMatches;

        public MainForm()
        {
            Text = "落地代理配置器";
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(1100, 1040);
            AutoScroll = true;
            MinimumSize = new Size(1100, 760);
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
            subtitle.Text = "订阅和节点在 Clash / Wanda 内选择；这里选择独立的落地出口";
            subtitle.ForeColor = Color.FromArgb(194, 211, 232);
            subtitle.AutoSize = true;
            subtitle.Font = new Font("Microsoft YaHei UI", 17F, FontStyle.Regular, GraphicsUnit.Pixel);
            subtitle.Location = new Point(38, 76);
            header.Controls.Add(subtitle);

            Panel statusCard = CreateCard(new Point(28, 134), new Size(1044, 154));
            Controls.Add(statusCard);

            Label statusTitle = CreateSectionTitle("运行状态", new Point(26, 17));
            statusCard.Controls.Add(statusTitle);

            refreshStatusButton = new Button();
            refreshStatusButton.Text = "刷新状态";
            refreshStatusButton.Size = new Size(112, 38);
            refreshStatusButton.Location = new Point(900, 12);
            StyleActionButton(refreshStatusButton, Color.White, Navy);
            refreshStatusButton.FlatAppearance.BorderColor = Color.FromArgb(190, 201, 214);
            refreshStatusButton.Click += async delegate { await TestExitAsync(); };
            statusCard.Controls.Add(refreshStatusButton);

            wandaStatus = CreateStatusLabel("● Clash 接口 读取中", new Point(26, 55));
            tunnelStatus = CreateStatusLabel("● 落地出口", new Point(26, 84));
            routerStatus = CreateStatusLabel("● 分流入口 18484", new Point(715, 84));
            wandaStatus.AutoSize = false;
            wandaStatus.Size = new Size(850, 28);
            tunnelStatus.AutoSize = false;
            tunnelStatus.Size = new Size(680, 28);
            statusCard.Controls.Add(wandaStatus);
            statusCard.Controls.Add(tunnelStatus);
            statusCard.Controls.Add(routerStatus);

            modeValue = new Label();
            modeValue.AutoSize = true;
            modeValue.Location = new Point(26, 118);
            modeValue.ForeColor = Gray;
            statusCard.Controls.Add(modeValue);

            systemProxyValue = new Label();
            systemProxyValue.AutoSize = true;
            systemProxyValue.Location = new Point(540, 118);
            systemProxyValue.ForeColor = Gray;
            statusCard.Controls.Add(systemProxyValue);

            Label interfaceTitle = CreateSectionTitle("Clash 接口", new Point(32, 310));
            Controls.Add(interfaceTitle);

            Label interfaceHint = new Label();
            interfaceHint.Text = "填写本地混合 / HTTP 端口；端口以客户端配置为准（7890 / 7980 等）。";
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
            applyClashButton.Click += async delegate {
                try { await ApplyRouteAsync(UpstreamScript, "-Choice clash -Endpoint \"" + NormalizeEndpoint(clashEndpointBox.Text) + "\""); }
                catch (Exception ex) { resultLabel.Text = ex.Message; resultLabel.ForeColor = Red; }
            };
            Controls.Add(applyClashButton);

            Label interfaceDefault = new Label();
            interfaceDefault.Text = "第一跳来源";
            interfaceDefault.ForeColor = Gray;
            interfaceDefault.AutoSize = true;
            interfaceDefault.Font = new Font("Microsoft YaHei UI", 15F, FontStyle.Regular, GraphicsUnit.Pixel);
            interfaceDefault.Location = new Point(560, 350);
            Controls.Add(interfaceDefault);

            upstreamChoiceBox = new ComboBox();
            upstreamChoiceBox.DropDownStyle = ComboBoxStyle.DropDownList;
            upstreamChoiceBox.Items.Add("当前 Clash 接口");
            upstreamChoiceBox.Items.Add("WandaCloud 7892");
            upstreamChoiceBox.Location = new Point(560, 378);
            upstreamChoiceBox.Size = new Size(220, 42);
            upstreamChoiceBox.Font = new Font("Microsoft YaHei UI", 15F, FontStyle.Regular, GraphicsUnit.Pixel);
            upstreamChoiceBox.SelectedIndex = UpstreamChoiceIndex(ReadUpstreamChoice());
            Controls.Add(upstreamChoiceBox);

            applyUpstreamButton = new Button();
            applyUpstreamButton.Text = "应用第一跳";
            applyUpstreamButton.Size = new Size(125, 42);
            applyUpstreamButton.Location = new Point(792, 378);
            StyleActionButton(applyUpstreamButton, Blue, Color.White);
            applyUpstreamButton.Click += async delegate {
                try {
                    string choice = UpstreamChoiceFromIndex(upstreamChoiceBox.SelectedIndex);
                    string extra = choice == "clash" ? " -Endpoint \"" + NormalizeEndpoint(clashEndpointBox.Text) + "\"" : "";
                    await ApplyRouteAsync(UpstreamScript, "-Choice " + choice + extra);
                } catch (Exception ex) { resultLabel.Text = ex.Message; resultLabel.ForeColor = Red; }
            };
            Controls.Add(applyUpstreamButton);

            Label landingTitle = CreateSectionTitle("落地出口", new Point(32, 438));
            Controls.Add(landingTitle);
            landingChoiceBox = new ComboBox();
            landingChoiceBox.DropDownStyle = ComboBoxStyle.DropDownList;
            landingChoiceBox.Font = new Font("Microsoft YaHei UI", 17F, FontStyle.Regular, GraphicsUnit.Pixel);
            landingChoiceBox.Items.Add("原德国出口  ·  192.248.188.234");
            landingChoiceBox.Items.Add("NAS04  ·  212.121.132.230  ·  SSH");
            landingChoiceBox.Location = new Point(170, 438);
            landingChoiceBox.Size = new Size(410, 38);
            landingChoiceBox.SelectedIndex = ReadLandingChoice() == "nas04" ? 1 : 0;
            Controls.Add(landingChoiceBox);
            applyLandingButton = new Button();
            applyLandingButton.Text = "应用落地";
            applyLandingButton.Size = new Size(130, 40);
            applyLandingButton.Location = new Point(600, 432);
            StyleActionButton(applyLandingButton, Blue, Color.White);
            applyLandingButton.Click += async delegate {
                string choice = landingChoiceBox.SelectedIndex == 1 ? "nas04" : "germany";
                await ApplyRouteAsync(LandingScript, "-Choice " + choice);
            };
            Controls.Add(applyLandingButton);

            Label selectTitle = CreateSectionTitle("选择转发模式", new Point(32, 500));
            Controls.Add(selectTitle);

            offButton = CreateModeButton(
                "关闭落地转发",
                "停止落地服务\r\nClash / Wanda 保持运行",
                new Point(28, 540)
            );
            foreignButton = CreateModeButton(
                "仅非中国走落地",
                "中国域名/IP 直接访问\r\n其余流量走所选出口",
                new Point(294, 540)
            );
            globalButton = CreateModeButton(
                "全局走落地",
                "本机/局域网保持直连\r\n公共流量走所选出口",
                new Point(560, 540)
            );
            appsButton = CreateModeButton(
                "仅指定应用",
                "系统代理不变\r\n单独配置应用",
                new Point(826, 540)
            );
            Controls.Add(offButton);
            Controls.Add(foreignButton);
            Controls.Add(globalButton);
            Controls.Add(appsButton);

            offButton.Click += delegate { ApplyMode("off"); };
            foreignButton.Click += delegate { ApplyMode("foreign"); };
            globalButton.Click += delegate { ApplyMode("global"); };
            appsButton.Click += delegate { ApplyMode("apps"); };

            edgeLandingCheck = new CheckBox();
            edgeLandingCheck.Text = "Edge 使用落地代理（含默认链接）";
            edgeLandingCheck.AutoCheck = false;
            edgeLandingCheck.Size = new Size(390, 32);
            edgeLandingCheck.Location = new Point(32, 690);
            edgeLandingCheck.Click += async delegate { await SetEdgePolicyAsync(!edgeLandingCheck.Checked); };
            Controls.Add(edgeLandingCheck);
            edgePolicyLabel = new Label();
            edgePolicyLabel.Size = new Size(640, 32);
            edgePolicyLabel.Location = new Point(428, 694);
            edgePolicyLabel.ForeColor = Gray;
            Controls.Add(edgePolicyLabel);
            RefreshEdgePolicy();
            string[] launchNames = { "启动 Claude 客户端", "核对 Claude 连接" };
            string[] launchScripts = { "Start-Claude-Landing.ps1", "Test-Claude-Landing.ps1" };
            for (int i = 0; i < launchNames.Length; i++)
            {
                Button action = new Button();
                action.Text = launchNames[i];
                action.Size = new Size(220, 40);
                action.Location = new Point(32 + i * 240, 726);
                StyleActionButton(action, Blue, Color.White);
                string scriptName = launchScripts[i];
                action.Click += async delegate {
                    action.Enabled = false;
                    try {
                        await Task.Run(delegate { RunHiddenChecked("powershell.exe",
                            "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + Path.Combine(RouterDir, scriptName) + "\""); });
                        if (scriptName == "Test-Claude-Landing.ps1") {
                            appConnectionLabel.Text = File.ReadAllText(Path.Combine(RouterDir, "claude-client-check.txt")).Trim() + "  [" + DateTime.Now.ToString("HH:mm:ss") + "]";
                            appConnectionLabel.ForeColor = Orange;
                        }
                    } catch (Exception ex) { MessageBox.Show(ex.Message, "应用接入", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
                    finally { action.Enabled = true; }
                };
                Controls.Add(action);
            }
            Button edgeTest = new Button();
            edgeTest.Text = "检查 Edge 出口";
            edgeTest.Size = new Size(220, 40);
            edgeTest.Location = new Point(512, 726);
            StyleActionButton(edgeTest, Color.White, Navy);
            edgeTest.Click += delegate {
                try { Process.Start("microsoft-edge:https://api.ipify.org"); }
                catch (Exception ex) { MessageBox.Show(ex.Message, "Edge 出口检测"); }
            };
            Controls.Add(edgeTest);
            appConnectionLabel = new Label();
            appConnectionLabel.Text = "Claude 客户端连接尚未核对。下方绿色出口仅表示落地服务正常。";
            appConnectionLabel.ForeColor = Gray;
            appConnectionLabel.Size = new Size(1020, 30);
            appConnectionLabel.Location = new Point(32, 778);
            Controls.Add(appConnectionLabel);

            Panel testCard = CreateCard(new Point(28, 818), new Size(1044, 150));
            Controls.Add(testCard);

            Label testTitle = CreateSectionTitle("落地服务出口检测（不代表应用已接入）", new Point(26, 17));
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
            footer.Text = "× 收进托盘；退出停止落地。Clash/Wanda 不受影响；Edge 取消勾选可恢复原代理。";
            footer.ForeColor = Gray;
            footer.AutoSize = true;
            footer.Location = new Point(32, 990);
            Controls.Add(footer);
        }

        private void RefreshEdgePolicy()
        {
            if (edgePolicyBusy || edgeLandingCheck == null) return;
            try {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Policies\Microsoft\Edge")) {
                    string value = key == null ? "" : Convert.ToString(key.GetValue("ProxySettings", ""));
                    edgeLandingCheck.Checked = value == "{\"ProxyMode\":\"fixed_servers\",\"ProxyServer\":\"http://127.0.0.1:18484\",\"ProxyBypassList\":\"<-loopback>\"}";
                    edgePolicyLabel.Text = edgeLandingCheck.Checked
                        ? "已配置；首次需重开 Edge，再检查出口"
                        : "未启用；沿用 Edge 原代理设置";
                    edgePolicyLabel.ForeColor = Gray;
                }
            } catch { edgePolicyLabel.Text = "无法读取 Edge 设置"; edgePolicyLabel.ForeColor = Orange; }
        }

        private async Task SetEdgePolicyAsync(bool enable)
        {
            edgePolicyBusy = true;
            edgeLandingCheck.Enabled = false;
            edgePolicyLabel.Text = "正在应用；如 Windows 提示，请完成管理员授权…";
            try {
                await Task.Run(delegate { RunHiddenChecked("powershell.exe",
                    "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + Path.Combine(RouterDir, "Configure-Edge-Landing.ps1") + "\" -Action " + (enable ? "Enable" : "Restore") + " -AllowElevation", 150000); });
                MessageBox.Show(enable
                    ? "已为日常 Edge 配置落地代理，包括默认浏览器打开的链接。\n请保存网页工作，完整退出并重开 Edge，然后点击“检查 Edge 出口”。\n落地服务停止时，Edge 会断网；取消勾选可恢复原代理。"
                    : "已恢复 Edge 原来的代理及隐私策略。请完整退出并重开 Edge。",
                    "Edge 设置", MessageBoxButtons.OK, MessageBoxIcon.Information);
            } catch (Exception ex) { MessageBox.Show(ex.Message, "Edge 设置未完成", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
            finally { edgePolicyBusy = false; edgeLandingCheck.Enabled = true; RefreshEdgePolicy(); }
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
                hasExitTest = false;

                if (mode == "off")
                {
                    RunCleanup();
                    resultLabel.ForeColor = Green;
                    resultLabel.Text = "落地服务已停止；上游保持运行，固定落地的 Claude 将断网。";
                }
                else
                {
                    if ((previousMode == "off" || previousMode == "apps") && mode != "apps") SaveProxyState();
                    if (mode == "apps" && previousMode != "apps") RestoreSavedProxy();
                    File.WriteAllText(ModeFile, mode);
                    if (previousMode == "foreign" || previousMode == "global" || previousMode == "apps")
                        RunRestart();
                    else
                        RunStart();
                    resultLabel.ForeColor = Orange;
                    resultLabel.Text = mode == "apps"
                        ? "系统代理保持不变；Claude 使用独立设置，Edge 可用下方开关接入。"
                        : "正在通过所选上游验证落地出口……";
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
                    resultLabel.Text = "落地转发当前已关闭，无需重新连接。";
                    return;
                }

                hasExitTest = false;
                RunRestart();
                resultLabel.ForeColor = Orange;
                resultLabel.Text = "正在重连所选链路；仅应用模式保持系统代理不变。";
                RefreshStatus();
            }
            catch (Exception ex)
            {
                resultLabel.ForeColor = Red;
                resultLabel.Text = "重连失败：" + ex.Message;
            }
        }

        private async Task ApplyRouteAsync(string script, string arguments)
        {
            if (routeBusy) return;
            routeBusy = true;
            hasExitTest = false;
            SetRouteControls(false);
            resultLabel.ForeColor = Orange;
            resultLabel.Text = "正在应用并检测所选链路……";
            try
            {
                await Task.Run(delegate { RunHiddenChecked("powershell.exe",
                    "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + script + "\" " + arguments); });
                if (ReadMode() == "off") resultLabel.Text = "选择已保存；启用转发模式后连接。";
                else await TestExitAsync();
            }
            catch (Exception ex)
            {
                resultLabel.ForeColor = Red;
                resultLabel.Text = ex.Message;
            }
            finally
            {
                routeBusy = false;
                SetRouteControls(true);
                upstreamChoiceBox.SelectedIndex = UpstreamChoiceIndex(ReadUpstreamChoice());
                landingChoiceBox.SelectedIndex = ReadLandingChoice() == "nas04" ? 1 : 0;
                RefreshStatus();
            }
        }

        private void SetRouteControls(bool enabled)
        {
            foreach (Control control in new Control[] {applyClashButton, applyUpstreamButton,
                applyLandingButton, clashEndpointBox, upstreamChoiceBox, landingChoiceBox,
                offButton, foreignButton, globalButton, appsButton, reconnectButton,
                testButton, refreshStatusButton}) control.Enabled = enabled;
        }

        private static string ReadLandingChoice()
        {
            try { if (File.ReadAllText(LandingChoiceFile).Trim() == "nas04") return "nas04"; }
            catch { }
            return "germany";
        }

        private static bool MatchesLanding(string ip, string choice)
        {
            return choice == "nas04" ? ip == "212.121.132.230"
                : ip == "192.248.188.234" || ip == "2a05:f480:1800:2d04:5400:5ff:fe92:1848";
        }

        private bool ExitResultIsFresh()
        {
            return hasExitTest && lastExitChoice == ReadLandingChoice()
                && lastTestRoute == ReadUpstreamChoice() + "|" + ReadClashEndpoint() + "|" + ReadMode()
                && (DateTime.Now - lastExitTestAt).TotalSeconds < 60;
        }

        private static int UpstreamChoiceIndex(string choice)
        {
            if (choice == "wanda") return 1;
            return 0;
        }

        private static string UpstreamChoiceFromIndex(int index)
        {
            if (index == 1) return "wanda";
            return "clash";
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
            if (!System.Text.RegularExpressions.Regex.IsMatch(parts[0], @"^[a-zA-Z0-9.-]+$"))
                throw new InvalidOperationException("接口主机名无效");
            return parts[0] + ":" + port;
        }

        private async Task TestExitAsync()
        {
            testButton.Enabled = false;
            refreshStatusButton.Enabled = false;
            hasExitTest = false;
            string testedChoice = ReadLandingChoice();
            string testedRoute = ReadUpstreamChoice() + "|" + ReadClashEndpoint() + "|" + ReadMode();
            resultLabel.ForeColor = Gray;
            resultLabel.Text = "正在检测出口……";

            try
            {
                string mode = ReadMode();
                if (mode != "off" && !IsListening(18484))
                    throw new InvalidOperationException("落地转发未连接，请点击“重新连接”。");

                string baseEndpoint = ReadUpstreamChoice() == "wanda" ? "127.0.0.1:7892" : ReadClashEndpoint();
                bool wandaAvailable = IsListening(ParseEndpointPort(baseEndpoint));
                string proxy;
                string url;
                if (mode == "off")
                {
                    proxy = wandaAvailable ? "http://" + baseEndpoint : null;
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
                    hasExitTest = true;
                    lastExitMatches = false;
                    resultLabel.ForeColor = Blue;
                    resultLabel.Text = wandaAvailable
                        ? "上游当前出口：" + value
                        : "本地网络：" + value;
                }
                else
                {
                    bool isGermany = MatchesLanding(value, testedChoice);
                    hasExitTest = true;
                    lastExitMatches = isGermany;
                    string expected = isGermany ? (testedChoice == "nas04" ? "NAS04 出口通过" : "原德国出口通过") : "与所选出口不符";
                    resultLabel.ForeColor = isGermany ? Green : Red;
                    resultLabel.Text = "公网 IP：" + value + "    判定：" + expected;
                }
            }
            catch (Exception ex)
            {
                resultLabel.ForeColor = Red;
                hasExitTest = true;
                lastExitMatches = false;
                resultLabel.Text = "检测失败：" + ex.Message;
            }
            finally
            {
                lastExitChoice = testedChoice;
                lastTestRoute = testedRoute;
                lastExitTestAt = DateTime.Now;
                testButton.Enabled = !routeBusy;
                refreshStatusButton.Enabled = !routeBusy;
                RefreshStatus();
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
            RefreshEdgePolicy();
            string mode = ReadMode();
            string upstreamChoice = ReadUpstreamChoice();
            bool upstreamListening = upstreamChoice == "wanda"
                    ? IsListening(7892)
                    : IsListening(ParseEndpointPort(ReadClashEndpoint()));
            bool port18484 = IsListening(18484);

            SetUpstreamStatus(mode, upstreamListening);
            SetLandingStatus(mode, port18484);
            SetStatus(routerStatus, "● 分流入口 18484", port18484);

            modeValue.Text = "当前模式：" + ModeDisplay(mode);
            if (trayStatusItem != null)
                trayStatusItem.Text = "当前模式：" + ModeDisplay(mode);
            if (trayIcon != null)
                trayIcon.Text = "德国代理切换器 - " + ModeDisplay(mode);
            string proxy = GetSystemProxy();
            systemProxyValue.Text = "系统代理：" + (string.IsNullOrEmpty(proxy) ? "未启用" : proxy);
            systemProxyValue.ForeColor = Gray;
            if (mode == "apps" && proxy.Contains(":18484")) {
                systemProxyValue.Text = "冲突：系统也走落地，影响其他应用";
                systemProxyValue.ForeColor = Red;
            }

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
            string choice = ReadUpstreamChoice();
            string label = choice == "wanda"
                    ? "● WandaCloud 7892"
                    : "● Clash 接口 " + endpoint;
            if (mode == "off")
            {
                SetStatus(wandaStatus, label, clashListening);
                return;
            }
            if (!clashListening)
            {
                wandaStatus.Text = label + "  未连接";
                wandaStatus.ForeColor = Red;
                return;
            }
            if (ExitResultIsFresh())
            {
                wandaStatus.Text = label + (lastExitMatches ? "  链路检测通过" : "  链路检测失败");
                wandaStatus.ForeColor = lastExitMatches ? Green : Red;
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
                    wandaStatus.Text = label + "  接口正常，链路待检测";
                    wandaStatus.ForeColor = Orange;
                }
                else if (active == "Clash-Upstream")
                {
                    wandaStatus.Text = label;
                    wandaStatus.ForeColor = value.Contains("state=healthy") || value.Contains("state=manual") ? Green : Orange;
                }
                else if (active == "Wanda-Upstream")
                {
                    wandaStatus.Text = "● 兼容接口 WandaCloud 7892";
                    wandaStatus.ForeColor = value.Contains("state=manual") ? Green : Orange;
                }
                else
                {
                    wandaStatus.Text = label + "  验证中";
                    wandaStatus.ForeColor = Orange;
                }
            }
            catch
            {
                wandaStatus.Text = label + "  状态未知";
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
                string endpoint = NormalizeEndpoint(value);
                if (IsListening(ParseEndpointPort(endpoint))) return endpoint;
                foreach (string candidate in new[] { "127.0.0.1:7890", "127.0.0.1:7980", "127.0.0.1:7897", "127.0.0.1:7891" })
                    if (IsListening(ParseEndpointPort(candidate))) return candidate;
                return endpoint;
            }
            catch
            {
                foreach (string candidate in new[] { "127.0.0.1:7890", "127.0.0.1:7980", "127.0.0.1:7897", "127.0.0.1:7891" })
                    if (IsListening(ParseEndpointPort(candidate))) return candidate;
                return "127.0.0.1:7890";
            }
        }

        private static string ReadUpstreamChoice()
        {
            try
            {
                string value = File.ReadAllText(UpstreamChoiceFile).Trim().ToLowerInvariant();
                if (value == "clash" || value == "wanda") return value;
            }
            catch { }
            return "clash";
        }

        private void SetLandingStatus(string mode, bool routerListening)
        {
            string choice = ReadLandingChoice();
            string label = choice == "nas04" ? "● NAS04 212.121.132.230" : "● 德国 192.248.188.234";
            string state = "待检测";
            Color color = Orange;
            if (mode == "off") { state = "待命"; color = Gray; }
            else if (!routerListening) { state = "未连接"; color = Red; }
            else if (ExitResultIsFresh()) {
                state = lastExitMatches ? "出口检测通过" : "出口检测失败";
                color = lastExitMatches ? Green : Red;
            }
            else {
                try {
                    FileInfo file = new FileInfo(RouteHealthFile);
                    string value = file.Exists ? File.ReadAllText(RouteHealthFile) : "";
                    string expected = choice == "nas04" ? "212.121.132.230" : "192.248.188.234";
                    bool matches = value.Contains("exit=" + expected) || (choice == "germany" && value.Contains("exit=2a05:f480:1800:2d04:5400:5ff:fe92:1848"));
                    if (file.Exists && (DateTime.Now - file.LastWriteTime).TotalSeconds <= 60 && matches && value.Contains("state=healthy")) {
                        state = "出口健康"; color = Green;
                    }
                } catch { }
            }
            tunnelStatus.Text = label + "  " + state;
            tunnelStatus.ForeColor = color;
            if (mode != "off") {
                FileInfo heartbeat = new FileInfo(Path.Combine(RouterDir, "supervisor-heartbeat.txt"));
                if (!heartbeat.Exists || (DateTime.Now - heartbeat.LastWriteTime).TotalSeconds > 90) {
                    tunnelStatus.Text = label + "  监督已停止/失联，请重新连接";
                    tunnelStatus.ForeColor = Orange;
                }
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
            if (mode == "foreign") return "仅非中国走落地";
            if (mode == "global") return "全局走落地";
            if (mode == "apps") return "仅指定应用（不自动接管）";
            return "关闭落地转发";
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

        private static void SaveProxyState()
        {
            if (File.Exists(ProxyBackupFile)) return;
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(InternetSettings))
            {
                if (key == null) return;
                File.WriteAllLines(ProxyBackupFile, new[] {
                    "ProxyEnable=" + Convert.ToInt32(key.GetValue("ProxyEnable", 0)),
                    "ProxyServer=" + Convert.ToString(key.GetValue("ProxyServer", "")),
                    "ProxyOverride=" + Convert.ToString(key.GetValue("ProxyOverride", ""))
                });
            }
        }

        private static void RestoreSavedProxy()
        {
            if (!File.Exists(ProxyBackupFile)) return;
            var values = File.ReadAllLines(ProxyBackupFile).ToDictionary(
                line => line.Split(new[] { '=' }, 2)[0],
                line => line.Contains("=") ? line.Substring(line.IndexOf('=') + 1) : "");
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(InternetSettings, true))
            {
                if (key == null) return;
                int enabled;
                if (!Int32.TryParse(values.ContainsKey("ProxyEnable") ? values["ProxyEnable"] : "0", out enabled)) enabled = 0;
                key.SetValue("ProxyEnable", enabled, RegistryValueKind.DWord);
                key.SetValue("ProxyServer", values.ContainsKey("ProxyServer") ? values["ProxyServer"] : "", RegistryValueKind.String);
                key.SetValue("ProxyOverride", values.ContainsKey("ProxyOverride") ? values["ProxyOverride"] : "", RegistryValueKind.String);
            }
            InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0);
            InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0);
            File.Delete(ProxyBackupFile);
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

        private static void RunHiddenChecked(string file, string arguments, int timeoutMs = 90000)
        {
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = file;
            info.Arguments = arguments;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardError = true;
            Process process = Process.Start(info);
            Task<string> errorRead = process.StandardError.ReadToEndAsync();
            if (!process.WaitForExit(timeoutMs))
                throw new InvalidOperationException("操作超时");
            if (process.ExitCode != 0)
                throw new InvalidOperationException("应用失败：" + errorRead.Result.Trim());
        }

        [DllImport("wininet.dll", SetLastError = true)]
        private static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int length);
    }
}
