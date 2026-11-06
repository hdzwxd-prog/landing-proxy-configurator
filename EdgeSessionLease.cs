using System;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;
using System.Web.Script.Serialization;

namespace GermanyProxyManager {
    // Owns an IPC session, never an OS/browser registry setting.
    internal sealed class EdgeSessionLease : IDisposable {
        internal static string PipeName {
            get { return "LandingEdgeSession-" + WindowsIdentity.GetCurrent().User.Value; }
        }
        readonly object gate = new object();
        readonly ManualResetEvent ended = new ManualResetEvent(false);
        readonly string name;
        NamedPipeServerStream pipe;
        int version;
        bool desired;
        DateTime ackTime;
        int ackVersion = -1;
        bool applied;
        string error = "";
        internal EdgeSessionLease(string testName = null) {
            name = testName ?? PipeName;
            new Thread(Serve) { IsBackground = true }.Start();
        }
        internal void SetEnabled(bool value) {
            lock (gate) { if (desired != value) { desired = value; version++; ackVersion = -1; } }
        }
        internal bool Desired { get { lock(gate) return desired; } }
        internal bool Accepted {
            get { lock(gate) return ackVersion == version && applied == desired &&
                error == "" && (DateTime.UtcNow - ackTime).TotalSeconds < 7; }
        }
        internal string Status {
            get { lock(gate) {
                if (error != "") return "Edge 接入失败：" + error;
                if (Accepted) return desired ? "浏览器已接受落地设置；出口未实测" : "浏览器已撤销本软件的代理设置";
                return desired ? "等待 Edge 扩展确认；尚未接入" : "未接管；等待 Edge 扩展连接";
            }}
        }
        void Serve() {
            while (!ended.WaitOne(0)) {
                try {
                    var security = new PipeSecurity();
                    security.SetAccessRuleProtection(true, false);
                    security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User,
                        PipeAccessRights.FullControl, AccessControlType.Allow));
                    using (var current = new NamedPipeServerStream(name, PipeDirection.InOut, 1,
                        PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 4096, 4096, security)) {
                        lock(gate) pipe = current;
                        var pending = current.BeginWaitForConnection(null, null);
                        if (WaitHandle.WaitAny(new[] {pending.AsyncWaitHandle, ended}) != 0) return;
                        current.EndWaitForConnection(pending);
                        using(var reader = new StreamReader(current))
                        using(var writer = new StreamWriter(current) {AutoFlush = true}) {
                            var read = reader.ReadLineAsync();
                            while (!ended.WaitOne(0) && current.IsConnected) {
                                bool want; int seq;
                                lock(gate) { want = desired; seq = version; }
                                writer.WriteLine("{\"protocol\":1,\"enabled\":" +
                                    (want ? "true" : "false") + ",\"version\":" + seq + "}");
                                if (read.Wait(500)) {
                                    var line = read.Result;
                                    if (line == null) break;
                                    if (line.Length > 4096) throw new IOException("Oversized acknowledgement");
                                    var ack = new JavaScriptSerializer().Deserialize<Acknowledgement>(line);
                                    lock(gate) {
                                        // Ignore responses to an older requested setting.
                                        if (ack.version == version) {
                                            ackVersion = ack.version; applied = ack.applied;
                                            error = ack.error ?? ""; ackTime = DateTime.UtcNow;
                                        }
                                    }
                                    read = reader.ReadLineAsync();
                                }
                                if (ended.WaitOne(1000)) break;
                            }
                        }
                    }
                } catch { if (ended.WaitOne(250)) break; }
                finally { lock(gate) { pipe = null; ackVersion = -1; error = ""; } }
            }
        }
        internal sealed class Acknowledgement {
            public int version {get;set;}
            public bool applied {get;set;}
            public string error {get;set;}
        }
        public void Dispose() {
            SetEnabled(false);
            ended.Set(); // broken pipe also revokes the extension lease after a crash
            lock(gate) { if(pipe != null) pipe.Dispose(); }
        }
    }
}
