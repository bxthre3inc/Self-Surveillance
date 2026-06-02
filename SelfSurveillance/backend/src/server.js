'use strict';

// ─── Self-Surveillance Backend ────────────────────────────────────────────────
//
// HTTP + WebSocket server that:
//   POST /api/ingest          — receives NDJSON batches from the iOS SyncEngine
//   GET  /api/logs            — paginated log query (source / category / date / search)
//   GET  /api/logs/summary    — aggregate counts by source and category
//   GET  /api/devices         — list of known devices
//   WS   /live                — pushes every new LogEntry to connected Android clients
//   WS   /screen/publish      — iOS ScreenStreamManager pushes JPEG frames here
//   WS   /screen/watch        — Android ScreenMirrorViewModel receives JPEG frames here
//
// Data storage: NDJSON files on disk under ./data/logs/<deviceID>/<YYYY-MM-DD>/<source>.ndjson
// Each line is one LogEntry JSON object, exactly as the iOS app produces it.

const express = require('express');
const http    = require('http');
const fs      = require('fs');
const path    = require('path');
const busboy  = require('busboy');
const { WebSocketServer } = require('ws');
const cors    = require('cors');

// ─── Config ───────────────────────────────────────────────────────────────────

const PORT     = process.env.PORT   || 3000;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data', 'logs');
fs.mkdirSync(DATA_DIR, { recursive: true });

// ─── App setup ────────────────────────────────────────────────────────────────

const app    = express();
const server = http.createServer(app);

app.use(cors());
app.use(express.json({ limit: '50mb' }));

// ─── In-memory state ──────────────────────────────────────────────────────────

// Subscribers waiting for live log events (Set of WebSocket connections)
const liveSubscribers = new Set();

// Subscribers waiting for screen frames (Set of WebSocket connections)
const screenWatchers = new Set();

// Quick device registry: deviceID → { deviceName, iOSVersion, lastSeen, count }
const deviceRegistry = {};

// ─── Helper: write one entry to disk ──────────────────────────────────────────

function persistEntry(entry) {
    const deviceID = entry.deviceID || 'unknown';
    const date     = (entry.timestamp || new Date().toISOString()).slice(0, 10);
    const source   = entry.source    || 'unknown';

    const dir  = path.join(DATA_DIR, deviceID, date);
    fs.mkdirSync(dir, { recursive: true });

    const file = path.join(dir, `${source}.ndjson`);
    fs.appendFileSync(file, JSON.stringify(entry) + '\n');
}

// ─── Helper: broadcast a LogEntry to all live subscribers ────────────────────

function broadcastLive(entry) {
    const text = JSON.stringify(entry);
    for (const ws of liveSubscribers) {
        if (ws.readyState === ws.OPEN) {
            ws.send(text);
        }
    }
}

// ─── POST /api/ingest ─────────────────────────────────────────────────────────
// Accepts the multipart/form-data payload that SyncEngine sends.
// Parts: "manifest" (JSON) + "batch" (NDJSON file).

app.post('/api/ingest', (req, res) => {
    const bb = busboy({ headers: req.headers, limits: { fileSize: 50 * 1024 * 1024 } });
    let manifest = null;
    let ndjsonLines = '';

    bb.on('field', (name, val) => {
        if (name === 'manifest') {
            try { manifest = JSON.parse(val); } catch (_) {}
        }
    });

    bb.on('file', (_name, stream) => {
        const chunks = [];
        stream.on('data', chunk => chunks.push(chunk));
        stream.on('end',  ()    => { ndjsonLines += Buffer.concat(chunks).toString('utf8'); });
    });

    bb.on('finish', () => {
        const lines = ndjsonLines.split('\n').filter(l => l.trim());
        let accepted = 0;

        for (const line of lines) {
            try {
                const entry = JSON.parse(line);

                // Update device registry
                const id = entry.deviceID;
                if (id) {
                    if (!deviceRegistry[id]) {
                        deviceRegistry[id] = { deviceID: id, deviceName: entry.deviceName || id,
                                               iOSVersion: entry.iOSVersion || '', lastSeen: '',
                                               entryCount: 0 };
                    }
                    deviceRegistry[id].lastSeen   = entry.timestamp || new Date().toISOString();
                    deviceRegistry[id].deviceName = entry.deviceName || id;
                    deviceRegistry[id].entryCount += 1;
                }

                persistEntry(entry);
                broadcastLive(entry);
                accepted++;
            } catch (e) {
                // Skip malformed lines
            }
        }

        res.json({ batchID: manifest?.batchID ?? 'unknown', accepted });
    });

    req.pipe(bb);
});

// ─── GET /api/logs ────────────────────────────────────────────────────────────
// Query params: source, category, deviceID, date, search, limit (default 100), offset (default 0)

app.get('/api/logs', (req, res) => {
    const { source, category, deviceID, date, search,
            limit = '100', offset = '0' } = req.query;
    const lim = Math.min(parseInt(limit), 1000);
    const off = parseInt(offset);

    const results = [];
    const devIDs  = deviceID
        ? [deviceID]
        : fs.existsSync(DATA_DIR) ? fs.readdirSync(DATA_DIR).filter(d =>
            fs.statSync(path.join(DATA_DIR, d)).isDirectory()) : [];

    outer: for (const devID of devIDs) {
        const devPath = path.join(DATA_DIR, devID);
        const dates   = date
            ? [date]
            : (fs.existsSync(devPath) ? fs.readdirSync(devPath) : []).sort().reverse();

        for (const d of dates) {
            const dayPath = path.join(devPath, d);
            if (!fs.existsSync(dayPath)) continue;

            const files = source
                ? [`${source}.ndjson`]
                : fs.readdirSync(dayPath).filter(f => f.endsWith('.ndjson'));

            for (const file of files) {
                const filepath = path.join(dayPath, file);
                if (!fs.existsSync(filepath)) continue;

                const lines = fs.readFileSync(filepath, 'utf8')
                    .split('\n').filter(l => l.trim()).reverse();

                for (const line of lines) {
                    try {
                        const entry = JSON.parse(line);
                        if (category && entry.category !== category) continue;
                        if (search) {
                            const needle = search.toLowerCase();
                            const hay    = JSON.stringify(entry).toLowerCase();
                            if (!hay.includes(needle)) continue;
                        }
                        results.push(entry);
                        if (results.length >= off + lim) break outer;
                    } catch (_) {}
                }
            }
        }
    }

    res.json(results.slice(off, off + lim));
});

// ─── GET /api/logs/summary ────────────────────────────────────────────────────

app.get('/api/logs/summary', (req, res) => {
    const { deviceID } = req.query;
    const bySource   = {};
    const byCategory = {};
    let total         = 0;
    let oldest        = null;
    let newest        = null;

    const devIDs = deviceID
        ? [deviceID]
        : (fs.existsSync(DATA_DIR) ? fs.readdirSync(DATA_DIR) : []);

    for (const devID of devIDs) {
        const devPath = path.join(DATA_DIR, devID);
        if (!fs.existsSync(devPath) || !fs.statSync(devPath).isDirectory()) continue;

        for (const date of fs.readdirSync(devPath)) {
            const dayPath = path.join(devPath, date);
            if (!fs.statSync(dayPath).isDirectory()) continue;

            for (const file of fs.readdirSync(dayPath).filter(f => f.endsWith('.ndjson'))) {
                const lines = fs.readFileSync(path.join(dayPath, file), 'utf8')
                    .split('\n').filter(l => l.trim());

                for (const line of lines) {
                    try {
                        const e = JSON.parse(line);
                        total++;
                        bySource[e.source]     = (bySource[e.source]     || 0) + 1;
                        byCategory[e.category] = (byCategory[e.category] || 0) + 1;
                        if (!oldest || e.timestamp < oldest) oldest = e.timestamp;
                        if (!newest || e.timestamp > newest) newest = e.timestamp;
                    } catch (_) {}
                }
            }
        }
    }

    res.json({
        totalEntries:     total,
        bySource,
        byCategory,
        devices:          Object.values(deviceRegistry),
        oldestTimestamp:  oldest,
        newestTimestamp:  newest
    });
});

// ─── GET /api/devices ─────────────────────────────────────────────────────────

app.get('/api/devices', (_req, res) => {
    res.json(Object.values(deviceRegistry));
});

// ─── POST /api/device/voip-token ─────────────────────────────────────────────
// Receives the VoIP push token registered by SyncEngine.

app.post('/api/device/voip-token', express.json(), (req, res) => {
    const { deviceID, voipToken } = req.body || {};
    if (deviceID && deviceRegistry[deviceID]) {
        deviceRegistry[deviceID].voipToken = voipToken;
    }
    res.sendStatus(200);
});

// ─── WebSocket setup ──────────────────────────────────────────────────────────

const wss = new WebSocketServer({ server, path: '/' });

wss.on('connection', (ws, req) => {
    const urlPath = new URL(req.url, 'ws://localhost').pathname;

    if (urlPath === '/live') {
        // Android client subscribing to live log entries
        liveSubscribers.add(ws);
        ws.on('close', () => liveSubscribers.delete(ws));
        ws.on('error', () => liveSubscribers.delete(ws));

    } else if (urlPath === '/screen/publish') {
        // iOS device sending JPEG frames
        ws.on('message', (data, isBinary) => {
            if (!isBinary) return;
            // Fan-out to all watching Android clients
            for (const watcher of screenWatchers) {
                if (watcher.readyState === watcher.OPEN) {
                    watcher.send(data);
                }
            }
        });
        ws.on('close', () => {});

    } else if (urlPath === '/screen/watch') {
        // Android client watching the screen stream
        screenWatchers.add(ws);
        ws.on('close', () => screenWatchers.delete(ws));
        ws.on('error', () => screenWatchers.delete(ws));
    }
});

// ─── Start ────────────────────────────────────────────────────────────────────

server.listen(PORT, '0.0.0.0', () => {
    console.log(`[SS Backend] listening on port ${PORT}`);
    console.log(`[SS Backend] data dir: ${DATA_DIR}`);
    console.log(`  POST /api/ingest         — iOS SyncEngine`);
    console.log(`  GET  /api/logs           — query logs`);
    console.log(`  GET  /api/logs/summary   — aggregate stats`);
    console.log(`  GET  /api/devices        — known devices`);
    console.log(`  WS   /live               — live log stream → Android`);
    console.log(`  WS   /screen/publish     — JPEG frames from iOS`);
    console.log(`  WS   /screen/watch       — JPEG frames → Android`);
});
