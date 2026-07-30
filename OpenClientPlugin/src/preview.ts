import { Buffer } from "node:buffer"

export const maximumPreviewBytes = 32 * 1_024
export const maximumPreviewDimension = 96

export type VisualPreview = {
  mimeType: "image/jpeg"
  dataURL: string
  width: number
  height: number
}

export type PreviewOperation = (command: string[], sourceFD: number) => Promise<Uint8Array>

export function previewFromJPEG(bytes: Uint8Array): VisualPreview {
  if (bytes.byteLength === 0 || bytes.byteLength > maximumPreviewBytes) {
    throw new Error("Preview exceeds the supported size limit")
  }
  const dimensions = jpegDimensions(bytes)
  if (dimensions.width > maximumPreviewDimension || dimensions.height > maximumPreviewDimension) {
    throw new Error("Preview dimensions exceed the supported limit")
  }
  return {
    mimeType: "image/jpeg",
    dataURL: `data:image/jpeg;base64,${Buffer.from(bytes).toString("base64")}`,
    ...dimensions,
  }
}

export function parseVisualPreview(value: unknown): VisualPreview | undefined {
  if (!isRecord(value)
    || value.mimeType !== "image/jpeg"
    || typeof value.dataURL !== "string"
    || !isPositiveSafeInteger(value.width)
    || !isPositiveSafeInteger(value.height)) return undefined

  const prefix = "data:image/jpeg;base64,"
  if (!value.dataURL.startsWith(prefix)) return undefined
  const encoded = value.dataURL.slice(prefix.length)
  if (encoded.length === 0 || encoded.length > Math.ceil(maximumPreviewBytes / 3) * 4) return undefined
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) return undefined

  const bytes = Buffer.from(encoded, "base64")
  if (bytes.toString("base64") !== encoded) return undefined
  try {
    const parsed = previewFromJPEG(bytes)
    return parsed.width === value.width && parsed.height === value.height ? parsed : undefined
  } catch {
    return undefined
  }
}

export function previewCommand(inputPath = "/dev/fd/3"): string[] {
  return [
    "ffmpeg",
    "-nostdin",
    "-hide_banner",
    "-loglevel", "error",
    "-i", inputPath,
    "-map", "0:v:0",
    "-frames:v", "1",
    "-vf", `scale=${maximumPreviewDimension}:${maximumPreviewDimension}:force_original_aspect_ratio=decrease`,
    "-c:v", "mjpeg",
    "-q:v", "4",
    "-f", "image2pipe",
    "pipe:1",
  ]
}

export async function spawnJPEGPreview(command: string[], sourceFD: number): Promise<Uint8Array> {
  let process: ReturnType<typeof Bun.spawn>
  try {
    process = Bun.spawn({
      cmd: command,
      stdio: ["ignore", "pipe", "pipe", sourceFD],
      timeout: 15_000,
      killSignal: "SIGKILL",
    })
  } catch {
    throw new Error("Unable to start ffmpeg preview generation")
  }
  if (typeof process.stdout === "number" || process.stdout === undefined
    || typeof process.stderr === "number" || process.stderr === undefined) {
    process.kill("SIGKILL")
    throw new Error("Unable to capture ffmpeg preview output")
  }
  const [output, errorOutput, exitCode] = await Promise.all([
    new Response(process.stdout).arrayBuffer(),
    new Response(process.stderr).text(),
    process.exited,
  ])
  if (exitCode !== 0) {
    throw new Error(errorOutput.trim() === "" ? "Unable to generate media preview" : "Media preview generation failed")
  }
  if (output.byteLength > maximumPreviewBytes) throw new Error("Preview exceeds the supported size limit")
  return new Uint8Array(output)
}

function jpegDimensions(bytes: Uint8Array): { width: number; height: number } {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8
    || bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) {
    throw new Error("Preview must be a complete JPEG image")
  }

  let offset = 2
  let dimensions: { width: number; height: number } | undefined
  let sawScan = false
  while (offset < bytes.length) {
    if (bytes[offset] !== 0xff) throw new Error("Preview contains invalid JPEG markers")
    while (bytes[offset] === 0xff) offset += 1
    const marker = bytes[offset]
    offset += 1
    if (marker === undefined || marker === 0x00) throw new Error("Preview contains invalid JPEG markers")
    if (marker === 0xd9) {
      if (offset !== bytes.length || !sawScan || dimensions === undefined) break
      return dimensions
    }
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      throw new Error("Preview contains invalid JPEG marker ordering")
    }
    if (offset + 2 > bytes.length) throw new Error("Preview contains a truncated JPEG segment")
    const segmentLength = (bytes[offset] ?? 0) * 256 + (bytes[offset + 1] ?? 0)
    if (segmentLength < 2 || offset + segmentLength > bytes.length) {
      throw new Error("Preview contains a truncated JPEG segment")
    }
    if (isStartOfFrame(marker)) {
      if (segmentLength < 7) throw new Error("Preview contains invalid JPEG dimensions")
      const height = (bytes[offset + 3] ?? 0) * 256 + (bytes[offset + 4] ?? 0)
      const width = (bytes[offset + 5] ?? 0) * 256 + (bytes[offset + 6] ?? 0)
      if (!isPositiveSafeInteger(width) || !isPositiveSafeInteger(height)) {
        throw new Error("Preview contains invalid JPEG dimensions")
      }
      if (dimensions !== undefined && (dimensions.width !== width || dimensions.height !== height)) {
        throw new Error("Preview contains conflicting JPEG dimensions")
      }
      dimensions = { width, height }
    }
    offset += segmentLength
    if (marker !== 0xda) continue
    if (dimensions === undefined) throw new Error("Preview JPEG dimensions are missing")
    sawScan = true
    offset = nextMarkerAfterScan(bytes, offset)
  }
  throw new Error("Preview JPEG dimensions are missing")
}

function nextMarkerAfterScan(bytes: Uint8Array, start: number): number {
  let offset = start
  while (offset < bytes.length - 1) {
    if (bytes[offset] !== 0xff) {
      offset += 1
      continue
    }
    const markerStart = offset
    while (bytes[offset] === 0xff) offset += 1
    const marker = bytes[offset]
    if (marker === undefined) break
    offset += 1
    if (marker === 0x00 || (marker >= 0xd0 && marker <= 0xd7)) continue
    return markerStart
  }
  throw new Error("Preview contains a truncated JPEG scan")
}

function isStartOfFrame(marker: number): boolean {
  return (marker >= 0xc0 && marker <= 0xc3)
    || (marker >= 0xc5 && marker <= 0xc7)
    || (marker >= 0xc9 && marker <= 0xcb)
    || (marker >= 0xcd && marker <= 0xcf)
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
}
