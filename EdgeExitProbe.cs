using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace GermanyProxyManager
{
    internal static class EdgeExitProbe
    {
        // A nonce ties the result to this tab. Only the browser fetches the public IP.
        internal static string Run()
        {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            try {
                string path = "/" + Guid.NewGuid().ToString("N");
                string url = "http://127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port + path;
                string edge = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                    @"Microsoft\Edge\Application\msedge.exe");
                Process.Start(edge, url);
                var time = Stopwatch.StartNew();
                while (time.Elapsed.TotalSeconds < 35) {
                    if (!listener.Pending()) { Thread.Sleep(60); continue; }
                    using (var client = listener.AcceptTcpClient()) {
                        client.ReceiveTimeout = 1000;
                        client.SendTimeout = 1000;
                        try {
                            var stream = client.GetStream();
                            var header = new StringBuilder();
                            int ch;
                            while (header.Length < 8192 && (ch = stream.ReadByte()) >= 0) {
                                header.Append((char)ch);
                                int n = header.Length;
                                if (n >= 4 && header[n-1]=='\n' && header[n-2]=='\r' && header[n-3]=='\n' && header[n-4]=='\r') break;
                            }
                            string[] request = header.ToString().Split(' ');
                            if (request.Length < 3 || request[0] != "GET") continue;
                            if (request[1] == path) {
                                Reply(stream, "200 OK", @"<!doctype html><meta charset=utf-8><meta name=referrer content=no-referrer><title>正在打开 IP.SB</title>
<style>body{font:18px system-ui;max-width:720px;margin:70px auto;padding:24px;color:#183153}a{color:#2271db}</style>
<h2>正在核对 Edge 出口，随后打开 IP.SB</h2>
<p>你可以在 IP.SB 查看当前出口的国家、地区和运营商。</p>
<p>如果没有自动跳转，<a href='https://ip.sb/' rel=noreferrer>直接打开 IP.SB</a>。</p>
<script>(async()=>{for(const host of ['api.ipify.org','api64.ipify.org']){try{
const r=await fetch('https://'+host+'/?format=json&probe='+location.pathname.slice(1),{cache:'no-store',credentials:'omit',signal:AbortSignal.timeout(8000)});
if(!r.ok)continue;const ip=(await r.json()).ip;
const ack=await fetch(location.pathname+'/ip/'+encodeURIComponent(ip),{cache:'no-store',signal:AbortSignal.timeout(2000)});
if(!ack.ok)continue;await ack.text();location.replace('https://ip.sb/');return;
}catch(e){}}
try{await fetch(location.pathname+'/error',{cache:'no-store',signal:AbortSignal.timeout(2000)});}catch(e){}
location.replace('https://ip.sb/');})();</script>");
                            } else if (request[1].StartsWith(path+"/ip/",StringComparison.Ordinal)) {
                                IPAddress ip;
                                if (IPAddress.TryParse(Uri.UnescapeDataString(request[1].Substring(path.Length+4)),out ip)) {
                                    Reply(stream,"200 OK","OK");
                                    return ip.ToString();
                                }
                            } else if (request[1] == path+"/error") {
                                Reply(stream,"200 OK","OK");
                                throw new InvalidOperationException("自动核对未取得出口；已打开 IP.SB，请查看网页结果。");
                            } else Reply(stream,"404 Not Found","");
                        } catch (IOException) { }
                    }
                }
                throw new TimeoutException("日常 Edge 未返回出口。请检查浏览器检测页，重开 Edge 后再检查。");
            } finally { listener.Stop(); }
        }

        private static void Reply(NetworkStream stream,string status,string html)
        {
            byte[] body=Encoding.UTF8.GetBytes(html);
            byte[] head=Encoding.ASCII.GetBytes("HTTP/1.1 "+status+"\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+body.Length+"\r\n\r\n");
            stream.Write(head,0,head.Length);
            stream.Write(body,0,body.Length);
        }
    }
}
