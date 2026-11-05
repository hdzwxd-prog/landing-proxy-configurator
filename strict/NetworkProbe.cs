using System;
using System.Net;
using System.Net.Sockets;
class NetworkProbe {
    static void Test(string address,int port,bool udp) {
        IPAddress ip=IPAddress.Parse(address);
        using(var s=new Socket(ip.AddressFamily,udp?SocketType.Dgram:SocketType.Stream,udp?ProtocolType.Udp:ProtocolType.Tcp)) {
            try {
                s.SendTimeout=2000;
                if(udp)s.SendTo(new byte[]{0},new IPEndPoint(ip,port));
                else {var a=s.BeginConnect(ip,port,null,null);if(!a.AsyncWaitHandle.WaitOne(2500)){Console.WriteLine(address+":"+port+" TIMEOUT");return;}s.EndConnect(a);}
                Console.WriteLine((udp?"UDP ":"TCP ")+address+":"+port+" ALLOWED");
            }catch(SocketException e){Console.WriteLine((udp?"UDP ":"TCP ")+address+":"+port+" ERROR "+e.ErrorCode);}
        }
    }
    static void Main(string[] args){int port=args.Length==1?Int32.Parse(args[0]):18485;Test("127.0.0.1",port,false);if(port!=18485)Test("127.0.0.1",18485,false);Test("127.0.0.1",7892,false);Test("127.0.0.1",7980,false);Test("127.0.0.1",18484,false);Test("1.1.1.1",443,false);Test("::1",port,false);Test("2606:4700:4700::1111",443,false);Test("127.0.0.1",port,true);Test("1.1.1.1",53,true);}
}
