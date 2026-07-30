import { constants as fsConstants, type Stats } from "node:fs"
import { access, chmod, mkdir, open, readFile, realpath, rename, rm, stat, writeFile } from "node:fs/promises"
import { basename, dirname, extname, isAbsolute, join } from "node:path"
import { homedir, platform, tmpdir } from "node:os"
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

export const videoToolID = "openclient_visual_video"
export const videoRendererID = "openclient.video.v1"

const videoResourcePathPrefix = "/openclient/v1/video/resources"
const videoStreamPathPrefix = "/openclient/v1/video/streams"
const opaqueIDPattern = /^[A-Za-z0-9_-]{32}$/
const mediaAssetPattern = /^(?:init\.mp4|segment-\d{6}\.m4s)$/

export type VideoExecutionContext = {
  clientID: string
  sessionID: string
  messageID: string
  agent: string
  directory: string
  worktree: string
}

export type VideoResourcePayload = JsonObject & {
  schemaVersion: 1
  title?: string
  resourceID: string
  startPath: string
  stopPath: string
  expiresAt: string
  width: number
  height: number
  rotation: number
  duration: number
  cover: VisualPreview
  file: {
    name: string
    sizeBytes: number
    modifiedAt: string
    mimeType: "video/mp4"
  }
}

export type VideoStartResult = {
  streamID: string
  hlsPath: string
  stopPath: string
}

export type VideoAsset = {
  path: string
  contentType: string
  cacheControl: string
}

export interface VideoProcess {
  exited: Promise<number>
  kill(signal?: NodeJS.Signals | number): void
}

export type VideoResourceManagerOptions = {
  rootDirectory?: string
  registryPath?: string
  resourceTTLMS?: number
  streamTTLMS?: number
  readinessTimeoutMS?: number
  readinessPollMS?: number
  sweepIntervalMS?: number
  maximumSourceBytes?: number
  maximumActiveStreams?: number
  maximumResources?: number
  now?: () => number
  spawn?: (command: string[], sourceFD?: number) => VideoProcess
  probe?: (command: string[], sourceFD: number) => Promise<string>
  preview?: PreviewOperation
}

type SourceIdentity = {
  device: number
  inode: number
  size: number
  modifiedAtMS: number
}

type VideoResource = {
  id: string
  canonicalPath: string
  title?: string
  context: VideoExecutionContext
  identity: SourceIdentity
  sourceMetadata?: VideoSourceMetadata
  cover: VisualPreview
  file: VideoResourcePayload["file"]
  expiresAt: number
  lastAccessedAt: number
  streamIDs: Set<string>
  starting?: Promise<VideoStartResult>
}

type PersistedVideoResource = Omit<VideoResource, "streamIDs" | "starting">

type VideoSourceMetadata = Pick<VideoResourcePayload, "width" | "height" | "rotation" | "duration">

type VideoStream = {
  id: string
  resourceID: string
  directory: string
  process: VideoProcess
  processExited: boolean
  expiresAt: number
}

export class VideoResourceError extends Error {
  constructor(
    message: string,
    readonly status: 404 | 409 | 500 = 409,
  ) {
    super(message)
    this.name = "VideoResourceError"
  }
}

export class VideoResourceManager {
  private readonly resources = new Map<string, VideoResource>()
  private readonly streams = new Map<string, VideoStream>()
  private readonly rootDirectory: string
  private readonly registryPath: string
  private readonly resourceTTLMS: number
  private readonly streamTTLMS: number
  private readonly readinessTimeoutMS: number
  private readonly readinessPollMS: number
  private readonly maximumSourceBytes: number
  private readonly maximumActiveStreams: number
  private readonly maximumResources: number
  private readonly now: () => number
  private readonly spawnProcess: (command: string[], sourceFD?: number) => VideoProcess
  private readonly probeProcess: (command: string[], sourceFD: number) => Promise<string>
  private readonly previewProcess: PreviewOperation
  private readonly sweepTimer: ReturnType<typeof setInterval>
  private readonly ready: Promise<void>
  private persistence: Promise<void> = Promise.resolve()
  private mutationTail: Promise<void> = Promise.resolve()
  private startingCount = 0
  private stopped = false

  constructor(options: VideoResourceManagerOptions = {}) {
    this.rootDirectory = options.rootDirectory ?? join(tmpdir(), `openclient-video-${opaqueID()}`)
    this.registryPath = options.registryPath ?? defaultRegistryPath()
    this.resourceTTLMS = options.resourceTTLMS ?? 30 * 24 * 60 * 60 * 1_000
    this.streamTTLMS = options.streamTTLMS ?? 10 * 60 * 1_000
    this.readinessTimeoutMS = options.readinessTimeoutMS ?? 15_000
    this.readinessPollMS = options.readinessPollMS ?? 50
    this.maximumSourceBytes = options.maximumSourceBytes ?? 20 * 1_024 * 1_024 * 1_024
    this.maximumActiveStreams = options.maximumActiveStreams ?? 3
    this.maximumResources = options.maximumResources ?? 128
    this.now = options.now ?? Date.now
    this.spawnProcess = options.spawn ?? spawnFFmpeg
    this.probeProcess = options.probe ?? spawnFFprobe
    this.previewProcess = options.preview ?? spawnJPEGPreview
    this.ready = this.initialize()
    this.sweepTimer = setInterval(() => void this.sweep(), options.sweepIntervalMS ?? 30_000)
    this.sweepTimer.unref?.()
  }

  async createResource(input: {
    filePath: string
    title?: string
    context: VideoExecutionContext
  }): Promise<VideoResourcePayload> {
    this.assertRunning()
    await this.sweep()
    const source = await validateVideoFile(input.filePath, undefined, this.maximumSourceBytes)
    const sourceMetadata = await probeValidatedSource(
      source.canonicalPath,
      source.identity,
      this.maximumSourceBytes,
      this.probeProcess,
    )
    const cover = await previewValidatedSource(
      source.canonicalPath,
      source.identity,
      this.maximumSourceBytes,
      this.previewProcess,
    )
    this.assertRunning()

    const resource = await this.mutateResources(async () => {
      this.assertRunning()
      const previousResources = new Map(this.resources)
      this.reserveResourceCapacity()
      const id = opaqueID()
      const createdAt = this.now()
      const created: VideoResource = {
        id,
        canonicalPath: source.canonicalPath,
        ...(input.title === undefined ? {} : { title: input.title }),
        context: { ...input.context },
        identity: source.identity,
        sourceMetadata,
        cover,
        file: source.file,
        expiresAt: createdAt + this.resourceTTLMS,
        lastAccessedAt: createdAt,
        streamIDs: new Set(),
      }
      this.resources.set(id, created)
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
    const streamPath = `${videoResourcePathPrefix}/${resource.id}/stream`
    return {
      schemaVersion: 1,
      ...(input.title === undefined ? {} : { title: input.title }),
      resourceID: resource.id,
      startPath: streamPath,
      stopPath: streamPath,
      expiresAt: new Date(resource.expiresAt).toISOString(),
      ...sourceMetadata,
      cover,
      file: source.file,
    }
  }

  async start(resourceID: string): Promise<VideoStartResult> {
    this.assertRunning()
    await this.sweep()
    const resource = this.resource(resourceID)
    if (resource.starting) return resource.starting
    if (this.streams.size + this.startingCount >= this.maximumActiveStreams) {
      throw new VideoResourceError("Too many video streams are active", 409)
    }

    this.startingCount += 1
    const starting = this.startNewStream(resource)
    resource.starting = starting
    try {
      return await starting
    } finally {
      this.startingCount -= 1
      if (resource.starting === starting) resource.starting = undefined
    }
  }

  async stop(resourceID: string): Promise<boolean> {
    await this.sweep()
    const resource = this.resources.get(resourceID)
    if (!resource) return false
    if (resource.starting) {
      try {
        await resource.starting
      } catch {
        // A failed start has already cleaned its partial stream.
      }
    }
    await Promise.all([...resource.streamIDs].map((streamID) => this.removeStream(streamID)))
    await this.touchResource(resource)
    return true
  }

  async stopStream(streamID: string): Promise<boolean> {
    await this.sweep()
    if (!opaqueIDPattern.test(streamID) || !this.streams.has(streamID)) return false
    await this.removeStream(streamID)
    return true
  }

  async removeResource(resourceID: string): Promise<boolean> {
    await this.sweep()
    return this.mutateResources(async () => {
      const resource = this.resources.get(resourceID)
      if (!resource || resource.starting || resource.streamIDs.size > 0) return false
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

  async asset(streamID: string, fileName: string): Promise<VideoAsset | undefined> {
    await this.sweep()
    if (!opaqueIDPattern.test(streamID)) return undefined
    if (fileName !== "playlist.m3u8" && !mediaAssetPattern.test(fileName)) return undefined
    const stream = this.streams.get(streamID)
    if (!stream) return undefined
    const resource = this.resources.get(stream.resourceID)
    if (!resource) return undefined
    stream.expiresAt = this.now() + this.streamTTLMS
    const path = join(stream.directory, fileName)
    try {
      const fileStat = await stat(path)
      if (!fileStat.isFile()) return undefined
    } catch {
      return undefined
    }
    return {
      path,
      contentType: fileName === "playlist.m3u8"
        ? "application/vnd.apple.mpegurl"
        : fileName === "init.mp4" ? "video/mp4" : "video/iso.segment",
      cacheControl: fileName === "playlist.m3u8" ? "no-store" : "private, max-age=600, immutable",
    }
  }

  async stopAll(): Promise<void> {
    if (this.stopped) return
    this.stopped = true
    clearInterval(this.sweepTimer)
    await this.ready.catch(() => {})
    const starts = [...this.resources.values()].flatMap((resource) => resource.starting ? [resource.starting] : [])
    await Promise.allSettled(starts)
    const streamIDs = [...this.streams.keys()]
    await Promise.all(streamIDs.map((id) => this.removeStream(id)))
    await this.mutationTail.catch(() => {})
    await this.persistence.catch(() => {})
    this.resources.clear()
    await rm(this.rootDirectory, { recursive: true, force: true })
  }

  private async startNewStream(resource: VideoResource): Promise<VideoStartResult> {
    const sourceHandle = await openValidatedSource(resource, this.maximumSourceBytes)
    this.assertRunning()
    const streamID = opaqueID()
    const directory = join(this.rootDirectory, streamID)
    const playlistPath = join(directory, "playlist.m3u8")
    await mkdir(directory, { recursive: true, mode: 0o700 })

    let process: VideoProcess
    try {
      const inheritedSourceFD = platform() === "win32" ? undefined : sourceHandle.fd
      process = this.spawnProcess([
        "ffmpeg",
        "-nostdin",
        "-hide_banner",
        "-loglevel", "error",
        "-y",
        "-i", inheritedSourceFD === undefined ? resource.canonicalPath : "/dev/fd/3",
        "-map", "0:v:0?",
        "-map", "0:a:0?",
        "-c", "copy",
        "-f", "hls",
        "-hls_segment_type", "fmp4",
        "-hls_time", "4",
        "-hls_list_size", "0",
        "-hls_playlist_type", "event",
        "-hls_flags", "temp_file",
        "-hls_fmp4_init_filename", "init.mp4",
        "-hls_segment_filename", join(directory, "segment-%06d.m4s"),
        playlistPath,
      ], inheritedSourceFD)
    } catch {
      await rm(directory, { recursive: true, force: true })
      throw new VideoResourceError("Unable to start the video stream", 500)
    } finally {
      await sourceHandle.close()
    }

    const stream: VideoStream = {
      id: streamID,
      resourceID: resource.id,
      directory,
      process,
      processExited: false,
      expiresAt: this.now() + this.streamTTLMS,
    }
    this.streams.set(streamID, stream)
    resource.streamIDs.add(streamID)
    void process.exited.then(() => {
      stream.processExited = true
    }, () => {
      stream.processExited = true
    })

    try {
      await this.waitUntilReady(stream, playlistPath)
      stream.expiresAt = this.now() + this.streamTTLMS
      await this.touchResource(resource)
      return this.startResult(streamID)
    } catch (error) {
      await this.removeStream(streamID)
      if (error instanceof VideoResourceError) throw error
      throw new VideoResourceError("The MP4 is not compatible with stream-copy HLS", 409)
    }
  }

  private async waitUntilReady(stream: VideoStream, playlistPath: string): Promise<void> {
    const deadline = this.now() + this.readinessTimeoutMS
    while (this.now() <= deadline) {
      this.assertRunning()
      try {
        const playlist = await readFile(playlistPath, "utf8")
        const firstSegment = playlist.split(/\r?\n/).find((line) => mediaAssetPattern.test(line.trim()))?.trim()
        if (firstSegment) {
          const segmentStat = await stat(join(stream.directory, firstSegment))
          if (segmentStat.isFile() && segmentStat.size > 0) return
        }
      } catch {
        // ffmpeg publishes the files asynchronously.
      }
      if (stream.processExited) throw new VideoResourceError("The MP4 is not compatible with stream-copy HLS", 409)
      await Bun.sleep(this.readinessPollMS)
    }
    throw new VideoResourceError("Timed out preparing the video stream", 409)
  }

  private async sweep(): Promise<void> {
    await this.ready
    const now = this.now()
    const expiredStreams = [...this.streams.values()]
      .filter((stream) => stream.expiresAt <= now)
      .map((stream) => stream.id)
    await Promise.all(expiredStreams.map((id) => this.removeStream(id)))
    await this.mutateResources(async () => {
      const removed: VideoResource[] = []
      for (const [id, resource] of this.resources) {
        if (resource.expiresAt <= now && resource.starting === undefined && resource.streamIDs.size === 0) {
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

  private async removeStream(streamID: string): Promise<void> {
    const stream = this.streams.get(streamID)
    if (!stream) return
    this.streams.delete(streamID)
    const resource = this.resources.get(stream.resourceID)
    resource?.streamIDs.delete(streamID)
    if (!stream.processExited) {
      try {
        stream.process.kill("SIGTERM")
      } catch {
        // The process may have exited between the readiness check and cleanup.
      }
      await Promise.race([stream.process.exited.catch(() => -1), Bun.sleep(1_000)])
      if (!stream.processExited) {
        try {
          stream.process.kill("SIGKILL")
        } catch {
          // Process cleanup is best effort after SIGTERM.
        }
        await Promise.race([stream.process.exited.catch(() => -1), Bun.sleep(1_000)])
      }
    }
    await rm(stream.directory, { recursive: true, force: true })
  }

  private resource(resourceID: string): VideoResource {
    if (!opaqueIDPattern.test(resourceID)) throw new VideoResourceError("Video resource not found", 404)
    const resource = this.resources.get(resourceID)
    if (!resource) throw new VideoResourceError("Video resource not found", 404)
    return resource
  }

  private async touchResource(resource: VideoResource): Promise<void> {
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
    for (const resource of retained) {
      this.resources.set(resource.id, { ...resource, streamIDs: new Set() })
    }
    if (retained.length !== parsed.length) await this.persistRegistry()
  }

  private reserveResourceCapacity(): void {
    while (this.resources.size >= this.maximumResources) {
      const candidate = [...this.resources.values()]
        .filter((resource) => resource.starting === undefined && resource.streamIDs.size === 0)
        .sort((left, right) => left.lastAccessedAt - right.lastAccessedAt)[0]
      if (!candidate) throw new VideoResourceError("Too many video resources are active", 409)
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
    const resources: PersistedVideoResource[] = [...this.resources.values()]
      .map(({ streamIDs: _streamIDs, starting: _starting, ...resource }) => resource)
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

  private startResult(streamID: string): VideoStartResult {
    return {
      streamID,
      hlsPath: `${videoStreamPathPrefix}/${streamID}/playlist.m3u8`,
      stopPath: `${videoStreamPathPrefix}/${streamID}`,
    }
  }

  private assertRunning(): void {
    if (this.stopped) throw new VideoResourceError("Video service is stopped", 500)
  }
}

async function validateVideoFile(
  filePath: string,
  expectedIdentity: SourceIdentity | undefined,
  maximumSourceBytes: number,
): Promise<{
  canonicalPath: string
  identity: SourceIdentity
  file: VideoResourcePayload["file"]
}> {
  if (!isAbsolute(filePath)) throw new VideoResourceError("Video filePath must be an absolute path")
  if (extname(filePath).toLowerCase() !== ".mp4") throw new VideoResourceError("Video filePath must reference an MP4 file")

  let canonicalPath: string
  try {
    canonicalPath = await realpath(filePath)
    if (extname(canonicalPath).toLowerCase() !== ".mp4") {
      throw new VideoResourceError("Video filePath must resolve to an MP4 file")
    }
    await access(canonicalPath, fsConstants.R_OK)
    const fileStat = await stat(canonicalPath)
    if (!fileStat.isFile()) throw new VideoResourceError("Video filePath must reference a regular file")
    if (!Number.isSafeInteger(fileStat.size)) throw new VideoResourceError("Video file is too large")
    if (fileStat.size <= 0 || fileStat.size > maximumSourceBytes) {
      throw new VideoResourceError("Video file exceeds the supported size limit")
    }
    const identity = sourceIdentity(fileStat)
    if (expectedIdentity && !sameSourceIdentity(identity, expectedIdentity)) {
      throw new VideoResourceError("Video file changed after the resource was created")
    }
    return {
      canonicalPath,
      identity,
      file: {
        name: basename(canonicalPath),
        sizeBytes: fileStat.size,
        modifiedAt: fileStat.mtime.toISOString(),
        mimeType: "video/mp4",
      },
    }
  } catch (error) {
    if (error instanceof VideoResourceError) throw error
    throw new VideoResourceError("Video filePath must reference a readable regular MP4 file")
  }
}

async function openValidatedSource(resource: VideoResource, maximumSourceBytes: number) {
  return openValidatedFile(resource.canonicalPath, resource.identity, maximumSourceBytes)
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
      const identity = sourceIdentity(fileStat)
      if (!fileStat.isFile()
        || fileStat.size <= 0
        || fileStat.size > maximumSourceBytes
        || !sameSourceIdentity(identity, expectedIdentity)) {
        throw new VideoResourceError("Video file changed after the resource was created")
      }
      return handle
    } catch (error) {
      await handle.close()
      throw error
    }
  } catch (error) {
    if (error instanceof VideoResourceError) throw error
    throw new VideoResourceError("Video filePath must reference a readable regular MP4 file")
  }
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

async function preparePrivateDirectory(path: string): Promise<void> {
  await mkdir(path, { recursive: true, mode: 0o700 })
  await chmod(path, 0o700)
}

export function defaultVideoRegistryPath(openCodePort?: number): string {
  const stateDirectory = process.env.XDG_STATE_HOME ?? join(homedir(), ".local", "state")
  return join(stateDirectory, "opencode", "openclient", `video-resources-${openCodePort ?? "default"}.json`)
}

function defaultRegistryPath(): string {
  return defaultVideoRegistryPath()
}

async function syncPath(path: string): Promise<void> {
  const handle = await open(path, "r")
  try {
    await handle.sync()
  } finally {
    await handle.close()
  }
}

function parseRegistry(serialized: string): PersistedVideoResource[] {
  let value: unknown
  try {
    value = JSON.parse(serialized)
  } catch {
    return []
  }
  if (!isRecord(value) || value.schemaVersion !== 1 || !Array.isArray(value.resources)) return []
  return value.resources.flatMap((resource) => {
    if (!isRecord(resource)
      || typeof resource.id !== "string" || !opaqueIDPattern.test(resource.id)
      || typeof resource.canonicalPath !== "string" || !isAbsolute(resource.canonicalPath)
      || extname(resource.canonicalPath).toLowerCase() !== ".mp4"
      || !isOptionalString(resource.title)
      || !isExecutionContext(resource.context)
      || !isSourceIdentity(resource.identity)
      || (resource.sourceMetadata !== undefined && !isVideoSourceMetadata(resource.sourceMetadata))
      || parseVisualPreview(resource.cover) === undefined
      || !isVideoFile(resource.file)
      || !isFiniteTimestamp(resource.expiresAt)
      || !isFiniteTimestamp(resource.lastAccessedAt)) return []
    const cover = parseVisualPreview(resource.cover)
    if (!cover) return []
    return [{
      id: resource.id,
      canonicalPath: resource.canonicalPath,
      ...(resource.title === undefined ? {} : { title: resource.title }),
      context: resource.context,
      identity: resource.identity,
      ...(resource.sourceMetadata === undefined ? {} : { sourceMetadata: resource.sourceMetadata }),
      cover,
      file: resource.file,
      expiresAt: resource.expiresAt,
      lastAccessedAt: resource.lastAccessedAt,
    }]
  })
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function isOptionalString(value: unknown): value is string | undefined {
  return value === undefined || typeof value === "string"
}

function isExecutionContext(value: unknown): value is VideoExecutionContext {
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

function isVideoFile(value: unknown): value is VideoResourcePayload["file"] {
  return isRecord(value)
    && typeof value.name === "string"
    && isSafeNonnegativeInteger(value.sizeBytes)
    && typeof value.modifiedAt === "string"
    && value.mimeType === "video/mp4"
}

function isVideoSourceMetadata(value: unknown): value is VideoSourceMetadata {
  return isRecord(value)
    && isPositiveSafeInteger(value.width)
    && isPositiveSafeInteger(value.height)
    && isSafeNonnegativeInteger(value.rotation)
    && value.rotation < 360
    && value.rotation % 90 === 0
    && typeof value.duration === "number"
    && Number.isFinite(value.duration)
    && value.duration >= 0
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

function isFileNotFound(error: unknown): boolean {
  return isRecord(error) && error.code === "ENOENT"
}

function opaqueID(): string {
  return randomBytes(24).toString("base64url")
}

function spawnFFmpeg(command: string[], sourceFD?: number): VideoProcess {
  if (sourceFD === undefined) {
    return Bun.spawn({
      cmd: command,
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
    })
  }
  return Bun.spawn({
    cmd: command,
    stdio: ["ignore", "ignore", "ignore", sourceFD],
  })
}

async function probeValidatedSource(
  canonicalPath: string,
  expectedIdentity: SourceIdentity,
  maximumSourceBytes: number,
  probe: (command: string[], sourceFD: number) => Promise<string>,
): Promise<VideoSourceMetadata> {
  if (platform() === "win32") {
    throw new VideoResourceError("Secure video metadata inspection is not supported on Windows", 500)
  }
  const sourceHandle = await openValidatedFile(canonicalPath, expectedIdentity, maximumSourceBytes)
  try {
    let output: string
    try {
      output = await probe([
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,duration:stream_tags=rotate:stream_side_data=rotation:format=duration",
        "-of", "json",
        "/dev/fd/3",
      ], sourceHandle.fd)
    } catch (error) {
      if (error instanceof VideoResourceError) throw error
      throw new VideoResourceError("Unable to inspect the video source", 500)
    }
    const currentIdentity = sourceIdentity(await sourceHandle.stat())
    if (!sameSourceIdentity(currentIdentity, expectedIdentity)) {
      throw new VideoResourceError("Video file changed while the resource was created")
    }
    return parseFFprobeMetadata(output)
  } finally {
    await sourceHandle.close()
  }
}

async function previewValidatedSource(
  canonicalPath: string,
  expectedIdentity: SourceIdentity,
  maximumSourceBytes: number,
  preview: PreviewOperation,
): Promise<VisualPreview> {
  if (platform() === "win32") {
    throw new VideoResourceError("Secure video cover generation is not supported on Windows", 500)
  }
  const sourceHandle = await openValidatedFile(canonicalPath, expectedIdentity, maximumSourceBytes)
  try {
    let bytes: Uint8Array
    try {
      bytes = await preview(previewCommand(), sourceHandle.fd)
    } catch (error) {
      if (error instanceof VideoResourceError) throw error
      throw new VideoResourceError("Unable to generate the video cover", 500)
    }
    const currentIdentity = sourceIdentity(await sourceHandle.stat())
    if (!sameSourceIdentity(currentIdentity, expectedIdentity)) {
      throw new VideoResourceError("Video file changed while the resource was created")
    }
    try {
      return previewFromJPEG(bytes)
    } catch (error) {
      throw new VideoResourceError(error instanceof Error ? error.message : "Invalid video cover")
    }
  } finally {
    await sourceHandle.close()
  }
}

function parseFFprobeMetadata(serialized: string): VideoSourceMetadata {
  let value: unknown
  try {
    value = JSON.parse(serialized)
  } catch {
    throw new VideoResourceError("Unable to read video source metadata")
  }
  if (!isRecord(value) || !Array.isArray(value.streams) || !isRecord(value.streams[0])) {
    throw new VideoResourceError("Video file must contain a readable video stream")
  }
  const stream = value.streams[0]
  const format = isRecord(value.format) ? value.format : undefined
  const width = stream.width
  const height = stream.height
  const duration = parseFiniteNumber(format?.duration) ?? parseFiniteNumber(stream.duration)
  if (!isPositiveSafeInteger(width) || !isPositiveSafeInteger(height) || duration === undefined || duration < 0) {
    throw new VideoResourceError("Unable to read video source metadata")
  }

  const tags = isRecord(stream.tags) ? stream.tags : undefined
  const sideData = Array.isArray(stream.side_data_list)
    ? stream.side_data_list.find((item) => isRecord(item) && parseFiniteNumber(item.rotation) !== undefined)
    : undefined
  const sideDataRotation = isRecord(sideData) ? parseFiniteNumber(sideData.rotation) : undefined
  const taggedRotation = parseFiniteNumber(tags?.rotate)
  const rawClockwiseRotation = sideDataRotation === undefined ? (taggedRotation ?? 0) : -sideDataRotation
  const rotation = ((Math.round(rawClockwiseRotation) % 360) + 360) % 360
  if (rotation % 90 !== 0) throw new VideoResourceError("Video rotation must be a multiple of 90 degrees")

  return { width, height, rotation, duration }
}

function parseFiniteNumber(value: unknown): number | undefined {
  if (typeof value === "number") return Number.isFinite(value) ? value : undefined
  if (typeof value !== "string" || value.trim() === "") return undefined
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : undefined
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
    throw new VideoResourceError("Unable to start ffprobe", 500)
  }
  if (typeof process.stdout === "number" || process.stdout === undefined
    || typeof process.stderr === "number" || process.stderr === undefined) {
    process.kill("SIGKILL")
    throw new VideoResourceError("Unable to capture ffprobe output", 500)
  }
  const [output, errorOutput, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ])
  if (exitCode !== 0) {
    throw new VideoResourceError(errorOutput.trim() === ""
      ? "Unable to inspect the video source"
      : "Video file must contain a readable video stream")
  }
  return output
}
