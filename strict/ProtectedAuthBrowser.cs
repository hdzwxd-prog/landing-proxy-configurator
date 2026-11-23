using System;
using System.Diagnostics;
using System.IO;
using System.Web;
using System.Web.Script.Serialization;
using System.Windows.Forms;

// BROWSER command used only by Claude. Never falls back to the Windows default browser.
internal static class ProtectedAuthBrowser {
    internal static string Prepare(string input) {
        Uri uri;
        if (!Uri.TryCreate(input, UriKind.Absolute, out uri) || uri.Scheme != "https" || !string.IsNullOrEmpty(uri.UserInfo) || uri.Port != 443)
            throw new InvalidOperationException("Login URL rejected.");
        if (uri.Host != "claude.ai" && uri.Host != "claude.com" && uri.Host != "platform.claude.com" && uri.Host != "console.anthropic.com")
            throw new InvalidOperationException("Login host rejected.");
        var query = HttpUtility.ParseQueryString(uri.Query);
        Uri redirect;
        if (query["redirect_uri"] != null && Uri.TryCreate(query["redirect_uri"], UriKind.Absolute, out redirect) && redirect.IsLoopback) {
            // Current CLI accepts the pasted code with this official manual redirect.
            if (redirect.Scheme != "http" || redirect.AbsolutePath != "/callback")
                throw new InvalidOperationException("Unknown callback format; login blocked.");
            query["redirect_uri"] = "https://platform.claude.com/oauth/code/callback";
            var builder = new UriBuilder(uri); builder.Query = query.ToString();
            return builder.Uri.AbsoluteUri;
        }
        return uri.AbsoluteUri;
    }
    [STAThread] static int Main(string[] args) {
        try {
            if(args.Length != 1) throw new InvalidOperationException("Expected one login URL.");
            string url = args[0] == "--probe" ? "https://api.ipify.org/?protected_login_probe=1" : Prepare(args[0]);
            string exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Mozilla Firefox\firefox.exe");
            if(!File.Exists(exe)) throw new InvalidOperationException("Protected Firefox is missing.");
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), @".ssh\GermanyRouter\StrictGermany");
            var check = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(root,"Test-LoginPrerequisites.ps1") + "\"");
            check.UseShellExecute=false; check.CreateNoWindow=true;
            check.RedirectStandardOutput=true; check.RedirectStandardError=true;
            using(var process=Process.Start(check)) {
                if(!process.WaitForExit(35000)) { process.Kill(); throw new InvalidOperationException("Check timed out"); }
                if(process.ExitCode!=0) throw new InvalidOperationException("Login prerequisites failed");
            }
            var info = new ProcessStartInfo(exe, "-new-tab \"" + url.Replace("\"", "%22") + "\"");
            info.UseShellExecute = false;
            Process.Start(info);
            return 0;
        } catch {
            // Never print the URL: OAuth state and challenge are confidential.
            MessageBox.Show("受保护的授权页未打开。请检查德国通道和 Firefox；不要改用普通浏览器登录。", "Claude 登录保护");
            return 1;
        }
    }
}
