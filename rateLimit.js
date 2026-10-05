// A small in-memory sliding-window limiter. Fine for a single instance (the free Render plan);
// it resets on restart, which is acceptable for protecting an email-sending endpoint.
const windows = new Map();

/// Returns true (and records the hit) if `key` has made fewer than `limit` calls in the last `windowMs`.
export function allow(key, limit, windowMs) {
  const now = Date.now();
  const recent = (windows.get(key) || []).filter((t) => now - t < windowMs);
  if (recent.length >= limit) {
    windows.set(key, recent);
    return false;
  }
  recent.push(now);
  windows.set(key, recent);
  return true;
}

// Drop keys that have gone quiet so the map can't grow forever.
setInterval(() => {
  const cutoff = Date.now() - 60 * 60 * 1000;
  for (const [key, times] of windows) {
    if (times.every((t) => t < cutoff)) windows.delete(key);
  }
}, 10 * 60 * 1000).unref();
