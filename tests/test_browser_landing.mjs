// Isolated, signed-out Edge profiles only. Never attaches to a user's browser.
import {spawn} from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import dgram from 'node:dgram';
import assert from 'node:assert/strict';
const edge = path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe');
const reportPath = process.argv[2];
const policyMode = process.argv.includes('--policy');
const delay = ms => new Promise(r=>setTimeout(r,ms));
let udpPackets=0;
const stun=dgram.createSocket('udp4');
stun.on('message',(msg,rinfo)=>{
  if(msg.length<20 || msg.readUInt16BE(0)!==1) return;
  udpPackets++;
  const response=Buffer.alloc(32);response.writeUInt16BE(0x101);response.writeUInt16BE(12,2);
  msg.copy(response,4,4,20);response.writeUInt16BE(0x20,20);response.writeUInt16BE(8,22);
  response[25]=1;response.writeUInt16BE(rinfo.port^0x2112,26);
  // Synthetic test address, not a real internet STUN service or the user's IP.
  [203,0,113,7].forEach((b,i)=>response[28+i]=b^msg[4+i]);
  stun.send(response,rinfo.port,rinfo.address);
});
await new Promise(r=>stun.bind(0,'127.0.0.1',r));
const stunPort=stun.address().port;
async function run(hardened,proxyPort) {
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'landing-browser-test-'));
  if(hardened && !policyMode) {
    await fs.mkdir(path.join(dir,'Default'));
    await fs.writeFile(path.join(dir,'Default','Preferences'),JSON.stringify({webrtc:{ip_handling_policy:'disable_non_proxied_udp'}}));
  }
  const args=['--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking',
    '--remote-debugging-port=0',`--user-data-dir=${dir}`,'about:blank'];
  if(!policyMode) {
    args.push(`--proxy-server=http://127.0.0.1:${proxyPort}`,'--proxy-bypass-list=<-loopback>','--disable-quic');
    if(hardened)args.push('--force-webrtc-ip-handling-policy=disable_non_proxied_udp');
  }
  const proc=spawn(edge,args,{windowsHide:true,stdio:'ignore'});
  let ws;let id=0;const waiting=new Map();
  function call(method,params={}) {
    return new Promise((resolve,reject)=>{
      const key=++id;const timer=setTimeout(()=>{waiting.delete(key);reject(Error('CDP timeout: '+method))},20000);
      waiting.set(key,{resolve:v=>{clearTimeout(timer);resolve(v)},reject:e=>{clearTimeout(timer);reject(e)}});
      ws.send(JSON.stringify({id:key,method,params}));
    });
  }
  try {
    let port;
    for(let i=0;i<80;i++) {try{port=Number((await fs.readFile(path.join(dir,'DevToolsActivePort'),'utf8')).split('\n')[0]);break}catch{await delay(250)}}
    assert(port,'No isolated test browser port');
    const tabs=await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    ws=new WebSocket(tabs.find(t=>t.type==='page').webSocketDebuggerUrl);
    await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
    ws.onmessage=e=>{const m=JSON.parse(e.data);const p=waiting.get(m.id);if(p){waiting.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result)}};
    const nav=await call('Page.navigate',{url:'https://api.ipify.org'});
    let ip='';
    if(!nav.errorText)for(let i=0;i<50;i++){
      ip=(await call('Runtime.evaluate',{expression:'document.body ? document.body.innerText.trim() : ""',returnByValue:true})).result.value;
      if(/^\d+\.\d+\.\d+\.\d+$/.test(ip))break;await delay(200);
    }
    const before=udpPackets;
    const rtc=(await call('Runtime.evaluate',{expression:`new Promise(async resolve => {
      const candidates=[];const pc=new RTCPeerConnection({iceServers:[{urls:'stun:127.0.0.1:${stunPort}'}]});
      pc.createDataChannel('probe');pc.onicecandidate=e=>{if(e.candidate)candidates.push(e.candidate.candidate)};
      await pc.setLocalDescription(await pc.createOffer());
      setTimeout(()=>{pc.close();resolve(candidates)},3500);
    })`,awaitPromise:true,returnByValue:true})).result.value;
    return {configuration:policyMode?'Windows Edge policy only':'isolated profile and command line',hardened,proxyPort:policyMode?null:proxyPort,ip,networkError:nav.errorText??null,stunPackets:udpPackets-before,candidates:rtc};
  } finally {
    if(ws) {try{await call('Browser.close')}catch{}ws.close()}
    for(let i=0;i<30&&proc.exitCode===null;i++)await delay(100);
    if(proc.exitCode===null)proc.kill();
    // Leave the small signed-out temp profile if Windows has not released it.
    const resolved=path.resolve(dir),tempRoot=path.resolve(os.tmpdir());
    assert(path.dirname(resolved)===tempRoot && path.basename(resolved).startsWith('landing-browser-test-'));
    await fs.rm(resolved,{recursive:true,force:true,maxRetries:3}).catch(()=>{});
  }
}
const report={};
try {
  if(!policyMode)report.control=await run(false,18484);
  report.protected=await run(true,18484);
  if(!policyMode)report.unreachable=await run(true,9);
  if(!policyMode)assert(report.control.stunPackets>0,'Local STUN control did not run');
  assert(report.protected.stunPackets===0,'WebRTC bypassed proxy');
  assert(report.protected.candidates.length===0,'WebRTC exposed a candidate');
  assert(['212.121.132.230','192.248.188.234'].includes(report.protected.ip),'Unexpected landing exit');
  if(!policyMode)assert(report.unreachable.networkError==='net::ERR_PROXY_CONNECTION_FAILED','Browser fell back or negative check inconclusive');
  report.passed=true;
} finally {
  stun.close();
  if(reportPath)await fs.writeFile(reportPath,JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
}
