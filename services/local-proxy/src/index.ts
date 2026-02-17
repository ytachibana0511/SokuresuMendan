import http from "node:http";
import express from "express";
import { WebSocketServer } from "ws";
import { config, hasApiKey, safeLog } from "./config.js";
import { streamStage1, streamStage2 } from "./generation.js";
import { RealtimeBridge } from "./realtimeBridge.js";
import { stage1RequestSchema, stage2RequestSchema } from "./types.js";

const app = express();
app.use(express.json({ limit: "1mb" }));

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    version: "0.1.0",
    mode: hasApiKey() ? "openai" : "fallback"
  });
});

app.post("/generate-stage1", async (req, res) => {
  const parsed = stage1RequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  res.setHeader("Content-Type", "application/x-ndjson; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");

  await streamStage1(res, parsed.data);
});

app.post("/generate-stage2", async (req, res) => {
  const parsed = stage2RequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.flatten() });
    return;
  }

  res.setHeader("Content-Type", "application/x-ndjson; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache, no-transform");
  res.setHeader("Connection", "keep-alive");

  await streamStage2(res, parsed.data);
});

const server = http.createServer(app);
const wsServer = new WebSocketServer({ noServer: true });

server.on("upgrade", (request, socket, head) => {
  if (!request.url || !request.url.startsWith("/ws/transcribe")) {
    socket.destroy();
    return;
  }

  wsServer.handleUpgrade(request, socket, head, (ws) => {
    wsServer.emit("connection", ws, request);
  });
});

wsServer.on("connection", (ws) => {
  const bridge = new RealtimeBridge(ws);
  bridge.start();

  ws.on("message", (data) => {
    bridge.handleClientMessage(data);
  });

  ws.on("close", () => {
    bridge.stop();
  });

  ws.on("error", (error) => {
    safeLog(`client ws error: ${error.message}`);
  });
});

server.listen(config.port, config.host, () => {
  safeLog(`Listening on http://${config.host}:${config.port}`);
  safeLog(`OpenAI mode: ${hasApiKey() ? "enabled" : "fallback"}`);
});
