const docs = require(process.argv[2]); const T = require('fs').readFileSync(process.argv[3], 'utf8').trim();
const B = 'https://api.favcircles.com/api/widgets/data/';
(async () => {
  for (const [id, d] of Object.entries(docs)) {
    const g = await fetch(B + id, { headers: { Authorization: `Bearer ${T}` } });
    const cur = g.ok ? await g.json() : null;
    const version = cur?.document?.version ?? cur?.version ?? 0;
    const r = await fetch(B + id, { method: 'PUT', headers: { Authorization: `Bearer ${T}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ version, payload: d.payload, schemaVersion: d.schemaVersion }) });
    console.log(id, g.status, version, r.status, r.ok ? '' : (await r.text()).slice(0, 200));
  }
})();
