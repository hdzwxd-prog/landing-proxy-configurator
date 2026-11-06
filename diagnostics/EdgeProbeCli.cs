using System;
using System.Text;
using System.Web.Script.Serialization;
using GermanyProxyManager;

// Opens one IP-check tab in ordinary Edge. The HTTP request originates in Edge,
// not this process. No browser debugging, account access, or proxy modification.
internal static class EdgeProbeCli {
    [STAThread]
    static int Main() {
        Console.OutputEncoding=new UTF8Encoding(false);
        var json=new JavaScriptSerializer();
        try {
            Console.WriteLine(json.Serialize(new {ok=true,ip=EdgeExitProbe.Run()}));return 0;
        } catch(Exception ex) {
            Console.WriteLine(json.Serialize(new {ok=false,error=ex.Message}));return 1;
        }
    }
}
