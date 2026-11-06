import {test} from "node:test";
import assert from "node:assert/strict";
import {LeaseController} from "../edge-extension/controller.mjs";
function harness() {
  let own, privacy, conflict = false;
  const calls = [], replies = [];
  const api = {runtime: {lastError: null}, proxy: {settings: {
    get(_args, cb) {cb({levelOfControl: conflict ? "not_controllable" :
      own ? "controlled_by_this_extension" : "controllable_by_this_extension",
      value: own || {mode: "system"}});},
    set(args, cb) {own=args.value; calls.push(["set",args]);cb();},
    clear(args, cb) {own=undefined;calls.push(["clear",args]);cb();}
  }}, privacy: {network: {webRTCIPHandlingPolicy: {
    set(args, cb) {privacy=args.value;cb();},
    clear(_args, cb) {privacy=undefined;cb();}
  }}}};
  return {controller: new LeaseController(api, m=>replies.push(m)), calls, replies,
    get own(){return own;}, get privacy(){return privacy;},
    conflict(){conflict=true;}};
}
test("no service / cold startup clears only this extension's overrides", async()=>{
  const h=harness();await h.controller.reset();
  assert.equal(h.own,undefined);assert.equal(h.calls.some(c=>c[0]==="set"),false);
});
test("enable accepts only fixed local landing; exit restores ownership by clear",async()=>{
  const h=harness();
  await h.controller.receive({protocol:1,enabled:true,version:1});
  assert.equal(h.own.rules.singleProxy.port,18484);
  assert.equal(h.privacy,"disable_non_proxied_udp");
  assert.equal(h.replies.at(-1).applied,true);
  await h.controller.receive({protocol:1,enabled:false,version:2});
  assert.equal(h.own,undefined);assert.equal(h.privacy,undefined);
  assert.equal(h.calls.some(c=>c[0]==="set"&&["direct","system"].includes(c[1].value.mode)),false);
});
test("GUI/native host disconnect revokes a live route, not just a UI flag",async()=>{
  const h=harness();await h.controller.receive({protocol:1,enabled:true,version:3});
  await h.controller.reset();
  assert.equal(h.own,undefined);
});
test("crash during queued enable cannot apply stale enable after disconnect",async()=>{
  const h=harness();
  const enable=h.controller.receive({protocol:1,enabled:true,version:1});
  const reset=h.controller.reset();await Promise.all([enable,reset]);
  assert.equal(h.own,undefined);
});
test("heartbeat expiry revokes; a live but unhealthy proxy is not silently changed",async()=>{
  const h=harness();await h.controller.receive({protocol:1,enabled:true,version:1});
  await h.controller.expire(h.controller.lastBeat+9999);
  assert.equal(h.own.rules.singleProxy.port,18484);
  await h.controller.expire(h.controller.lastBeat+10001);
  assert.equal(h.own,undefined);
});
test("another policy's ownership is not overwritten or reported as success",async()=>{
  const h=harness();h.conflict();
  await h.controller.receive({protocol:1,enabled:true,version:1});
  assert.equal(h.own,undefined);assert.equal(h.replies.at(-1).applied,false);
  assert.ok(h.replies.at(-1).error);
});
test("rapid on/off/on ends at the latest selection",async()=>{
  const h=harness();
  await Promise.all([true,false,true].map((enabled,version)=>
    h.controller.receive({protocol:1,enabled,version})));
  assert.equal(h.own.rules.singleProxy.port,18484);
  assert.equal(h.replies.at(-1).version,2);
});
