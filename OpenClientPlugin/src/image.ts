import { constants as fsConstants, type Stats } from "node:fs"
import { access, chmod, mkdir, open, readFile, realpath, rename, rm, stat, writeFile } from "node:fs/promises"
import { basename, dirname, extname, isAbsolute, join } from "node:path"
import { homedir, platform } from "node:os"
import { randomBytes } from "node:crypto"
import type { JsonObject } from "./protocol.js"
import {
  parseVisualPreview,
  previewCommand,
  previewFromJPEG,
  spawnJPEGPreview,
  type PreviewOperation,
  type VisualPreview,
} from "./preview.js"

export const imageToolID = "openclient_visual_image"
export const imageRendererID = "openclient.image.v1"

const imageResourcePathPrefix = "/openclient/v1/image/resources"
const opaqueIDPattern = /^[A-Za-z0-9_-]{32}$/
const defaultResourceTTLMS = 30 * 24 * 60 * 60 * 1_000
const defaultMaximumSourceBytes = 20 * 1_024 * 1_024
const defaultMaximumResources = 128

export type ImageExecutionContext = {
  clientID: string
  sessionID: string
  messageID: string
  agent: string
  directory: string
  worktree: string
}

export type ImageMimeType = "image/jpeg" | "image/png" | "image/webp"

export type ImageResourcePayload = JsonObject & {
  schemaVersion: 1
  title?: string
  accessibilityLabel?: string
  resourceID: string
  contentPath: string
  expiresAt: string
  width: number
  height: number
  file: {
    name: string
    sizeBytes: number
    modifiedAt: string
    mimeType: ImageMimeType
  }
  preview: VisualPreview
}

export type ImageContent = {
  bytes: Uint8Array
  contentType: ImageMimeType
  sizeBytes: number
}

export type ImageResourceManagerOptions = {
  rootDirectory?: string
  registryPath?: string
  resourceTTLMS?: number
  sweepIntervalMS?: number
  maximumSourceBytes?: number
  maximumResources?: number
  now?: () => number
  probe?: (command: string[], sourceFD: number) => Promise<string>
  preview?: PreviewOperation
}

type SourceIdentity = {
  device: number
  inode: number
  size: number
  modifiedAtMS: number
}

type ImageResource = {
  id: string
  canonicalPath: string
  title?: string
  accessibilityLabel?: string
  context: ImageExecutionContext
  identity: SourceIdentity
  width: number
  height: number
  file: ImageResourcePayload["file"]
  preview: VisualPreview
  expiresAt: number
  lastAccessedAt: number
}

export class ImageResourceError extends Error {
  constructor(
    message: string,
    readonly status: 404 | 409 | 500 = 409,
  ) {
    super(message)
    this.name = "ImageResourceError"
  }
}

export class ImageResourceManager {
  private readonly resources = new Map<string, ImageResource>()
  private readonly rootDirectory: string
  private readonly registryPath: string
  private readonly resourceTTLMS: number
  private readonly maximumSourceBytes: number
  private readonly maximumResources: number
  private readonly now: () => number
  private readonly probeProcess: (command: string[], sourceFD: number) => Promise<string>
  private readonly previewProcess: PreviewOperation
  private readonly sweepTimer: ReturnType<typeof setInterval>
  private readonly ready: Promise<void>
  private persistence: Promise<void> = Promise.resolve()
  private mutationTail: Promise<void> = Promise.resolve()
  private stopped = false

  constructor(options: ImageResourceManagerOptions = {}) {
    this.registryPath = options.registryPath
      ?? (options.rootDirectory === undefined ? defaultImageRegistryPath() : join(options.rootDirectory, "image-resources.json"))
    this.rootDirectory = options.rootDirectory ?? dirname(this.registryPath)
    this.resourceTTLMS = options.resourceTTLMS ?? defaultResourceTTLMS
    this.maximumSourceBytes = options.maximumSourceBytes ?? defaultMaximumSourceBytes
    this.maximumResources = options.maximumResources ?? defaultMaximumResources
    this.now = options.now ?? Date.now
    this.probeProcess = options.probe ?? spawnFFprobe
    this.previewProcess = options.preview ?? spawnJPEGPreview
    this.ready = this.initialize()
    this.sweepTimer = setInterval(() => void this.sweep(), options.sweepIntervalMS ?? 30_000)
    this.sweepTimer.unref?.()
  }

  async createResource(input: {
    filePath: string
    title?: string
    accessibilityLabel?: string
    context: ImageExecutionContext
  }): Promise<ImageResourcePayload> {
    this.assertRunning()
    await this.sweep()
    const title = normalizedOptionalText(input.title, 120, "Image title")
    const accessibilityLabel = normalizedOptionalText(input.accessibilityLabel, 500, "Image accessibilityLabel")
    const source = await validateImageFile(input.filePath, undefined, this.maximumSourceBytes)
    const dimensions = await probeValidatedSource(
      source.canonicalPath,
      source.identity,
      source.file.mimeType,
      this.maximumSourceBytes,
      this.probeProcess,
    )
    const preview = await generateValidatedPreview(
      source.canonicalPath,
      source.identity,
      this.maximumSourceBytes,
      this.previewProcess,
      "image",
    )
    this.assertRunning()

    const resource = await this.mutateResources(async () => {
      this.assertRunning()
      const previousResources = new Map(this.resources)
      this.reserveResourceCapacity()
      const createdAt = this.now()
      const created: ImageResource = {
        id: opaqueID(),
        canonicalPath: source.canonicalPath,
        ...(title === undefined ? {} : { title }),
        ...(accessibilityLabel === undefined ? {} : { accessibilityLabel }),
        context: { ...input.context },
        identity: source.identity,
        ...dimensions,
        file: source.file,
        preview,
        expiresAt: createdAt + this.resourceTTLMS,
        lastAccessedAt: createdAt,
      }
      this.resources.set(created.id, created)
      try {
        await this.persistRegistry()
        this.assertRunning()
      } catch (error) {
        this.resources.clear()
        for (const [resourceID, previous] of previousResources) this.resources.set(resourceID, previous)
        await this.persistRegistry().catch(() => {})
        throw error
      }
      return created
    })
    return this.payload(resource)
  }

  async load(resourceID: string): Promise<ImageContent> {
    this.assertRunning()
    await this.sweep()
    const resource = this.resource(resourceID)
    const handle = await openValidatedFile(resource.canonicalPath, resource.identity, this.maximumSourceBytes)
    let bytes: Uint8Array
    try {
      bytes = new Uint8Array(await handle.readFile())
      const identity = sourceIdentity(await handle.stat())
      if (!sameSourceIdentity(identity, resource.identity) || bytes.byteLength !== resource.file.sizeBytes) {
        throw new ImageResourceError("Image file changed while it was being loaded")
      }
    } finally {
      await handle.close()
    }
    this.assertRunning()
    await this.touchResource(resource)
    return {
      bytes,
      contentType: resource.file.mimeType,
      sizeBytes: bytes.byteLength,
    }
  }

  async removeResource(resourceID: string): Promise<boolean> {
    await this.sweep()
    return this.mutateResources(async () => {
      const resource = this.resources.get(resourceID)
      if (!resource) return false
      this.resources.delete(resourceID)
      try {
        await this.persistRegistry()
      } catch (error) {
        this.resources.set(resourceID, resource)
        throw error
      }
      return true
    })
  }

  async stopAll(): Promise<void> {
    if (this.stopped) return
    this.stopped = true
    clearInterval(this.sweepTimer)
    await this.ready.catch(() => {})
    await this.mutationTail.catch(() => {})
    await this.persistence.catch(() => {})
    this.resources.clear()
  }

  private payload(resource: ImageResource): ImageResourcePayload {
    return {
      schemaVersion: 1,
      ...(resource.title === undefined ? {} : { title: resource.title }),
      ...(resource.accessibilityLabel === undefined ? {} : { accessibilityLabel: resource.accessibilityLabel }),
      resourceID: resource.id,
      contentPath: `${imageResourcePathPrefix}/${resource.id}/content`,
      expiresAt: new Date(resource.expiresAt).toISOString(),
      width: resource.width,
      height: resource.height,
      file: resource.file,
      preview: resource.preview,
    }
  }

  private resource(resourceID: string): ImageResource {
    if (!opaqueIDPattern.test(resourceID)) throw new ImageResourceError("Image resource not found", 404)
    const resource = this.resources.get(resourceID)
    if (!resource) throw new ImageResourceError("Image resource not found", 404)
    return resource
  }

  private async touchResource(resource: ImageResource): Promise<void> {
    await this.mutateResources(async () => {
      if (this.stopped || this.resources.get(resource.id) !== resource) return
      const previousLastAccessedAt = resource.lastAccessedAt
      const previousExpiresAt = resource.expiresAt
      const now = this.now()
      resource.lastAccessedAt = now
      resource.expiresAt = now + this.resourceTTLMS
      try {
        await this.persistRegistry()
      } catch (error) {
        resource.lastAccessedAt = previousLastAccessedAt
        resource.expiresAt = previousExpiresAt
        throw error
      }
    })
  }

  private async sweep(): Promise<void> {
    await this.ready
    const now = this.now()
    await this.mutateResources(async () => {
      const removed: ImageResource[] = []
      for (const [id, resource] of this.resources) {
        if (resource.expiresAt <= now) {
          this.resources.delete(id)
          removed.push(resource)
        }
      }
      if (removed.length === 0) return
      try {
        await this.persistRegistry()
      } catch (error) {
        for (const resource of removed) this.resources.set(resource.id, resource)
        throw error
      }
    })
  }

  private async initialize(): Promise<void> {
    await Promise.all([
      preparePrivateDirectory(this.rootDirectory),
      preparePrivateDirectory(dirname(this.registryPath)),
    ])
    let serialized: string
    try {
      serialized = await readFile(this.registryPath, "utf8")
      await chmod(this.registryPath, 0o600)
    } catch (error) {
      if (isFileNotFound(error)) return
      throw error
    }

    const parsed = parseRegistry(serialized)
    const now = this.now()
    const retained = parsed
      .filter((resource) => resource.expiresAt > now)
      .sort((left, right) => right.lastAccessedAt - left.lastAccessedAt)
      .slice(0, this.maximumResources)
    for (const resource of retained) this.resources.set(resource.id, resource)
    if (retained.length !== parsed.length) await this.persistRegistry()
  }

  private reserveResourceCapacity(): void {
    while (this.resources.size >= this.maximumResources) {
      const candidate = [...this.resources.values()]
        .sort((left, right) => left.lastAccessedAt - right.lastAccessedAt)[0]
      if (!candidate) throw new ImageResourceError("Too many image resources are active")
      this.resources.delete(candidate.id)
    }
  }

  private async mutateResources<T>(mutation: () => Promise<T>): Promise<T> {
    let release: () => void = () => {}
    const previous = this.mutationTail
    this.mutationTail = new Promise<void>((resolve) => {
      release = resolve
    })
    await previous.catch(() => {})
    try {
      return await mutation()
    } finally {
      release()
    }
  }

  private async persistRegistry(): Promise<void> {
    const resources = [...this.resources.values()]
      .sort((left, right) => right.lastAccessedAt - left.lastAccessedAt)
    const serialized = `${JSON.stringify({ schemaVersion: 1, resources }, null, 2)}\n`
    const write = this.persistence.catch(() => {}).then(async () => {
      const temporaryPath = `${this.registryPath}.${process.pid}.${opaqueID()}.tmp`
      try {
        await writeFile(temporaryPath, serialized, { encoding: "utf8", mode: 0o600 })
        await chmod(temporaryPath, 0o600)
        await syncPath(temporaryPath)
        await rename(temporaryPath, this.registryPath)
        await chmod(this.registryPath, 0o600)
        try {
          await syncPath(dirname(this.registryPath))
        } catch (error) {
          if (platform() !== "win32") throw error
        }
      } finally {
        await rm(temporaryPath, { force: true })
      }
    })
    this.persistence = write
    await write
  }

  private assertRunning(): void {
    if (this.stopped) throw new ImageResourceError("Image service is stopped", 500)
  }
}

export function defaultImageRegistryPath(openCodePort?: number): string {
  const stateDirectory = process.env.XDG_STATE_HOME ?? join(homedir(), ".local", "state")
  return join(stateDirectory, "opencode", "openclient", `image-resources-${openCodePort ?? "default"}.json`)
}

async function validateImageFile(
  filePath: string,
  expectedIdentity: SourceIdentity | undefined,
  maximumSourceBytes: number,
): Promise<{
  canonicalPath: string
  identity: SourceIdentity
  file: ImageResourcePayload["file"]
}> {
  if (!isAbsolute(filePath)) throw new ImageResourceError("Image filePath must be an absolute path")
  if (imageMimeType(filePath) === undefined) {
    throw new ImageResourceError("Image filePath must reference a JPEG, PNG, or WebP file")
  }

  try {
    const canonicalPath = await realpath(filePath)
    const mimeType = imageMimeType(canonicalPath)
    if (mimeType === undefined) throw new ImageResourceError("Image filePath must resolve to a JPEG, PNG, or WebP file")
    await access(canonicalPath, fsConstants.R_OK)
    const fileStat = await stat(canonicalPath)
    if (!fileStat.isFile()) throw new ImageResourceError("Image filePath must reference a regular file")
    if (!Number.isSafeInteger(fileStat.size)) throw new ImageResourceError("Image file is too large")
    if (fileStat.size <= 0 || fileStat.size > maximumSourceBytes) {
      throw new ImageResourceError("Image file exceeds the supported size limit")
    }
    const identity = sourceIdentity(fileStat)
    if (expectedIdentity && !sameSourceIdentity(identity, expectedIdentity)) {
      throw new ImageResourceError("Image file changed after the resource was created")
    }
    return {
      canonicalPath,
      identity,
      file: {
        name: basename(canonicalPath),
        sizeBytes: fileStat.size,
        modifiedAt: fileStat.mtime.toISOString(),
        mimeType,
      },
    }
  } catch (error) {
    if (error instanceof ImageResourceError) throw error
    throw new ImageResourceError("Image filePath must reference a readable regular JPEG, PNG, or WebP file")
  }
}

async function openValidatedFile(
  canonicalPath: string,
  expectedIdentity: SourceIdentity,
  maximumSourceBytes: number,
) {
  try {
    const handle = await open(canonicalPath, "r")
    try {
      const fileStat = await handle.stat()
      if (!fileStat.isFile()
        || fileStat.size <= 0
        || fileStat.size > maximumSourceBytes
        || !sameSourceIdentity(sourceIdentity(fileStat), expectedIdentity)) {
        throw new ImageResourceError("Image file changed after the resource was created")
      }
      return handle
    } catch (error) {
      await handle.close()
      throw error
    }
  } catch (error) {
    if (error instanceof ImageResourceError) throw error
    throw new ImageResourceError("Image source is no longer readable")
  }
}

async function probeValidatedSource(
  canonicalPath: string,
  expectedIdentity: SourceIdentity,
  mimeType: ImageMimeType,
  maximumSourceBytes: number,
  probe: (command: string[], sourceFD: number) => Promise<string>,
): Promise<{ width: number; height: number }> {
  if (platform() === "win32") {
    throw new ImageResourceError("Secure image inspection is not supported on Windows", 500)
  }
  const handle = await openValidatedFile(canonicalPath, expectedIdentity, maximumSourceBytes)
  try {
    let output: string
    try {
      output = await probe([
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,width,height",
        "-of", "json",
        "/dev/fd/3",
      ], handle.fd)
    } catch (error) {
      if (error instanceof ImageResourceError) throw error
      throw new ImageResourceError("Unable to inspect the image source", 500)
    }
    assertUnchanged(await handle.stat(), expectedIdentity, "Image file changed while the resource was created")
    return parseImageProbe(output, mimeType)
  } finally {
    await handle.close()
  }
}

async function generateValidatedPreview(
  canonicalPath: string,
  expectedIdentity: SourceIdentity,
  maximumSourceBytes: number,
  preview: PreviewOperation,
  mediaName: string,
): Promise<VisualPreview> {
  if (platform() === "win32") {
    throw new ImageResourceError(`Secure ${mediaName} preview generation is not supported on Windows`, 500)
  }
  const handle = await openValidatedFile(canonicalPath, expectedIdentity, maximumSourceBytes)
  try {
    let bytes: Uint8Array
    try {
      bytes = await preview(previewCommand(), handle.fd)
    } catch (error) {
      if (error instanceof ImageResourceError) throw error
      throw new ImageResourceError(`Unable to generate the ${mediaName} preview`, 500)
    }
    assertUnchanged(await handle.stat(), expectedIdentity, `Image file changed while the resource was created`)
    try {
      return previewFromJPEG(bytes)
    } catch (error) {
      throw new ImageResourceError(error instanceof Error ? error.message : "Invalid image preview")
    }
  } finally {
    await handle.close()
  }
}

function parseImageProbe(serialized: string, mimeType: ImageMimeType): { width: number; height: number } {
  let value: unknown
  try {
    value = JSON.parse(serialized)
  } catch {
    throw new ImageResourceError("Unable to read image source metadata")
  }
  if (!isRecord(value) || !Array.isArray(value.streams) || !isRecord(value.streams[0])) {
    throw new ImageResourceError("Image file must contain a readable image stream")
  }
  const stream = value.streams[0]
  if (!isPositiveSafeInteger(stream.width) || !isPositiveSafeInteger(stream.height)) {
    throw new ImageResourceError("Unable to read image source dimensions")
  }
  const expectedCodecs: Record<ImageMimeType, string[]> = {
    "image/jpeg": ["mjpeg"],
    "image/png": ["png"],
    "image/webp": ["webp"],
  }
  if (typeof stream.codec_name !== "string" || !expectedCodecs[mimeType].includes(stream.codec_name)) {
    throw new ImageResourceError("Image contents do not match the file extension")
  }
  return { width: stream.width, height: stream.height }
}

async function spawnFFprobe(command: string[], sourceFD: number): Promise<string> {
  let process: ReturnType<typeof Bun.spawn>
  try {
    process = Bun.spawn({
      cmd: command,
      stdio: ["ignore", "pipe", "pipe", sourceFD],
      timeout: 15_000,
      killSignal: "SIGKILL",
    })
  } catch {
    throw new ImageResourceError("Unable to start ffprobe", 500)
  }
  if (typeof process.stdout === "number" || process.stdout === undefined
    || typeof process.stderr === "number" || process.stderr === undefined) {
    process.kill("SIGKILL")
    throw new ImageResourceError("Unable to capture ffprobe output", 500)
  }
  const [output, errorOutput, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ])
  if (exitCode !== 0) {
    throw new ImageResourceError(errorOutput.trim() === ""
      ? "Unable to inspect the image source"
      : "Image file must contain a readable image stream")
  }
  return output
}

function parseRegistry(serialized: string): ImageResource[] {
  let value: unknown
  try {
    value = JSON.parse(serialized)
  } catch {
    return []
  }
  if (!isRecord(value) || value.schemaVersion !== 1 || !Array.isArray(value.resources)) return []
  return value.resources.flatMap((resource) => {
    if (!isRecord(resource)) return []
    const canonicalMimeType = typeof resource.canonicalPath === "string"
      ? imageMimeType(resource.canonicalPath)
      : undefined
    if (typeof resource.id !== "string" || !opaqueIDPattern.test(resource.id)
      || typeof resource.canonicalPath !== "string" || !isAbsolute(resource.canonicalPath)
      || canonicalMimeType === undefined
      || !isOptionalBoundedText(resource.title, 120)
      || !isOptionalBoundedText(resource.accessibilityLabel, 500)
      || !isExecutionContext(resource.context)
      || !isSourceIdentity(resource.identity)
      || !isPositiveSafeInteger(resource.width)
      || !isPositiveSafeInteger(resource.height)
      || !isImageFile(resource.file)
      || !isFiniteTimestamp(resource.expiresAt)
      || !isFiniteTimestamp(resource.lastAccessedAt)) return []
    const preview = parseVisualPreview(resource.preview)
    if (!preview
      || resource.file.mimeType !== canonicalMimeType
      || resource.file.name !== basename(resource.canonicalPath)
      || resource.file.sizeBytes !== resource.identity.size
      || !isISODateForTimestamp(resource.file.modifiedAt, resource.identity.modifiedAtMS)) return []
    return [{
      id: resource.id,
      canonicalPath: resource.canonicalPath,
      ...(resource.title === undefined ? {} : { title: resource.title }),
      ...(resource.accessibilityLabel === undefined ? {} : { accessibilityLabel: resource.accessibilityLabel }),
      context: resource.context,
      identity: resource.identity,
      width: resource.width,
      height: resource.height,
      file: resource.file,
      preview,
      expiresAt: resource.expiresAt,
      lastAccessedAt: resource.lastAccessedAt,
    }]
  })
}

function imageMimeType(path: string): ImageMimeType | undefined {
  switch (extname(path).toLowerCase()) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg"
    case ".png":
      return "image/png"
    case ".webp":
      return "image/webp"
    default:
      return undefined
  }
}

function normalizedOptionalText(value: string | undefined, maximumLength: number, field: string): string | undefined {
  if (value === undefined) return undefined
  const normalized = value.trim()
  if (normalized.length === 0 || Array.from(normalized).length > maximumLength) {
    throw new ImageResourceError(`${field} must contain at most ${maximumLength} characters`)
  }
  return normalized
}

function sourceIdentity(fileStat: Stats): SourceIdentity {
  return {
    device: fileStat.dev,
    inode: fileStat.ino,
    size: fileStat.size,
    modifiedAtMS: fileStat.mtimeMs,
  }
}

function sameSourceIdentity(left: SourceIdentity, right: SourceIdentity): boolean {
  return left.device === right.device
    && left.inode === right.inode
    && left.size === right.size
    && left.modifiedAtMS === right.modifiedAtMS
}

function assertUnchanged(fileStat: Stats, expectedIdentity: SourceIdentity, message: string): void {
  if (!sameSourceIdentity(sourceIdentity(fileStat), expectedIdentity)) throw new ImageResourceError(message)
}

async function preparePrivateDirectory(path: string): Promise<void> {
  await mkdir(path, { recursive: true, mode: 0o700 })
  await chmod(path, 0o700)
}

async function syncPath(path: string): Promise<void> {
  const handle = await open(path, "r")
  try {
    await handle.sync()
  } finally {
    await handle.close()
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function isExecutionContext(value: unknown): value is ImageExecutionContext {
  return isRecord(value)
    && typeof value.clientID === "string"
    && typeof value.sessionID === "string"
    && typeof value.messageID === "string"
    && typeof value.agent === "string"
    && typeof value.directory === "string"
    && typeof value.worktree === "string"
}

function isSourceIdentity(value: unknown): value is SourceIdentity {
  return isRecord(value)
    && isSafeNonnegativeInteger(value.device)
    && isSafeNonnegativeInteger(value.inode)
    && isSafeNonnegativeInteger(value.size)
    && isFiniteTimestamp(value.modifiedAtMS)
}

function isImageFile(value: unknown): value is ImageResourcePayload["file"] {
  return isRecord(value)
    && typeof value.name === "string"
    && isSafeNonnegativeInteger(value.sizeBytes)
    && typeof value.modifiedAt === "string"
    && (value.mimeType === "image/jpeg" || value.mimeType === "image/png" || value.mimeType === "image/webp")
}

function isOptionalBoundedText(value: unknown, maximumLength: number): value is string | undefined {
  return value === undefined
    || (typeof value === "string" && value.trim() === value && value.length > 0 && Array.from(value).length <= maximumLength)
}

function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
}

function isSafeNonnegativeInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
}

function isFiniteTimestamp(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
}

function isISODateForTimestamp(value: string, timestamp: number): boolean {
  try {
    return new Date(timestamp).toISOString() === value
  } catch {
    return false
  }
}

function isFileNotFound(error: unknown): boolean {
  return isRecord(error) && error.code === "ENOENT"
}

function opaqueID(): string {
  return randomBytes(24).toString("base64url")
}
