'use strict';

/**
 * Simple in-memory cache with TTL support.
 */
class gCache {
  constructor(ttlMs) {
    this._ttl = ttlMs || 5 * 60 * 1000; // default 5 minutes
    this._store = new Map();
  }

  get(key) {
    const entry = this._store.get(key);
    if (!entry) return null;
    if (Date.now() > entry.expires) {
      this._store.delete(key);
      return null;
    }
    return entry.value;
  }

  set(key, value) {
    this._store.set(key, {
      value,
      expires: Date.now() + this._ttl,
    });
    // Periodic cleanup: remove expired entries when map gets large
    if (this._store.size > 200) this._cleanup();
  }

  has(key) {
    return this.get(key) !== null;
  }

  _cleanup() {
    const now = Date.now();
    for (const [k, v] of this._store) {
      if (now > v.expires) this._store.delete(k);
    }
  }
}

module.exports = gCache;
