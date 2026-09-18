// A small in-memory Firestore stand-in: enough for single-collection document
// CRUD, compare-and-set transactions, and the equality/range queries the
// postcard order machine runs. Deliberately not general — it exists so money
// transitions can be tested for real instead of being mocked away.
class FakeQuery {
  constructor(store, filters = [], order = null, max = null) {
    this.store = store;
    this.filters = filters;
    this.order = order;
    this.max = max;
  }
  where(field, op, value) { return new FakeQuery(this.store, [...this.filters, { field, op, value }], this.order, this.max); }
  orderBy(field, direction = 'asc') { return new FakeQuery(this.store, this.filters, { field, direction }, this.max); }
  limit(n) { return new FakeQuery(this.store, this.filters, this.order, n); }
  // Real queries use select() to fetch ids without the document bodies. The
  // fake always returns whole docs, so this is just a pass-through that keeps
  // the call chain working.
  select() { return this; }

  async get() {
    let rows = [...this.store.docs.entries()].map(([id, data]) => ({ id, data }));
    for (const f of this.filters) {
      rows = rows.filter(({ data }) => {
        const v = data[f.field];
        switch (f.op) {
          case '==': return v === f.value;
          case '<=': return v !== null && v !== undefined && v <= f.value;
          case '>=': return v !== null && v !== undefined && v >= f.value;
          case 'in': return Array.isArray(f.value) && f.value.includes(v);
          case '!=': return v !== f.value;
          case 'array-contains': return Array.isArray(v) && v.includes(f.value);
          case 'array-contains-any':
            return Array.isArray(v) && Array.isArray(f.value) && f.value.some(x => v.includes(x));
          default: throw new Error(`FakeQuery: unsupported operator ${f.op}`);
        }
      });
    }
    if (this.order) {
      const { field, direction } = this.order;
      rows.sort((a, b) => (a.data[field] > b.data[field] ? 1 : -1) * (direction === 'desc' ? -1 : 1));
    }
    if (this.max !== null) rows = rows.slice(0, this.max);
    const docs = rows.map(({ id, data }) => this.store.snapshot(id, data));
    return { docs, empty: docs.length === 0, size: docs.length, forEach: (fn) => docs.forEach(fn) };
  }
}

class FakeCollection {
  constructor(store) { this.store = store; }
  add(data) {
    const id = `auto_${++this.store.autoId}`;
    this.store.docs.set(id, { ...data });
    return Promise.resolve(this.store.ref(id));
  }
  doc(id) { return this.store.ref(id); }
  where(...args) { return new FakeQuery(this.store).where(...args); }
  orderBy(...args) { return new FakeQuery(this.store).orderBy(...args); }
  limit(n) { return new FakeQuery(this.store).limit(n); }
}

class FakeFirestore {
  constructor({ namespaced = false } = {}) {
    this.docs = new Map();
    this.collections = new Map();
    this.autoId = 0;
    // namespaced: each collection gets its own doc map (multi-collection
    // services). Default keeps the original single-map behaviour, where
    // db.docs is inspected directly by the postcard tests.
    this.namespaced = namespaced;
  }

  collection(name) {
    if (!this.collections.has(name)) {
      const store = this.namespaced ? new FakeFirestore() : this;
      this.collections.set(name, new FakeCollection(store));
    }
    return this.collections.get(name);
  }

  // namespaced only: the backing map for one collection.
  rows(name) { return this.collection(name).store.docs; }

  snapshot(id, data) {
    const store = this;
    return {
      id,
      exists: data !== undefined,
      data: () => (data === undefined ? undefined : { ...data }),
      ref: store.ref(id)
    };
  }

  ref(id) {
    const store = this;
    return {
      id,
      store,
      async get() { return store.snapshot(id, store.docs.get(id)); },
      async set(data) { store.docs.set(id, { ...data }); },
      async create(data) {
        if (store.docs.has(id)) throw new Error('ALREADY_EXISTS');
        store.docs.set(id, { ...data });
      },
      async update(patch) {
        const current = store.docs.get(id);
        if (!current) throw new Error('NOT_FOUND');
        store.docs.set(id, applyPatch(current, patch));
      }
    };
  }

  /**
   * Runs the body once. Real Firestore retries on contention; tests drive
   * conflicts deterministically instead, by mutating between calls.
   */
  async runTransaction(body) {
    const fallback = this;
    const writes = [];
    const storeOf = (ref) => ref.store || fallback;
    const tx = {
      async get(ref) { return storeOf(ref).snapshot(ref.id, storeOf(ref).docs.get(ref.id)); },
      update(ref, patch) { writes.push([ref, patch]); },
      set(ref, data) { writes.push([ref, data]); }
    };
    const result = await body(tx);
    for (const [ref, patch] of writes) {
      const store = storeOf(ref);
      store.docs.set(ref.id, applyPatch(store.docs.get(ref.id) || {}, patch));
    }
    return result;
  }
}

// Mirrors FieldValue.increment, the only sentinel the order machine uses.
function applyPatch(current, patch) {
  const next = { ...current };
  for (const [key, value] of Object.entries(patch)) {
    if (value && typeof value === 'object' && value.__increment !== undefined) {
      next[key] = (next[key] || 0) + value.__increment;
    } else {
      next[key] = value;
    }
  }
  return next;
}

const FakeFieldValue = { increment: (n) => ({ __increment: n }) };

module.exports = { FakeFirestore, FakeFieldValue };
