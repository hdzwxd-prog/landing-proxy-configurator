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
        private Label strictStatus;
        private Label appRoutes;
        private bool strictBusy;
        private DateTime strictVerifiedUntil;
        private DateTime strictRecoveryAfter;
        private bool HasStrict { get { return File.Exists(Path.Combine(StrictDir, "isolation-install.json")); } }

        private void BuildStrictPanel()
        {
            // Application rules share the upstream selector and the apply/reconnect lifecycle.
            // The separate core is an implementation detail needed for the Germany-only rule.
            foreach (Control control in Controls) if (control.Top >= 500) control.Top += 190;
            Panel card = CreateCard(new Point(28, 490), new Size(1044, 180));
            Controls.Add(card);
            card.Controls.Add(CreateSectionTitle("应用规则 · 当前实际配置", new Point(24, 10)));
            appRoutes = new Label { Location = new Point(24, 46), Size = new Size(995, 84), ForeColor = Navy,
                Font = new Font("Microsoft YaHei UI", 16F, FontStyle.Regular, GraphicsUnit.Pixel) };
            strictStatus = new Label { Location = new Point(24, 132), Size = new Size(995, 44), ForeColor = Orange,
                Font = new Font("Microsoft YaHei UI", 15F, FontStyle.Regular, GraphicsUnit.Pixel) };
            card.Controls.Add(appRoutes); card.Controls.Add(strictStatus);
            RefreshStrictPanel();
        }
        private static string ReadStrictChoice()
        {
            try { return File.ReadAllText(Path.Combine(StrictDir,"upstream-choice.txt")).Trim(); } catch { return "unknown"; }
        }
        private static string UpstreamName(string choice)
        {
            return choice == "wanda" ? "Wanda :7892" : choice == "clash" ? "Clash" : "未知（待检查）";
        }
        private async Task ApplyIntegratedAsync()
        {
            if (routeBusy || strictBusy) return;
            if (ReadMode() == "off") { resultLabel.Text = "请先选择转发模式，再应用统一配置。"; resultLabel.ForeColor = Orange; return; }
            try {
                string endpoint = NormalizeEndpoint(clashEndpointBox.Text);
                string choice = UpstreamChoiceFromIndex(upstreamChoiceBox.SelectedIndex);
                string landing = landingChoiceBox.SelectedIndex == 1 ? "nas04" : "germany";
                if (!IsListening(18484)) {
                    routeBusy = true; SetRouteControls(false);
                    try {
                        await Task.Run(delegate { RunHiddenChecked("powershell.exe",
                            "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + RestartScript + "\""); });
                    } catch {
                        // Recovery can start the core while the old route is unhealthy.
                        // In that case the user's newly selected pair is still allowed to be tested.
                        if (!IsListening(18484)) throw;
                    } finally { routeBusy = false; SetRouteControls(true); }
                }
                strictVerifiedUntil = DateTime.MinValue;
                await ApplyRouteAsync(Path.Combine(RouterDir,"Set-IntegratedRoute.ps1"),
                    "-Choice " + choice + " -Endpoint \"" + endpoint + "\" -Landing " + landing);
                // Never turn an operation's failure into green based only on a listening socket.
                RefreshStrictPanel();
            } catch (Exception ex) { resultLabel.Text = ex.Message; resultLabel.ForeColor = Red; }
        }
        private async Task TestAllExitsAsync()
        {
            if (routeBusy || strictBusy) return;
            routeBusy = true;
            SetRouteControls(false);
            try {
                await TestExitAsync();
                if (HasStrict) await RunStrictAction("Start-StrictGermany.ps1", "-CheckOnly", true);
            } finally { routeBusy = false; SetRouteControls(true); RefreshStrictPanel(); }
        }
        private async Task RunStrictAction(string script, string args, bool verifies)
        {
            if (strictBusy || !HasStrict) return;
            strictBusy = true; strictVerifiedUntil = DateTime.MinValue;
            SetRouteControls(false);
            strictStatus.Text = "正在检查德国应用规则对应的服务；不启动应用、不访问 Claude。";
            strictStatus.ForeColor = Orange;
            try {
                await Task.Run(delegate { RunHiddenChecked("powershell.exe", "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + Path.Combine(StrictDir,script) + "\" " + args); });
                if (verifies) strictVerifiedUntil = DateTime.Now.AddMinutes(1);
                strictStatus.Text = "德国服务出口已核实 · 192.248.188.234 / 该主机 IPv6；应用接入未由此验证。";
                strictStatus.ForeColor = Green;
            } catch (Exception ex) { strictStatus.Text = "德国服务检测未通过：" + ex.Message; strictStatus.ForeColor = Red; }
            finally { strictBusy = false; SetRouteControls(!routeBusy); }
        }
        private void RefreshStrictPanel()
        {
            if (strictStatus == null || strictBusy || routeBusy) return;
            string regular = UpstreamName(ReadUpstreamChoice());
            string protectedUpstream = UpstreamName(ReadStrictChoice());
            appRoutes.Text = "Firefox / Claude 桌面 → " + protectedUpstream + " → 德国固定出口；失败断网\n"
                + "Edge → " + (edgeLandingCheck.Checked ? regular + " → " + (ReadLandingChoice() == "nas04" ? "NAS04" : "德国") + "（浏览器实际出口须另查）" : "原代理；本程序未接管") + "\n"
                + "Claude Code：代理设置不等于完整隔离；原生引擎及其子进程尚未全部验收。";
            if (!HasStrict) { strictStatus.Text = "Firefox / Claude 的系统隔离尚未安装，不能视为已受保护。"; strictStatus.ForeColor = Red; return; }
            if (!IsListening(18485)) {
                strictStatus.Text = "德国应用服务未运行，保持网络限制。启用模式后点“应用全部设置 / 重新连接”。";
                strictStatus.ForeColor = Red;
                try {
                    if (IsHandleCreated && !allowExit && ReadMode() != "off" && DateTime.Now > strictRecoveryAfter && File.ReadAllText(Path.Combine(StrictDir,"enabled.txt")).Trim() == "true") {
                        strictRecoveryAfter = DateTime.Now.AddSeconds(20);
                        BeginInvoke(new Action(async delegate { if (!strictBusy && !routeBusy && !allowExit) await RunStrictAction("Start-StrictGermany.ps1", "", true); }));
                    }
                } catch { }
            }
            else if (ReadStrictChoice() != ReadUpstreamChoice()) {
                strictStatus.Text = "旧配置的上游不一致：请在上方选定上游并应用全部设置。当前连接未自动切换。";
                strictStatus.ForeColor = Orange;
            }
            else if (DateTime.Now > strictVerifiedUntil) {
                strictStatus.Text = "德国服务正在监听，出口尚未检测或结果已过期。点“检测出口”检查两条应用路线。";
                strictStatus.ForeColor = Orange;
            }
        }
    }
}
