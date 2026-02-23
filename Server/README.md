# FakeTwitter Local Server

Run the API locally for the iOS app:

```bash
cd FakeTwitter/Server
npm install
npm start
```

Server URL: `http://localhost:8080`

## Server structure

- `server.js` bootstrap entrypoint
- `src/app.js` shared app + route registration
- `src/levels/level1.js`
- `src/levels/level2.js`
- `src/levels/level3.js`
- `src/levels/level4.js`
- `src/state/store.js`
- `src/utils/network.js`

## Endpoint behavior by level

- `POST /level1/tweets`
  - Simulates occasional failure (~30%)
- `POST /level2/tweets`
  - Simulates frequent failure (~80%)
  - Supports `Idempotency-Key` header replay
- `POST /level3/uploads/start`
- `PUT /level3/uploads/:sessionId/chunk`
  - Accepts raw chunk bytes with `Upload-Offset` and `Upload-Length`
  - Throttled (~2.5s per chunk) so full uploads are visibly slow
- `GET /level3/uploads/:sessionId`
  - Returns authoritative server offset for resume
- `POST /level3/uploads/:sessionId/complete`
- `POST /level4/tweets`
  - Mostly succeeds with small delay and occasional transient failures

## Notes

- Data is in-memory only for demo purposes.
- Restarting the server resets tweets and upload sessions.
