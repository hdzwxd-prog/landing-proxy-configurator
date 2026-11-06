using System;
using System.IO;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using System.Threading;

internal static class NativeHost {
    static readonly object outputGate = new object(), pipeGate = new object();
    static Stream output;
    static StreamWriter pipeWriter;
    static bool ReadExact(Stream s, byte[] b) {
        int n=0; while(n<b.Length) {int got=s.Read(b,n,b.Length-n); if(got==0)return false;n+=got;} return true;
    }
    static void Send(string json) {
        byte[] b=Encoding.UTF8.GetBytes(json);
        lock(outputGate) {output.Write(BitConverter.GetBytes(b.Length),0,4);output.Write(b,0,b.Length);output.Flush();}
    }
    static void ReadBrowser() {
        try {
            var input=Console.OpenStandardInput();
            for(;;) {
                var prefix=new byte[4]; if(!ReadExact(input,prefix))break;
                int count=BitConverter.ToInt32(prefix,0); if(count<1||count>4096)break;
                var b=new byte[count];if(!ReadExact(input,b))break;
                string line=Encoding.UTF8.GetString(b);
                if(line.IndexOfAny(new[]{'\r','\n'})>=0)break;
                lock(pipeGate) {if(pipeWriter!=null)pipeWriter.WriteLine(line);}
            }
        } catch {}
        Environment.Exit(0); // browser closed: do not leave an orphan host
    }
    static void Main() {
        output=Console.OpenStandardOutput();
        new Thread(ReadBrowser){IsBackground=true}.Start();
        string name="LandingEdgeSession-"+WindowsIdentity.GetCurrent().User.Value;
        bool disabledSent=false;
        for(;;) {
            try {
                if(!disabledSent){Send("{\"protocol\":1,\"enabled\":false,\"version\":0}");disabledSent=true;}
                using(var pipe=new NamedPipeClientStream(".",name,PipeDirection.InOut)) {
                    pipe.Connect(1000);
                    using(var reader=new StreamReader(pipe))
                    using(var writer=new StreamWriter(pipe){AutoFlush=true}) {
                        lock(pipeGate)pipeWriter=writer;
                        string line;
                        while((line=reader.ReadLine())!=null) {
                            if(line.Length>4096)throw new IOException("Oversized lease");
                            Send(line);disabledSent=false;
                        }
                    }
                }
            } catch(TimeoutException) {Thread.Sleep(1000);}
              catch(IOException) {Thread.Sleep(100);}
              catch {return;}
            finally {lock(pipeGate)pipeWriter=null;}
        }
    }
}
