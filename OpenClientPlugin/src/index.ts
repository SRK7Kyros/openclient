import type { Plugin } from "@opencode-ai/plugin"
import { acquireBridge } from "./lifecycle.js"
import { createOpenClientTools } from "./tools.js"

const OpenClientPlugin: Plugin = async ({ client, serverUrl }) => {
  try {
    const lease = await acquireBridge({
      openCodePort: normalizedPort(serverUrl),
      onLog: (level, message) => void log(level, message),
    })
    return {
      dispose: lease.release,
      tool: createOpenClientTools(
        lease.server.bridge,
        lease.server.videoResources,
        lease.server.imageResources,
      ),
    }
  } catch (error) {
    await log("error", `WebSocket bridge failed to start: ${error instanceof Error ? error.message : String(error)}`)
    return {}
  }

  async function log(level: "info" | "warn" | "error", message: string): Promise<void> {
    await client.app.log({
      body: {
        service: "openclient-plugin",
        level,
        message,
      },
    })
  }
}

export default OpenClientPlugin

function normalizedPort(url: URL): number {
  if (!url.port) return url.protocol === "https:" ? 443 : 80
  const port = Number(url.port)
  if (!Number.isInteger(port)) throw new Error(`Invalid OpenCode server port: ${url.port}`)
  return port
}
