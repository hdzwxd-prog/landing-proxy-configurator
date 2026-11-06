using System;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;

namespace GermanyProxyManager {
    // Local automation uses the same handler as the checkbox. No TCP endpoint.
    internal sealed class EdgeSessionControl : IDisposable {
        readonly Func<string,string> handle;
        readonly ManualResetEvent ended = new ManualResetEvent(false);
        NamedPipeServerStream current;
        internal EdgeSessionControl(Func<string,string> handler) {
            handle=handler;
            new Thread(Serve){IsBackground=true}.Start();
        }
        void Serve() {
            while(!ended.WaitOne(0)) try {
                var security=new PipeSecurity();
                security.SetAccessRuleProtection(true,false);
                security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User,
                    PipeAccessRights.FullControl,AccessControlType.Allow));
                using(var pipe=new NamedPipeServerStream("LandingEdgeControl-"+WindowsIdentity.GetCurrent().User.Value,
                    PipeDirection.InOut,1,PipeTransmissionMode.Byte,PipeOptions.Asynchronous,1024,4096,security)) {
                    current=pipe;
                    var connection=pipe.BeginWaitForConnection(null,null);
                    if(WaitHandle.WaitAny(new[]{connection.AsyncWaitHandle,ended})!=0)return;
                    pipe.EndWaitForConnection(connection);
                    using(var reader=new StreamReader(pipe))
                    using(var writer=new StreamWriter(pipe){AutoFlush=true}) {
                        // Fixed-size commands, bounded read; no arbitrary file paths or script execution.
                        var chars=new char[16];int length=0;bool complete=false;
                        while(length<chars.Length) {
                            var read=reader.ReadAsync(chars,length,1);
                            if(!read.Wait(2000)||read.Result==0)break;
                            if(chars[length]=='\n'){complete=true;break;}length++;
                        }
                        if(complete)writer.WriteLine(handle(new string(chars,0,length).Trim()));
                    }
                }
            } catch {if(ended.WaitOne(100))break;}
        }
        public void Dispose(){ended.Set();try{if(current!=null)current.Dispose();}catch{}}
    }
}
