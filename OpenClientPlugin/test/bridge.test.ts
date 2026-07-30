import { describe, expect, test } from "bun:test"
import { OpenClientBridge, type BridgeSocket } from "../src/bridge.js"
import type { ServerMessage } from "../src/protocol.js"

class FakeSocket implements BridgeSocket {
  sent: ServerMessage[] = []
  closed: Array<{ code?: number; reason?: string }> = []

  send(data: string): number {
    this.sent.push(JSON.parse(data) as ServerMessage)
    return data.length
  }

  close(code?: number, reason?: string): void {
    this.closed.push({ code, reason })
  }
}

describe("OpenClient bridge", () => {
  test("keeps multiple clients and requests live tool lists", async () => {
    const bridge = new OpenClientBridge()
    const first = new FakeSocket()
    const second = new FakeSocket()
    bridge.register("connection-1", first, registration("a"))
    bridge.register("connection-2", second, registration("b"))
    attach(bridge, "connection-1", first)
    attach(bridge, "connection-2", second)

    const promise = bridge.listTools({ sessionID: "session", signal: new AbortController().signal })
    respondToLatest(bridge, "connection-1", first, "alpha")
    respondToLatest(bridge, "connection-2", second, "beta")

    const clients = await promise
    expect(clients.map((client) => client.clientID)).toEqual(["a", "b"])
    expect(clients[0]?.tools[0]?.id).toBe("alpha")
    expect(clients[1]?.tools[0]?.id).toBe("beta")
    expect(clients[0]?.tools.find((tool) => tool.id === "openclient_visual_video")?.inputSchema).toMatchObject({
      required: ["schemaVersion", "filePath"],
    })
    expect(clients[0]?.tools.find((tool) => tool.id === "openclient_visual_image")?.inputSchema).toMatchObject({
      required: ["schemaVersion", "filePath"],
      additionalProperties: false,
    })
  })

  test("replaces duplicate client IDs", () => {
    const bridge = new OpenClientBridge()
    const first = new FakeSocket()
    const second = new FakeSocket()
    bridge.register("connection-1", first, registration("same"))
    bridge.register("connection-2", second, registration("same"))
    expect(first.closed).toEqual([{ code: 4001, reason: "Replaced by a newer connection" }])
    expect(bridge.connectedClientCount()).toBe(1)
  })

  test("removes the old identity when one socket re-registers", () => {
    const bridge = new OpenClientBridge()
    const socket = new FakeSocket()
    bridge.register("connection", socket, registration("old"))
    bridge.register("connection", socket, registration("new"))
    expect(bridge.connectedClientCount()).toBe(1)
    expect(() => bridge.validateExecution("old", "status", "session")).toThrow("not connected")
  })

  test("ignores a response from the wrong connection", async () => {
    const bridge = new OpenClientBridge()
    const first = new FakeSocket()
    const second = new FakeSocket()
    bridge.register("connection-1", first, registration("a"))
    bridge.register("connection-2", second, registration("b"))
    attach(bridge, "connection-1", first)
    attach(bridge, "connection-2", second)
    const promise = bridge.listTools({ clientID: "a", sessionID: "session", signal: new AbortController().signal })
    const request = latestRequest(first)
    bridge.handleMessage("connection-2", second, response(request.id, "wrong"))
    bridge.handleMessage("connection-1", first, response(request.id, "right"))
    expect((await promise)[0]?.tools[0]?.id).toBe("right")
  })

  test("keeps healthy clients when another tool list is invalid", async () => {
    const bridge = new OpenClientBridge()
    const first = new FakeSocket()
    const second = new FakeSocket()
    bridge.register("connection-1", first, registration("a"))
    bridge.register("connection-2", second, registration("b"))
    attach(bridge, "connection-1", first)
    attach(bridge, "connection-2", second)
    const promise = bridge.listTools({ sessionID: "session", signal: new AbortController().signal })
    respondToLatest(bridge, "connection-1", first, "healthy")
    const request = latestRequest(second)
    bridge.handleMessage("connection-2", second, {
      protocol: 1,
      type: "response",
      id: request.id,
      ok: true,
      result: { tools: "invalid" },
    })
    const clients = await promise
    expect(clients.find((client) => client.clientID === "a")?.tools[0]?.id).toBe("healthy")
    expect(clients.find((client) => client.clientID === "b")?.error).toContain("contain tools")
  })

  test("cancels an in-flight execution without enforcing session affinity", async () => {
    const bridge = new OpenClientBridge()
    const socket = new FakeSocket()
    bridge.register("connection", socket, registration("client"))
    attach(bridge, "connection", socket)
    const listPromise = bridge.listTools({ sessionID: "session", signal: new AbortController().signal })
    respondToLatest(bridge, "connection", socket, "status")
    await listPromise
    expect(() => bridge.validateExecution("client", "status", "other-session")).not.toThrow()

    const abort = new AbortController()
    const execution = bridge.execute({
      clientID: "client",
      toolID: "status",
      arguments: {},
      context: {
        sessionID: "session",
        messageID: "message",
        agent: "build",
        directory: "/tmp/project",
        worktree: "/tmp/project",
      },
      signal: abort.signal,
    })
    abort.abort()
    await expect(execution).rejects.toThrow("cancelled")
    expect(socket.sent.some((message) => message.type === "cancel")).toBe(true)
  })

  test("remembers capabilities across sessions after a client disconnects", async () => {
    const bridge = new OpenClientBridge()
    const socket = new FakeSocket()
    bridge.register("connection", socket, registration("client"))
    attach(bridge, "connection", socket)
    const listPromise = bridge.listTools({ sessionID: "session", signal: new AbortController().signal })
    respondToLatest(bridge, "connection", socket, "openclient_visual_html")
    await listPromise

    bridge.disconnect("connection")

    expect(() => bridge.validateExecution(
      "client",
      "openclient_visual_html",
      "session",
      true,
    )).not.toThrow()
    expect(() => bridge.validateExecution(
      "client",
      "openclient_visual_html",
      "session",
    )).toThrow("not connected")
    expect(() => bridge.validateExecution(
      "client",
      "openclient_visual_html",
      "different-session",
      true,
    )).not.toThrow()

    const remembered = await bridge.listTools({
      clientID: "client",
      sessionID: "different-session",
      signal: new AbortController().signal,
    })
    expect(remembered).toHaveLength(1)
    expect(remembered[0]?.connected).toBe(false)
    expect(remembered[0]?.tools[0]?.id).toBe("openclient_visual_html")
  })

  test("keeps remembered visuals available after reconnecting in another session", async () => {
    const bridge = new OpenClientBridge()
    const firstSocket = new FakeSocket()
    bridge.register("connection-1", firstSocket, registration("client"))
    attach(bridge, "connection-1", firstSocket)
    const firstList = bridge.listTools({ sessionID: "session", signal: new AbortController().signal })
    respondToLatest(bridge, "connection-1", firstSocket, "openclient_visual_html")
    await firstList
    bridge.disconnect("connection-1")

    const secondSocket = new FakeSocket()
    bridge.register("connection-2", secondSocket, registration("client"))
    bridge.handleMessage("connection-2", secondSocket, {
      protocol: 1,
      type: "session_updated",
      sessionID: "other-session",
    })

    expect(() => bridge.validateExecution(
      "client",
      "openclient_visual_html",
      "session",
      true,
    )).not.toThrow()
    expect(() => bridge.validateExecution(
      "client",
      "openclient_visual_html",
      "other-session",
      true,
    )).not.toThrow()
  })

  test("allows tool discovery to finish across a session change", async () => {
    const bridge = new OpenClientBridge()
    const socket = new FakeSocket()
    bridge.register("connection", socket, registration("client"))
    attach(bridge, "connection", socket)
    const discovery = bridge.listTools({
      clientID: "client",
      sessionID: "session",
      signal: new AbortController().signal,
    })
    const request = latestRequest(socket)

    bridge.handleMessage("connection", socket, {
      protocol: 1,
      type: "session_updated",
      sessionID: "other-session",
    })
    bridge.handleMessage("connection", socket, response(request.id, "openclient_visual_html"))

    expect((await discovery)[0]?.tools[0]?.id).toBe("openclient_visual_html")
    expect(() => bridge.validateExecution(
      "client",
      "openclient_visual_html",
      "other-session",
      true,
    )).not.toThrow()
  })
})

function registration(clientID: string) {
  return {
    protocol: 1 as const,
    type: "register" as const,
    clientID,
    displayName: clientID.toUpperCase(),
    appVersion: "1.0",
  }
}

function latestRequest(socket: FakeSocket): Extract<ServerMessage, { type: "request" }> {
  const message = [...socket.sent].reverse().find(
    (item): item is Extract<ServerMessage, { type: "request" }> => item.type === "request",
  )
  if (!message) throw new Error("Missing request")
  return message
}

function respondToLatest(bridge: OpenClientBridge, connectionID: string, socket: FakeSocket, toolID: string): void {
  bridge.handleMessage(connectionID, socket, response(latestRequest(socket).id, toolID))
}

function attach(bridge: OpenClientBridge, connectionID: string, socket: FakeSocket): void {
  bridge.handleMessage(connectionID, socket, {
    protocol: 1,
    type: "session_updated",
    sessionID: "session",
  })
}

function response(id: string, toolID: string) {
  return {
    protocol: 1 as const,
    type: "response" as const,
    id,
    ok: true,
    result: {
      tools: [{ id: toolID, description: toolID, inputSchema: {} }],
    },
  }
}
