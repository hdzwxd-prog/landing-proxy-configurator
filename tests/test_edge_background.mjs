import test from 'node:test';
import assert from 'node:assert/strict';

test('overlapping startup events create one native host', async () => {
  const event = () => ({listeners:[], addListener(fn){this.listeners.push(fn);}});
  const setting = () => ({clear(_arg, cb){setTimeout(cb, 5);}});
  const connections=[];
  globalThis.chrome={
    proxy:{settings:setting()}, privacy:{network:{webRTCIPHandlingPolicy:setting()}},
    runtime:{onStartup:event(), onInstalled:event(), connectNative(){
      const connection={onMessage:event(),onDisconnect:event(),postMessage(){}};
      connections.push(connection);return connection;
    }},
    action:{onClicked:event(),setBadgeText(){},setTitle(){}},
    alarms:{onAlarm:event(),create(){}}
  };
  await import('../edge-extension/background.js');
  chrome.runtime.onStartup.listeners.forEach(fn=>fn());
  chrome.runtime.onInstalled.listeners.forEach(fn=>fn());
  chrome.action.onClicked.listeners.forEach(fn=>fn());
  await new Promise(resolve=>setTimeout(resolve,100));
  assert.equal(connections.length,1);
  connections[0].onDisconnect.listeners.forEach(fn=>fn());
  chrome.alarms.onAlarm.listeners.forEach(fn=>fn());
  chrome.action.onClicked.listeners.forEach(fn=>fn());
  await new Promise(resolve=>setTimeout(resolve,100));
  assert.equal(connections.length,2);
  delete globalThis.chrome;
});
