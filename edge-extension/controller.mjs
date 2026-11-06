// No fetch, URLs, account access, system proxy writes, or saved enable flag.
export class LeaseController {
  constructor(api, reply) {
    this.api = api;
    this.reply = reply;
    this.queue = Promise.resolve();
    this.epoch = 0;
    this.lastBeat = 0;
    this.applied = null;
  }
  call(setting, method, args) {
    return new Promise((resolve, reject) => setting[method](args, value => {
      const error = this.api.runtime.lastError;
      error ? reject(new Error(error.message)) : resolve(value);
    }));
  }
  enqueue(action) {
    this.queue = this.queue.catch(() => {}).then(action);
    return this.queue;
  }
  async clear() {
    // clear ONLY this extension's overrides; never set system/direct/another upstream.
    // Clear proxy even if restoring privacy fails.
    const errors = [];
    for (const setting of [this.api.proxy.settings,
      this.api.privacy.network.webRTCIPHandlingPolicy]) {
      try { await this.call(setting, "clear", {scope: "regular"}); }
      catch (e) { errors.push(e.message); }
    }
    this.applied = null;
    if (errors.length) throw new Error(errors.join("; "));
  }
  reset() {
    ++this.epoch;
    this.lastBeat = 0;
    return this.enqueue(() => this.clear());
  }
  receive(message) {
    if (message.protocol !== 1 || typeof message.enabled !== "boolean" ||
        !Number.isSafeInteger(message.version)) return this.reset();
    this.lastBeat = Date.now();
    const epoch = this.epoch;
    return this.enqueue(async () => {
      if (epoch !== this.epoch) return;
      try {
        if (message.enabled) {
          const current = await this.call(this.api.proxy.settings, "get", {incognito: false});
          if (!["controllable_by_this_extension", "controlled_by_this_extension"].includes(current.levelOfControl))
            throw new Error("Edge 代理被策略或其他扩展控制");
          if (!current.value || current.value.mode !== "fixed_servers" ||
              current.value.rules?.singleProxy?.port !== 18484 ||
              current.levelOfControl !== "controlled_by_this_extension") {
            await this.call(this.api.privacy.network.webRTCIPHandlingPolicy, "set",
              {scope: "regular", value: "disable_non_proxied_udp"});
            await this.call(this.api.proxy.settings, "set", {scope: "regular",
              value: {mode: "fixed_servers", rules: {
                singleProxy: {scheme: "http", host: "127.0.0.1", port: 18484},
                bypassList: ["<-loopback>"]
              }}});
          }
          const after = await this.call(this.api.proxy.settings, "get", {incognito: false});
          if (after.levelOfControl !== "controlled_by_this_extension" ||
              after.value?.rules?.singleProxy?.host !== "127.0.0.1" ||
              after.value?.rules?.singleProxy?.port !== 18484)
            throw new Error("Edge 未接受本扩展代理设置");
        } else if (this.applied !== false) {
          await this.clear();
        }
        if (epoch !== this.epoch) return; // queued reset clears any interrupted apply
        this.applied = message.enabled;
        this.reply({version: message.version, applied: message.enabled, error: ""});
      } catch (e) {
        // An enabled route with a conflict is NOT reported as successfully protected.
        try { await this.clear(); } catch (cleanupError) { e = new Error(e.message + "; " + cleanupError.message); }
        this.reply({version: message.version, applied: false, error: e.message});
      }
    });
  }
  expire(now = Date.now()) {
    if (this.lastBeat && now - this.lastBeat > 10000) return this.reset();
    return Promise.resolve();
  }
}
