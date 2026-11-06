using System;
using System.IO;
using System.IO.Pipes;
using System.Threading;
using GermanyProxyManager;
class EdgeLeaseTest {
    static void Assert(bool ok,string why){if(!ok)throw new Exception(why);}
    static void Main() {
        string name="LandingEdgeTest-"+Guid.NewGuid().ToString("N");
        using(var server=new EdgeSessionLease(name))
        using(var client=new NamedPipeClientStream(".",name,PipeDirection.InOut)) {
            client.Connect(5000);
            var reader=new StreamReader(client);
            var writer=new StreamWriter(client){AutoFlush=true};
            Assert(reader.ReadLine().Contains("\"enabled\":false"),"Fresh session must be disabled");
            server.SetEnabled(true);
            string line;do{line=reader.ReadLine();}while(!line.Contains("\"enabled\":true"));
            writer.WriteLine("{\"version\":1,\"applied\":true,\"error\":\"\"}");
            for(int i=0;i<30&&!server.Accepted;i++)Thread.Sleep(100);
            Assert(server.Accepted,"Browser ACK must reach server");
            server.SetEnabled(false);
            Assert(!server.Accepted,"Previous ACK must not validate a new selection");
            server.Dispose();
            // Pipe teardown is the crash/exit notification. No production ports or browser used.
            bool closed=false;
            try{while(reader.ReadLine()!=null){}closed=true;}catch(IOException){closed=true;}
            Assert(closed,"Lease teardown must close the pipe");
        }
        Console.WriteLine("PASS: disabled startup, lease apply ACK, stale ACK rejection, pipe disconnect");
    }
}
