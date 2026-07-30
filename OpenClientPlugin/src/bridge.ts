import {
  parseRemoteToolResult,
  parseToolList,
  protocolVersion,
  type ClientMessage,
  type ClientToolDescriptor,
  type JsonObject,
  type JsonValue,
  type RegisterMessage,
  type RemoteExecutionContext,
  type RemoteToolResult,
  type ServerMessage,
} from "./protocol.js"
import { pluginDeclarativeToolDescriptors } from "./declarative.js"

export interface BridgeSocket {
  send(data: string): number
  close(code?: number, reason?: string): void
}

type ClientRecord = {
  connectionID: string
  clientID: string
  displayName: string
  appVersion: string
  socket: BridgeSocket
  tools: Map<string, ClientToolDescriptor>
}

type PendingRequest = {
  connectionID: string
  resolve: (value: JsonValue) => void
  reject: (error: Error) => void
  timer: ReturnType<typeof setTimeout>
  removeAbortListener: () => void
}

type RememberedClient = {
  snapshot: ClientSnapshot
  expiresAt: number
}

const rememberedClientTTLMS = 24 * 60 * 60 * 1_000
const maximumRememberedClients = 64

export type ClientSnapshot = {
  clientID: string
  displayName: string
  appVersion: string
  tools: ClientToolDescriptor[]
  connected: boolean
  error?: string
}

export class OpenClientBridge {
  private readonly clients = new Map<string, ClientRecord>()
  private readonly rememberedClients = new Map<string, RememberedClient>()
  private readonly clientIDByConnectionID = new Map<string, string>()
  private readonly pending = new Map<string, PendingRequest>()

  register(connectionID: string, socket: BridgeSocket, message: RegisterMessage): void {
    const previousClientID = this.clientIDByConnectionID.get(connectionID)
    if (previousClientID && previousClientID !== message.clientID) {
      this.clients.delete(previousClientID)
      this.removeRememberedClient(previousClientID)
    }
    const existing = this.clients.get(message.clientID)
    if (existing && existing.connectionID !== connectionID) {
      this.rejectPendingForConnection(existing.connectionID, new Error("OpenClient reconnected"))
      this.clientIDByConnectionID.delete(existing.connectionID)
      existing.socket.close(4001, "Replaced by a newer connection")
    }

    this.clients.set(message.clientID, {
      connectionID,
      clientID: message.clientID,
      displayName: message.displayName,
      appVersion: message.appVersion,
      socket,
      tools: new Map(),
    })
    this.clientIDByConnectionID.set(connectionID, message.clientID)
    this.send(socket, {
      protocol: protocolVersion,
      type: "registered",
      clientID: message.clientID,
    })
  }

  handleMessage(connectionID: string, socket: BridgeSocket, message: ClientMessage): void {
    if (message.type === "register") {
      this.register(connectionID, socket, message)
      return
    }

    const client = this.clientForConnection(connectionID)
    if (!client) throw new Error("Client must register before sending messages")

    switch (message.type) {
      case "session_updated":
        break
      case "response":
        this.handleResponse(connectionID, message)
        break
      case "pong":
        break
    }
  }

  disconnect(connectionID: string): void {
    const clientID = this.clientIDByConnectionID.get(connectionID)
    if (clientID) {
      const client = this.clients.get(clientID)
      if (client?.connectionID === connectionID) this.clients.delete(clientID)
      this.clientIDByConnectionID.delete(connectionID)
    }
    this.rejectPendingForConnection(connectionID, new Error("OpenClient disconnected"))
  }

  async listTools(input: {
    sessionID: string
    clientID?: string
    signal: AbortSignal
  }): Promise<ClientSnapshot[]> {
    const candidates = this.selectClients(input.clientID)
    const snapshots = await Promise.all(candidates.map(async (client) => {
      const expectedConnectionID = client.connectionID
      try {
        const value = await this.request(
          client,
          "list_tools",
          { sessionID: input.sessionID },
          input.signal,
          15_000,
        )
        const current = this.clients.get(client.clientID)
        if (current?.connectionID !== expectedConnectionID) {
          throw new Error(`OpenClient ${client.clientID} reconnected during tool discovery`)
        }
        const tools = parseToolList(value).sort((left, right) => left.id.localeCompare(right.id))
        for (const descriptor of pluginDeclarativeToolDescriptors) {
          const existingIndex = tools.findIndex((tool) => tool.id === descriptor.id)
          if (existingIndex >= 0) tools.splice(existingIndex, 1)
          tools.push(descriptor)
        }
        client.tools = new Map(tools.map((tool) => [tool.id, tool]))
        const snapshot = this.snapshot(client)
        this.remember(snapshot)
        return snapshot
      } catch (error) {
        client.tools.clear()
        if (input.clientID || input.signal.aborted) throw error
        return {
          ...this.snapshot(client),
          tools: [],
          error: error instanceof Error ? error.message : String(error),
        }
      }
    }))
    const activeClientIDs = new Set(snapshots.map((snapshot) => snapshot.clientID))
    this.purgeExpiredRememberedClients()
    for (const remembered of this.rememberedClients.values()) {
      const snapshot = remembered.snapshot
      if (activeClientIDs.has(snapshot.clientID)) continue
      if (input.clientID !== undefined && snapshot.clientID !== input.clientID) continue
      snapshots.push(snapshot)
    }
    return snapshots.sort((left, right) => left.clientID.localeCompare(right.clientID))
  }

  async execute(input: {
    clientID: string
    toolID: string
    arguments: JsonObject
    context: RemoteExecutionContext
    signal: AbortSignal
  }): Promise<RemoteToolResult> {
    const client = this.clients.get(input.clientID)
    if (!client) throw new Error(`OpenClient ${input.clientID} is not connected`)
    if (!client.tools.has(input.toolID)) {
      throw new Error(`Tool ${input.toolID} is not in the latest tool list for ${input.clientID}`)
    }

    const value = await this.request(
      client,
      "execute_tool",
      {
        toolID: input.toolID,
        arguments: input.arguments,
        context: input.context,
      },
      input.signal,
      60_000,
    )
    return parseRemoteToolResult(value)
  }

  connectedClientCount(): number {
    return this.clients.size
  }

  validateExecution(
    clientID: string,
    toolID: string,
    _sessionID: string,
    allowRemembered = false,
  ): ClientSnapshot {
    const client = this.clients.get(clientID)
    if (client?.tools.has(toolID)) return this.snapshot(client)

    const remembered = allowRemembered ? this.rememberedSnapshot(clientID) : undefined
    if (remembered?.tools.some((tool) => tool.id === toolID)) {
      return remembered
    }
    if (!client) throw new Error(`OpenClient ${clientID} is not connected`)
    if (!client.tools.has(toolID)) {
      throw new Error(`Tool ${toolID} is not in the latest tool list for ${clientID}`)
    }
    return this.snapshot(client)
  }

  stop(): void {
    for (const client of this.clients.values()) client.socket.close(1001, "Bridge stopped")
    this.clients.clear()
    this.rememberedClients.clear()
    this.clientIDByConnectionID.clear()
    for (const [id, pending] of this.pending) {
      this.finishPending(id, pending)
      pending.reject(new Error("OpenClient bridge stopped"))
    }
  }

  private selectClients(clientID?: string): ClientRecord[] {
    if (clientID) {
      const client = this.clients.get(clientID)
      if (!client) {
        if (this.rememberedSnapshot(clientID)) return []
        throw new Error(`OpenClient ${clientID} is not connected`)
      }
      return [client]
    }

    return [...this.clients.values()]
  }

  private request(
    client: ClientRecord,
    method: "list_tools" | "execute_tool",
    params: JsonObject,
    signal: AbortSignal,
    timeoutMS: number,
  ): Promise<JsonValue> {
    if (signal.aborted) return Promise.reject(abortError())
    const inFlight = [...this.pending.values()].filter((item) => item.connectionID === client.connectionID).length
    if (inFlight >= 16) return Promise.reject(new Error(`OpenClient ${client.clientID} has too many pending requests`))

    const id = crypto.randomUUID()
    return new Promise<JsonValue>((resolve, reject) => {
      const onAbort = () => {
        const pending = this.pending.get(id)
        if (!pending) return
        this.finishPending(id, pending)
        this.sendBestEffort(client.socket, { protocol: protocolVersion, type: "cancel", id })
        reject(abortError())
      }
      signal.addEventListener("abort", onAbort, { once: true })

      const pending: PendingRequest = {
        connectionID: client.connectionID,
        resolve,
        reject,
        timer: setTimeout(() => {
          const active = this.pending.get(id)
          if (!active) return
          this.finishPending(id, active)
          this.sendBestEffort(client.socket, { protocol: protocolVersion, type: "cancel", id })
          reject(new Error(`OpenClient ${method} request timed out`))
        }, timeoutMS),
        removeAbortListener: () => signal.removeEventListener("abort", onAbort),
      }
      this.pending.set(id, pending)

      try {
        this.send(client.socket, { protocol: protocolVersion, type: "request", id, method, params })
      } catch (error) {
        this.finishPending(id, pending)
        reject(error)
      }
    })
  }

  private handleResponse(connectionID: string, message: Extract<ClientMessage, { type: "response" }>): void {
    const pending = this.pending.get(message.id)
    if (!pending || pending.connectionID !== connectionID) return
    this.finishPending(message.id, pending)
    if (!message.ok) {
      pending.reject(new Error(message.error?.message ?? "OpenClient tool failed"))
      return
    }
    pending.resolve(message.result as JsonValue)
  }

  private rejectPendingForConnection(connectionID: string, error: Error): void {
    for (const [id, pending] of this.pending) {
      if (pending.connectionID !== connectionID) continue
      this.finishPending(id, pending)
      pending.reject(error)
    }
  }

  private finishPending(id: string, pending: PendingRequest): void {
    clearTimeout(pending.timer)
    pending.removeAbortListener()
    this.pending.delete(id)
  }

  private clientForConnection(connectionID: string): ClientRecord | undefined {
    const clientID = this.clientIDByConnectionID.get(connectionID)
    return clientID ? this.clients.get(clientID) : undefined
  }

  private snapshot(client: ClientRecord): ClientSnapshot {
    return {
      clientID: client.clientID,
      displayName: client.displayName,
      appVersion: client.appVersion,
      tools: [...client.tools.values()],
      connected: true,
    }
  }

  private remember(snapshot: ClientSnapshot): void {
    this.purgeExpiredRememberedClients()
    this.rememberedClients.delete(snapshot.clientID)
    this.rememberedClients.set(snapshot.clientID, {
      snapshot: { ...snapshot, connected: false },
      expiresAt: Date.now() + rememberedClientTTLMS,
    })
    while (this.rememberedClients.size > maximumRememberedClients) {
      const oldest = this.rememberedClients.keys().next().value
      if (oldest === undefined) break
      this.rememberedClients.delete(oldest)
    }
  }

  private rememberedSnapshot(clientID: string): ClientSnapshot | undefined {
    this.purgeExpiredRememberedClients()
    return this.rememberedClients.get(clientID)?.snapshot
  }

  private removeRememberedClient(clientID: string): void {
    for (const [key, remembered] of this.rememberedClients) {
      if (remembered.snapshot.clientID === clientID) this.rememberedClients.delete(key)
    }
  }

  private purgeExpiredRememberedClients(): void {
    const now = Date.now()
    for (const [key, remembered] of this.rememberedClients) {
      if (remembered.expiresAt <= now) this.rememberedClients.delete(key)
    }
  }

  private send(socket: BridgeSocket, message: ServerMessage): void {
    const result = socket.send(JSON.stringify(message))
    if (result === 0) throw new Error("OpenClient socket is unavailable")
  }

  private sendBestEffort(socket: BridgeSocket, message: ServerMessage): void {
    try {
      socket.send(JSON.stringify(message))
    } catch {
      // Cancellation is already complete locally.
    }
  }
}

function abortError(): Error {
  return new DOMException("OpenClient request cancelled", "AbortError")
}
