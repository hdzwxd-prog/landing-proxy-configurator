import {LeaseController} from "./controller.mjs";
let port;
let connecting = false;
const controller = new LeaseController(chrome, message => {
  try { port?.postMessage(message); } catch {}
  chrome.action.setBadgeText({text: message.error ? "!" : message.applied ? "ON" : ""});
  chrome.action.setTitle({title: message.error ||
    (message.applied ? "Edge 已接受落地设置；实际出口须另行验证" : "本扩展未接管代理")});
});
function report(error) {
  chrome.action.setBadgeText({text: "!"});
  chrome.action.setTitle({title: "撤销/接入未完成：" + error.message});
}
async function connect() {
  if (port || connecting) return;
  connecting = true;
  try {
    await controller.reset(); // cold worker / browser startup never trusts a saved enable state
    const connection = chrome.runtime.connectNative("local.landing_proxy.session");
    port = connection;
    connection.onMessage.addListener(message => {
      if (port === connection) controller.receive(message).catch(report);
    });
    connection.onDisconnect.addListener(() => {
      void chrome.runtime.lastError;
      if (port !== connection) return;
      port = undefined;
      controller.reset().catch(report);
      chrome.action.setBadgeText({text: ""});
    });
  } catch (e) { await controller.reset(); report(e); }
  finally { connecting = false; }
}
chrome.runtime.onStartup.addListener(() => { connect().catch(report); });
chrome.runtime.onInstalled.addListener(() => { connect().catch(report); });
chrome.action.onClicked.addListener(() => { connect().catch(report); });
// Local watchdog, not model automation. Alarms can be delayed by sleep/browser shutdown.
chrome.alarms.create("landing-lease", {periodInMinutes: 0.5});
chrome.alarms.onAlarm.addListener(() => {
  controller.expire().catch(report);
  if (!port) connect().catch(report);
});
connect().catch(report);
