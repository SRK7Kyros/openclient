import { describe, expect, test } from "bun:test"
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { OpenClientBridge, type BridgeSocket } from "../src/bridge.js"
import type { ServerMessage } from "../src/protocol.js"
import { createOpenClientTools } from "../src/tools.js"
import { ImageResourceManager } from "../src/image.js"
import { VideoResourceManager } from "../src/video.js"
import { jpegPreview } from "./fixtures.js"

describe("OpenClient video tool execution", () => {
  test("creates a dormant server resource through openclient_execute_tool", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-video-tool-test-"))
    const source = join(temporary, "demo.mp4")
    await writeFile(source, "mp4")
    const canonicalSource = await realpath(source)
    const bridge = await discoveredBridge()

    let spawnCount = 0
    const videoResources = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath: join(temporary, "state", "video-resources.json"),
      probe: async () => JSON.stringify({
        streams: [{ width: 1_280, height: 720 }],
        format: { duration: "3.25" },
      }),
      preview: async () => jpegPreview(96, 54),
      spawn: () => {
        spawnCount += 1
        throw new Error("Tool execution must not spawn ffmpeg")
      },
    })
    const imageResources = new ImageResourceManager({
      registryPath: join(temporary, "state", "image-resources.json"),
    })
    try {
      const tools = createOpenClientTools(bridge, videoResources, imageResources)
      let permissionRequest: unknown
      const result = await tools.openclient_execute_tool.execute({
        client_id: "client",
        tool_id: "openclient_visual_video",
        arguments: { schemaVersion: 1, title: "Demo", filePath: source },
      }, {
        sessionID: "session",
        messageID: "message",
        agent: "build",
        directory: temporary,
        worktree: temporary,
        abort: new AbortController().signal,
        metadata() {},
        async ask(request: unknown) { permissionRequest = request },
      })

      expect(spawnCount).toBe(0)
      expect(result).toMatchObject({
        title: "Demo",
        metadata: {
          renderer: "openclient.video.v1",
          executionMode: "declarative",
          payload: {
            schemaVersion: 1,
            resourceID: expect.stringMatching(/^[A-Za-z0-9_-]{32}$/),
            startPath: expect.stringContaining("/stream"),
            width: 1_280,
            height: 720,
            rotation: 0,
            duration: 3.25,
            file: { name: "demo.mp4", mimeType: "video/mp4" },
          },
        },
      })
      expect(JSON.stringify(result)).not.toContain(source)
      expect(JSON.stringify(result)).not.toContain("hlsPath")
      expect(permissionRequest).toMatchObject({
        patterns: [expect.stringMatching(/^client\/openclient_visual_video\/[a-f0-9]{64}$/)],
        always: [expect.stringMatching(/^client\/openclient_visual_video\/[a-f0-9]{64}$/)],
        metadata: { clientID: "client", toolID: "openclient_visual_video", filePath: canonicalSource },
      })
    } finally {
      bridge.stop()
      await imageResources.stopAll()
      await videoResources.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })

  test("creates image resources with canonical permissions and removes an aborted result", async () => {
    const temporary = await mkdtemp(join(tmpdir(), "openclient-image-tool-test-"))
    const source = join(temporary, "photo.jpg")
    await writeFile(source, "jpeg source bytes")
    const canonicalSource = await realpath(source)
    const bridge = await discoveredBridge()
    let abortOnPreview = false
    let activeAbort: AbortController | undefined
    const imageRegistryPath = join(temporary, "state", "image-resources.json")
    const imageResources = new ImageResourceManager({
      registryPath: imageRegistryPath,
      probe: async () => JSON.stringify({ streams: [{ codec_name: "mjpeg", width: 800, height: 600 }] }),
      preview: async () => {
        if (abortOnPreview) activeAbort?.abort()
        return jpegPreview(96, 72)
      },
    })
    const videoResources = new VideoResourceManager({
      rootDirectory: join(temporary, "hls"),
      registryPath: join(temporary, "state", "video-resources.json"),
    })
    try {
      const tools = createOpenClientTools(bridge, videoResources, imageResources)
      let permissionRequest: unknown
      activeAbort = new AbortController()
      const result = await tools.openclient_execute_tool.execute({
        client_id: "client",
        tool_id: "openclient_visual_image",
        arguments: {
          schemaVersion: 1,
          title: "  Mountain  ",
          accessibilityLabel: "  Snow-covered mountain.  ",
          filePath: source,
        },
      }, toolContext(temporary, activeAbort.signal, (request) => { permissionRequest = request }))

      expect(result).toMatchObject({
        title: "Mountain",
        metadata: {
          renderer: "openclient.image.v1",
          executionMode: "declarative",
          payload: {
            schemaVersion: 1,
            accessibilityLabel: "Snow-covered mountain.",
            resourceID: expect.stringMatching(/^[A-Za-z0-9_-]{32}$/),
            contentPath: expect.stringMatching(/^\/openclient\/v1\/image\/resources\/[A-Za-z0-9_-]{32}\/content$/),
            width: 800,
            height: 600,
            file: { name: "photo.jpg", mimeType: "image/jpeg" },
            preview: { mimeType: "image/jpeg", width: 96, height: 72 },
          },
        },
      })
      expect(JSON.stringify(result)).not.toContain(source)
      expect(permissionRequest).toMatchObject({
        patterns: [expect.stringMatching(/^client\/openclient_visual_image\/[a-f0-9]{64}$/)],
        always: [expect.stringMatching(/^client\/openclient_visual_image\/[a-f0-9]{64}$/)],
        metadata: { clientID: "client", toolID: "openclient_visual_image", filePath: canonicalSource },
      })

      abortOnPreview = true
      activeAbort = new AbortController()
      await expect(tools.openclient_execute_tool.execute({
        client_id: "client",
        tool_id: "openclient_visual_image",
        arguments: { schemaVersion: 1, filePath: source },
      }, toolContext(temporary, activeAbort.signal))).rejects.toThrow("cancelled")
      const registry = JSON.parse(await readFile(imageRegistryPath, "utf8")) as { resources: unknown[] }
      expect(registry.resources).toHaveLength(1)
    } finally {
      bridge.stop()
      await imageResources.stopAll()
      await videoResources.stopAll()
      await rm(temporary, { recursive: true, force: true })
    }
  })
})

async function discoveredBridge(): Promise<OpenClientBridge> {
  const bridge = new OpenClientBridge()
  const socket = new ToolSocket()
  bridge.register("connection", socket, {
    protocol: 1,
    type: "register",
    clientID: "client",
    displayName: "Test iPhone",
    appVersion: "1.0",
  })
  const discovery = bridge.listTools({
    clientID: "client",
    sessionID: "session",
    signal: new AbortController().signal,
  })
  const request = socket.sent.find(
    (message): message is Extract<ServerMessage, { type: "request" }> => message.type === "request",
  )
  if (!request) throw new Error("Missing tool-list request")
  bridge.handleMessage("connection", socket, {
    protocol: 1,
    type: "response",
    id: request.id,
    ok: true,
    result: { tools: [] },
  })
  await discovery
  return bridge
}

function toolContext(
  temporary: string,
  abort: AbortSignal,
  onAsk: (request: unknown) => void = () => {},
) {
  return {
    sessionID: "session",
    messageID: "message",
    agent: "build",
    directory: temporary,
    worktree: temporary,
    abort,
    metadata() {},
    async ask(request: unknown) { onAsk(request) },
  }
}

class ToolSocket implements BridgeSocket {
  readonly sent: ServerMessage[] = []

  send(data: string): number {
    this.sent.push(JSON.parse(data) as ServerMessage)
    return data.length
  }

  close(): void {}
}
