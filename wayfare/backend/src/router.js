/**
 * A tiny router: exact-segment matching with ":param" placeholders.
 * Returns 404 for unknown paths and 405-as-bad_request is not needed by the
 * contract, so an unknown method on a known path is also a 404 not_found.
 */
export class Router {
  constructor() {
    this.routes = [];
  }

  add(method, pattern, handler, { auth = true } = {}) {
    this.routes.push({ method, parts: pattern.split('/').filter(Boolean), handler, auth });
    return this;
  }

  /** Finds the route for method + pathname. Returns { route, params } or null. */
  match(method, pathname) {
    const segs = pathname.split('/').filter(Boolean);
    for (const route of this.routes) {
      if (route.method !== method || route.parts.length !== segs.length) continue;
      const params = {};
      let ok = true;
      for (let i = 0; i < segs.length; i++) {
        const p = route.parts[i];
        if (p.startsWith(':')) {
          let v;
          try {
            v = decodeURIComponent(segs[i]);
          } catch {
            ok = false;
            break;
          }
          params[p.slice(1)] = v;
        } else if (p !== segs[i]) {
          ok = false;
          break;
        }
      }
      if (ok) return { route, params };
    }
    return null;
  }
}
