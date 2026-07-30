export const protocolVersion = 1 as const

export type JsonPrimitive = string | number | boolean | null
export type JsonValue = JsonPrimitive | JsonValue[] | JsonObject
export type JsonObject = { [key: string]: JsonValue }

export type ClientToolDescriptor = {
  id: string
  description: string
  inputSchema: JsonObject
}

export type RegisterMessage = {
  protocol: typeof protocolVersion
  type: "register"
  clientID: string
  displayName: string
  appVersion: string
}

export type SessionUpdatedMessage = {
  protocol: typeof protocolVersion
  type: "session_updated"
  sessionID?: string
}

export type ResponseMessage = {
  protocol: typeof protocolVersion
  type: "response"
  id: string
  ok: boolean
  result?: JsonValue
  error?: {
    code: string
    message: string
  }
}

export type PongMessage = {
  protocol: typeof protocolVersion
  type: "pong"
  id: string
}

export type ClientMessage = RegisterMessage | SessionUpdatedMessage | ResponseMessage | PongMessage

export type RemoteExecutionContext = {
  sessionID: string
  messageID: string
  agent: string
  directory: string
  worktree: string
}

export type RemoteToolResult = {
  title?: string
  output: string
  metadata?: JsonObject
}

export type ServerRequest = {
  protocol: typeof protocolVersion
  type: "request"
  id: string
  method: "list_tools" | "execute_tool"
  params: JsonObject
}

export type CancelRequest = {
  protocol: typeof protocolVersion
  type: "cancel"
  id: string
}

export type RegisteredMessage = {
  protocol: typeof protocolVersion
  type: "registered"
  clientID: string
}

export type ServerMessage = ServerRequest | CancelRequest | RegisteredMessage

const identifierLimit = 128
const displayNameLimit = 128
const appVersionLimit = 64

export function parseClientMessage(payload: string): ClientMessage {
  let value: unknown
  try {
    value = JSON.parse(payload)
  } catch {
    throw new Error("Message is not valid JSON")
  }

  const object = requireObject(value, "message")
  if (object.protocol !== protocolVersion) {
    throw new Error(`Unsupported protocol version: ${String(object.protocol)}`)
  }

  switch (object.type) {
    case "register":
      return {
        protocol: protocolVersion,
        type: "register",
        clientID: requireString(object.clientID, "clientID", identifierLimit),
        displayName: requireString(object.displayName, "displayName", displayNameLimit),
        appVersion: requireString(object.appVersion, "appVersion", appVersionLimit),
      }
    case "session_updated": {
      const sessionID = optionalString(object.sessionID, "sessionID", identifierLimit)
      return {
        protocol: protocolVersion,
        type: "session_updated",
        ...(sessionID === undefined ? {} : { sessionID }),
      }
    }
    case "response": {
      const ok = object.ok
      if (typeof ok !== "boolean") throw new Error("ok must be a boolean")
      const result = object.result
      if (result !== undefined && !isJsonValue(result)) throw new Error("result must be JSON")

      let error: ResponseMessage["error"]
      if (object.error !== undefined) {
        const errorObject = requireObject(object.error, "error")
        error = {
          code: requireString(errorObject.code, "error.code", identifierLimit),
          message: requireString(errorObject.message, "error.message", 4_096),
        }
      }
      if (ok && result === undefined) throw new Error("Successful response is missing result")
      if (!ok && error === undefined) throw new Error("Failed response is missing error")

      return {
        protocol: protocolVersion,
        type: "response",
        id: requireString(object.id, "id", identifierLimit),
        ok,
        ...(result === undefined ? {} : { result }),
        ...(error === undefined ? {} : { error }),
      }
    }
    case "pong":
      return {
        protocol: protocolVersion,
        type: "pong",
        id: requireString(object.id, "id", identifierLimit),
      }
    default:
      throw new Error(`Unsupported message type: ${String(object.type)}`)
  }
}

export function parseToolList(value: JsonValue): ClientToolDescriptor[] {
  const object = requireObject(value, "tool list result")
  if (!Array.isArray(object.tools)) throw new Error("tool list result must contain tools")
  if (object.tools.length > 100) throw new Error("tool list exceeds 100 tools")

  const seen = new Set<string>()
  return object.tools.map((item, index) => {
    const tool = requireObject(item, `tools[${index}]`)
    const id = requireString(tool.id, `tools[${index}].id`, identifierLimit)
    if (seen.has(id)) throw new Error(`Duplicate tool ID: ${id}`)
    seen.add(id)
    return {
      id,
      description: requireString(tool.description, `tools[${index}].description`, 8_192),
      inputSchema: requireObject(tool.inputSchema, `tools[${index}].inputSchema`) as JsonObject,
    }
  })
}

export function parseRemoteToolResult(value: JsonValue): RemoteToolResult {
  const object = requireObject(value, "tool result")
  const title = optionalString(object.title, "tool result.title", 512)
  const metadataValue = object.metadata
  const metadata = metadataValue === undefined
    ? undefined
    : requireObject(metadataValue, "tool result.metadata") as JsonObject
  return {
    output: requireString(object.output, "tool result.output", 1_000_000),
    ...(title === undefined ? {} : { title }),
    ...(metadata === undefined ? {} : { metadata }),
  }
}

export function isJsonObject(value: unknown): value is JsonObject {
  return isPlainObject(value) && Object.values(value).every(isJsonValue)
}

function isJsonValue(value: unknown): value is JsonValue {
  if (value === null || typeof value === "string" || typeof value === "boolean") return true
  if (typeof value === "number") return Number.isFinite(value)
  if (Array.isArray(value)) return value.every(isJsonValue)
  return isJsonObject(value)
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function requireObject(value: unknown, field: string): Record<string, unknown> {
  if (!isPlainObject(value)) throw new Error(`${field} must be an object`)
  return value
}

function requireString(value: unknown, field: string, limit: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > limit) {
    throw new Error(`${field} must be a non-empty string of at most ${limit} characters`)
  }
  return value
}

function optionalString(value: unknown, field: string, limit: number): string | undefined {
  if (value === undefined || value === null) return undefined
  return requireString(value, field, limit)
}
