// Scans saved in this browser (IndexedDB). Nothing is uploaded anywhere: the site is static
// files and has no server behind it.
//
// Browsers can clear site data they consider unused (Safari does after a few weeks without a
// visit), so the pages tell people to download any PDF they want to keep.
const LocalScans = (() => {
  const DB_NAME = 'doc-scanner';
  const STORE = 'scans';

  function openDb() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = () => {
        request.result.createObjectStore(STORE, { keyPath: 'id' });
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // Runs `work(store)` in one transaction and resolves with its request's result.
  async function run(mode, work) {
    const db = await openDb();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, mode);
      const request = work(tx.objectStore(STORE));
      tx.oncomplete = () => {
        db.close();
        resolve(request ? request.result : undefined);
      };
      tx.onerror = () => {
        db.close();
        reject(tx.error);
      };
      tx.onabort = () => {
        db.close();
        reject(tx.error || new Error('The browser refused to save (storage may be full).'));
      };
    });
  }

  function newId() {
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  }

  return {
    // Newest first.
    async list() {
      const all = await run('readonly', (store) => store.getAll());
      return all.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
    },

    get(id) {
      return run('readonly', (store) => store.get(id));
    },

    async save(title, pageCount, blob) {
      const scan = {
        id: newId(),
        title,
        pageCount,
        pdfSize: blob.size,
        createdAt: new Date().toISOString(),
        blob,
      };
      await run('readwrite', (store) => store.put(scan));
      // Ask the browser not to evict this site's storage when space runs low.
      if (navigator.storage && navigator.storage.persist) {
        navigator.storage.persist().catch(() => {});
      }
      return scan;
    },

    remove(id) {
      return run('readwrite', (store) => store.delete(id));
    },
  };
})();
