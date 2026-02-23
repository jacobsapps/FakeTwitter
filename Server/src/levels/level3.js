const crypto = require('crypto');
const express = require('express');
const { delay, randomFailure } = require('../utils/network');

const LEVEL3_CHUNK_FAIL_RATE = 0.2;
const LEVEL3_CHUNK_DELAY_MS = 2500;

function registerLevel3Routes(app, store) {
  app.post('/level3/uploads/start', (req, res) => {
    const text = req.body?.text;
    const filename = req.body?.filename;
    const totalBytes = Number(req.body?.totalBytes || 0);

    if (!text || !filename || !Number.isFinite(totalBytes) || totalBytes <= 0) {
      return res.status(400).json({ message: 'Invalid start payload.' });
    }

    const sessionId = crypto.randomUUID();
    store.level3Sessions.set(sessionId, {
      sessionId,
      text,
      filename,
      totalBytes,
      offset: 0,
      complete: false,
      createdAt: store.nowISO()
    });

    console.log('🎬 Level3 session started', sessionId, filename, totalBytes);
    return res.status(201).json({ sessionId, nextOffset: 0 });
  });

  app.get('/level3/uploads/:sessionId', (req, res) => {
    const session = store.level3Sessions.get(req.params.sessionId);
    if (!session) {
      return res.status(404).json({ message: 'Session not found.' });
    }

    return res.json({
      sessionId: session.sessionId,
      offset: session.offset,
      totalBytes: session.totalBytes,
      complete: session.complete
    });
  });

  app.put(
    '/level3/uploads/:sessionId/chunk',
    express.raw({ type: 'application/octet-stream', limit: '200mb' }),
    async (req, res) => {
      const session = store.level3Sessions.get(req.params.sessionId);
      if (!session) {
        return res.status(404).json({ message: 'Session not found.' });
      }

      const offsetHeader = Number(req.header('Upload-Offset') || 0);
      const uploadLengthHeader = Number(req.header('Upload-Length') || session.totalBytes);

      if (!Number.isFinite(offsetHeader) || offsetHeader < 0) {
        return res.status(400).json({ message: 'Invalid Upload-Offset header.' });
      }

      if (uploadLengthHeader !== session.totalBytes) {
        return res.status(409).json({ message: 'Upload length mismatch.' });
      }

      if (offsetHeader !== session.offset) {
        res.setHeader('Upload-Offset', String(session.offset));
        return res.status(409).json({ message: 'Offset mismatch.' });
      }

      if (randomFailure(LEVEL3_CHUNK_FAIL_RATE)) {
        console.log('🧯 Level3 simulated chunk failure', session.sessionId);
        return res.status(500).json({ message: 'Simulated chunk upload failure.' });
      }

      await delay(LEVEL3_CHUNK_DELAY_MS);

      const chunkLength = Buffer.isBuffer(req.body) ? req.body.length : 0;
      session.offset += chunkLength;

      if (session.offset > session.totalBytes) {
        session.offset = session.totalBytes;
      }

      if (session.offset >= session.totalBytes) {
        session.complete = true;
      }

      store.level3Sessions.set(session.sessionId, session);

      console.log('📦 Level3 chunk accepted', session.sessionId, `${session.offset}/${session.totalBytes}`);

      res.setHeader('Upload-Offset', String(session.offset));
      return res.status(204).end();
    }
  );

  app.post('/level3/uploads/:sessionId/complete', (req, res) => {
    const session = store.level3Sessions.get(req.params.sessionId);
    if (!session) {
      return res.status(404).json({ message: 'Session not found.' });
    }

    if (session.offset < session.totalBytes) {
      return res.status(409).json({
        message: `Upload incomplete. Server offset is ${session.offset}.`
      });
    }

    const tweet = store.createTweet(req.body?.text || session.text, 'level3');
    store.level3Sessions.delete(session.sessionId);

    console.log('🎉 Level3 upload completed', tweet.id);
    return res.status(201).json({ tweet });
  });
}

module.exports = {
  registerLevel3Routes
};
