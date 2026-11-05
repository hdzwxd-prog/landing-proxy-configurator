using System;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace GermanyProxyManager
{
    internal sealed partial class MainForm
    {
        private static readonly string StrictDir = Path.Combine(RouterDir, "StrictGermany");
        private ComboBox strictChoice;
        private Label strictStatus;
        private bool strictBusy;
        private DateTime strictVerifiedUntil;
        private DateTime strictRecoveryAfter;
        private void BuildStrictPanel()
        {
            if (!File.Exists(Path.Combine(StrictDir, "isolation-install.json"))) return;
            foreach (Control control in Controls) if (control.Top >= 310) control.Top += 176;
            Panel card = CreateCard(new Point(28, 310), new Size(1044, 158));
            Controls.Add(card);
            card.Controls.Add(CreateSectionTitle("Firefox / Claude · 德国强制通道", new Point(24, 12)));
            strictChoice = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Location = new Point(24, 54), Size = new Size(245, 38) };
            strictChoice.Items.Add("Clash（使用下方接口）"); strictChoice.Items.Add("Wanda · 127.0.0.1:7892");
            strictChoice.SelectedIndex = ReadStrictChoice() == "wanda" ? 1 : 0;
            card.Controls.Add(strictChoice);
            var apply = new Button { Text = "应用通道 / 重连", Location = new Point(287, 50), Size = new Size(190, 42) };
            var stop = new Button { Text = "停止强制通道", Location = new Point(493, 50), Size = new Size(170, 42) };
            var firefox = new Button { Text = "打开 Firefox", Location = new Point(679, 50), Size = new Size(160, 42) };
            var verify = new Button { Text = "检测德国出口", Location = new Point(855, 50), Size = new Size(163, 42) };
            foreach (Button b in new[] {apply, stop, firefox, verify}) { StyleActionButton(b, Blue, Color.White); card.Controls.Add(b); }
            strictStatus = new Label { Location = new Point(24, 104), Size = new Size(995, 46), ForeColor = Orange, Font = new Font("Microsoft YaHei UI", 16F, FontStyle.Regular, GraphicsUnit.Pixel) };
            card.Controls.Add(strictStatus);
            apply.Click += async delegate {
                string choice = strictChoice.SelectedIndex == 1 ? "wanda" : "clash";
                try { await RunStrictAction("Set-StrictUpstream.ps1", "-Choice " + choice + " -Endpoint \"" + NormalizeEndpoint(clashEndpointBox.Text) + "\"", true); }
                catch (Exception ex) { strictStatus.Text = ex.Message; strictStatus.ForeColor = Red; }
            };
            stop.Click += async delegate { await RunStrictAction("Set-StrictUpstream.ps1", "-Stop", false); };
            firefox.Click += async delegate { await RunStrictAction("Start-StrictApp.ps1", "-App Firefox -NoDialog", false); };
            verify.Click += async delegate { await RunStrictAction("Start-StrictGermany.ps1", "-CheckOnly", true); };
            RefreshStrictPanel();
            Shown += async delegate {
                try {
                    if (!IsListening(18485) && File.ReadAllText(Path.Combine(StrictDir,"enabled.txt")).Trim() == "true")
                        await RunStrictAction("Start-StrictGermany.ps1", "", true);
                } catch { }
            };
        }
        private static string ReadStrictChoice()
        {
            try { return File.ReadAllText(Path.Combine(StrictDir,"upstream-choice.txt")).Trim(); } catch { return "clash"; }
        }
        private async Task RunStrictAction(string script, string args, bool verifies)
        {
            if (strictBusy) return;
            strictBusy = true; strictVerifiedUntil = DateTime.MinValue;
            strictChoice.Enabled = false; strictStatus.Text = "正在操作德国强制通道；不会修改系统代理或普通落地入口。"; strictStatus.ForeColor = Orange;
            try {
                await Task.Run(delegate { RunHiddenChecked("powershell.exe", "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + Path.Combine(StrictDir,script) + "\" " + args); });
                if (verifies) strictVerifiedUntil = DateTime.Now.AddMinutes(1);
                strictStatus.Text = IsListening(18485) ? (verifies ? "德国出口检测通过 · 192.248.188.234（或该主机 IPv6）。应用连接另行核对。" : "德国强制通道已启动；Firefox / Claude 不使用下方可变落地。") : "强制通道已停止。Firefox / Claude 保持阻断，不回退普通代理。";
                strictStatus.ForeColor = verifies ? Green : Orange;
            } catch (Exception ex) { strictStatus.Text = "强制通道未通过：" + ex.Message; strictStatus.ForeColor = Red; }
            finally { strictBusy = false; strictChoice.Enabled = true; strictChoice.SelectedIndex = ReadStrictChoice() == "wanda" ? 1 : 0; }
        }
        private void RefreshStrictPanel()
        {
            if (strictStatus == null || strictBusy) return;
            if (!IsListening(18485)) {
                strictStatus.Text = "德国强制通道未运行。Firefox / Claude 保持阻断；选通道后点“应用通道 / 重连”。"; strictStatus.ForeColor = Red;
                try {
                    if (IsHandleCreated && !allowExit && DateTime.Now > strictRecoveryAfter && File.ReadAllText(Path.Combine(StrictDir,"enabled.txt")).Trim() == "true") {
                        strictRecoveryAfter = DateTime.Now.AddSeconds(20);
                        BeginInvoke(new Action(async delegate { if (!strictBusy && !allowExit) await RunStrictAction("Start-StrictGermany.ps1", "", true); }));
                    }
                } catch { }
            }
            else if (strictVerifiedUntil != DateTime.MinValue && DateTime.Now > strictVerifiedUntil) { strictStatus.Text = "德国入口正在监听，出口检测已过期。固定德国、不回退；需要时点击检测。"; strictStatus.ForeColor = Orange; strictVerifiedUntil = DateTime.MinValue; }
            else if (String.IsNullOrEmpty(strictStatus.Text)) strictStatus.Text = "独立入口 18485 正在监听，尚未检测出口。下方普通落地设置不作用于 Firefox / Claude。";
        }
    }
}
