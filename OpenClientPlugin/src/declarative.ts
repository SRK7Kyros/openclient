import { isAbsolute } from "node:path"
import type { ClientToolDescriptor, JsonObject, JsonValue, RemoteToolResult } from "./protocol.js"
import { imageRendererID, imageToolID } from "./image.js"
import { videoRendererID, videoToolID } from "./video.js"

type DeclarativeTool = {
  renderer: string
  fallbackTitle: string
  normalize(arguments_: JsonObject): JsonObject
  output(title: string, arguments_: JsonObject): string
  serverManaged?: boolean
}

export const videoToolDescriptor: ClientToolDescriptor = {
  id: videoToolID,
  description: "Display an MP4 video in OpenClient chat. The file must be a readable regular file on the OpenCode host; only a small cover is prepared until the viewer requests playback.",
  inputSchema: {
    type: "object",
    required: ["schemaVersion", "filePath"],
    additionalProperties: false,
    properties: {
      schemaVersion: { type: "integer", const: 1 },
      title: { type: "string", minLength: 1, maxLength: 120, pattern: "\\S" },
      filePath: {
        type: "string",
        minLength: 1,
        description: "Absolute path to an MP4 file on the OpenCode host.",
      },
    },
  },
}

export const imageToolDescriptor: ClientToolDescriptor = {
  id: imageToolID,
  description: "Display a JPEG, PNG, or WebP image in OpenClient chat. The file must be a readable regular file on the OpenCode host; only a small preview is persisted in the visual payload.",
  inputSchema: {
    type: "object",
    required: ["schemaVersion", "filePath"],
    additionalProperties: false,
    properties: {
      schemaVersion: { type: "integer", const: 1 },
      title: { type: "string", minLength: 1, maxLength: 120, pattern: "\\S" },
      accessibilityLabel: { type: "string", minLength: 1, maxLength: 500, pattern: "\\S" },
      filePath: {
        type: "string",
        minLength: 1,
        description: "Absolute path to a JPEG, PNG, or WebP file on the OpenCode host.",
      },
    },
  },
}

export const pluginDeclarativeToolDescriptors = [imageToolDescriptor, videoToolDescriptor]

const tools: Record<string, DeclarativeTool> = {
  openclient_visual_chart: {
    renderer: "openclient.chart.v1",
    fallbackTitle: "Chart",
    normalize: normalizeChart,
    output: (_title, arguments_) => {
      const series = requireArray(arguments_.series, "Chart series")
      const pointCount = series.reduce<number>((total, item) => {
        const object = requireObject(item, "Chart series")
        return total + requireArray(object.points, "Chart points").length
      }, 0)
      return `Displayed a ${String(arguments_.chartType)} chart with ${pointCount} data points.`
    },
  },
  openclient_visual_html: {
    renderer: "openclient.html.v1",
    fallbackTitle: "HTML visual",
    normalize: normalizeHTML,
    output: (title) => `Displayed the static HTML visual "${title}".`,
  },
  openclient_visual_map: {
    renderer: "openclient.map.v1",
    fallbackTitle: "Map",
    normalize: normalizeMap,
    output: (title, arguments_) => {
      const markerCount = requireArray(arguments_.markers, "Map markers").length
      return `Displayed ${title} with ${markerCount} markers.`
    },
  },
  [imageToolID]: {
    renderer: imageRendererID,
    fallbackTitle: "Image",
    normalize: normalizeImage,
    output: (title) => `Prepared the image "${title}" for lazy loading.`,
    serverManaged: true,
  },
  [videoToolID]: {
    renderer: videoRendererID,
    fallbackTitle: "Video",
    normalize: normalizeVideo,
    output: (title) => `Prepared the video "${title}" for lazy playback.`,
    serverManaged: true,
  },
}

export function isDeclarativeTool(toolID: string): boolean {
  return tools[toolID] !== undefined
}

export function executeDeclarativeTool(toolID: string, arguments_: JsonObject): RemoteToolResult | undefined {
  const definition = tools[toolID]
  if (!definition) return undefined
  const payload = definition.normalize(arguments_)
  if (definition.serverManaged) throw new Error(`${toolID} requires the OpenClient media resource service`)
  return declarativeResult(toolID, definition, payload)
}

export function normalizeVideoArguments(arguments_: JsonObject): { schemaVersion: 1; title?: string; filePath: string } {
  return normalizeVideo(arguments_) as { schemaVersion: 1; title?: string; filePath: string }
}

export function normalizeImageArguments(arguments_: JsonObject): {
  schemaVersion: 1
  title?: string
  accessibilityLabel?: string
  filePath: string
} {
  return normalizeImage(arguments_) as {
    schemaVersion: 1
    title?: string
    accessibilityLabel?: string
    filePath: string
  }
}

export function videoDeclarativeResult(payload: JsonObject): RemoteToolResult {
  const definition = tools[videoToolID]
  if (!definition) throw new Error("Video declarative tool is not registered")
  return declarativeResult(videoToolID, definition, payload)
}

export function imageDeclarativeResult(payload: JsonObject): RemoteToolResult {
  const definition = tools[imageToolID]
  if (!definition) throw new Error("Image declarative tool is not registered")
  return declarativeResult(imageToolID, definition, payload)
}

function declarativeResult(toolID: string, definition: DeclarativeTool, payload: JsonObject): RemoteToolResult {
  const title = typeof payload.title === "string" ? payload.title : definition.fallbackTitle
  return {
    title,
    output: definition.output(title, payload),
    metadata: {
      toolID,
      renderer: definition.renderer,
      schemaVersion: 1,
      executionMode: "declarative",
      payload,
    },
  }
}

function normalizeVideo(arguments_: JsonObject): JsonObject {
  assertKeys(arguments_, ["schemaVersion", "title", "filePath"], "Video arguments")
  requireSchemaVersion(arguments_)
  const title = optionalNormalizedString(arguments_.title, 120, "Video title")
  const filePath = requireString(arguments_.filePath, "Video filePath")
  if (!isAbsolute(filePath)) throw new Error("Video filePath must be an absolute path")
  if (!filePath.toLowerCase().endsWith(".mp4")) throw new Error("Video filePath must reference an MP4 file")
  return {
    schemaVersion: 1,
    ...(title === undefined ? {} : { title }),
    filePath,
  }
}

function normalizeImage(arguments_: JsonObject): JsonObject {
  assertKeys(arguments_, ["schemaVersion", "title", "accessibilityLabel", "filePath"], "Image arguments")
  requireSchemaVersion(arguments_)
  const title = optionalNormalizedString(arguments_.title, 120, "Image title")
  const accessibilityLabel = optionalNormalizedString(
    arguments_.accessibilityLabel,
    500,
    "Image accessibilityLabel",
  )
  const filePath = requireString(arguments_.filePath, "Image filePath")
  if (!isAbsolute(filePath)) throw new Error("Image filePath must be an absolute path")
  if (!/\.(?:jpe?g|png|webp)$/i.test(filePath)) {
    throw new Error("Image filePath must reference a JPEG, PNG, or WebP file")
  }
  return {
    schemaVersion: 1,
    ...(title === undefined ? {} : { title }),
    ...(accessibilityLabel === undefined ? {} : { accessibilityLabel }),
    filePath,
  }
}

function normalizeHTML(arguments_: JsonObject): JsonObject {
  assertKeys(arguments_, ["schemaVersion", "title", "accessibilityLabel", "html", "height"], "HTML arguments")
  requireSchemaVersion(arguments_)
  const title = normalizedString(arguments_.title, 120, "HTML title", 480)
  const accessibilityLabel = normalizedString(
    arguments_.accessibilityLabel,
    500,
    "HTML accessibilityLabel",
    2_000,
  )
  const html = requireString(arguments_.html, "HTML fragment").trim()
  const height = requireInteger(arguments_.height, "HTML height")
  if (html.length === 0 || utf8Length(html) > 65_536) throw new Error("HTML fragment exceeds 65,536 UTF-8 bytes")
  if (height <= 0) throw new Error("HTML height must be a positive integer")
  if ((html.match(/<\s*[a-zA-Z][^>]*>/g) ?? []).length > 200) throw new Error("HTML fragment exceeds 200 elements")
  if (html.includes("\\")) throw new Error("HTML fragment contains unsupported CSS escapes")

  const forbidden = [
    /<\s*\/?\s*(script|iframe|frame|frameset|object|embed|form|input|button|select|option|textarea|label|base|link|meta|audio|video|source|track|foreignobject|a|img|image|use|filter|animate|animatetransform|animatemotion|set|canvas)(?:\s|\/|>)/i,
    /<\s*\/?\s*fe[a-z0-9-]*(?:\s|\/|>)/i,
    /(?:\s|\/)on[a-z]+\s*=/i,
    /(?:\s|\/)(src|srcset|href|xlink:href|action|formaction|style)\s*=/i,
    /javascript\s*:/i,
    /@import\b/i,
    /@keyframes\b/i,
    /(?:^|[;{\s])(animation|transition|filter|backdrop-filter)\s*:/i,
    /url\s*\(/i,
  ]
  if (forbidden.some((pattern) => pattern.test(html))) throw new Error("HTML fragment contains unsupported content")
  return { schemaVersion: 1, title, accessibilityLabel, html, height }
}

function normalizeMap(arguments_: JsonObject): JsonObject {
  assertKeys(arguments_, ["schemaVersion", "title", "center", "span", "markers"], "Map arguments")
  requireSchemaVersion(arguments_)
  const title = optionalNormalizedString(arguments_.title, 120, "Map title")
  const center = normalizeCoordinate(arguments_.center, "Map center")
  const spanValue = arguments_.span === undefined ? { latitudeDelta: 0.05, longitudeDelta: 0.05 } : requireObject(arguments_.span, "Map span")
  assertKeys(spanValue, ["latitudeDelta", "longitudeDelta"], "Map span")
  const latitudeDelta = requireFiniteNumber(spanValue.latitudeDelta, "Map latitudeDelta")
  const longitudeDelta = requireFiniteNumber(spanValue.longitudeDelta, "Map longitudeDelta")
  if (latitudeDelta < 0.0001 || latitudeDelta > 180 || longitudeDelta < 0.0001 || longitudeDelta > 360) {
    throw new Error("Map span is out of range")
  }

  const markerValues = arguments_.markers === undefined ? [] : requireArray(arguments_.markers, "Map markers")
  if (markerValues.length > 50) throw new Error("Map exceeds 50 markers")
  const markerIDs = new Set<string>()
  const markers = markerValues.map((value, index) => {
    const marker = requireObject(value, `Map marker ${index}`)
    assertKeys(marker, ["id", "title", "subtitle", "coordinate"], `Map marker ${index}`)
    const id = normalizedString(marker.id, 80, `Map marker ${index} id`)
    if (markerIDs.has(id)) throw new Error(`Duplicate map marker ID: ${id}`)
    markerIDs.add(id)
    const markerTitle = normalizedString(marker.title, 120, `Map marker ${index} title`)
    const subtitle = optionalNormalizedString(marker.subtitle, 240, `Map marker ${index} subtitle`)
    return {
      id,
      title: markerTitle,
      ...(subtitle === undefined ? {} : { subtitle }),
      coordinate: normalizeCoordinate(marker.coordinate, `Map marker ${index} coordinate`),
    }
  })
  return {
    schemaVersion: 1,
    ...(title === undefined ? {} : { title }),
    center,
    span: { latitudeDelta, longitudeDelta },
    markers,
  }
}

function normalizeChart(arguments_: JsonObject): JsonObject {
  assertKeys(arguments_, ["schemaVersion", "chartType", "title", "xAxis", "yAxis", "series"], "Chart arguments")
  requireSchemaVersion(arguments_)
  const chartType = requireEnum(arguments_.chartType, ["line", "area", "bar", "scatter", "pie", "donut"], "Chart type")
  const title = optionalNormalizedString(arguments_.title, 120, "Chart title")
  const xAxisValue = requireObject(arguments_.xAxis, "Chart xAxis")
  assertKeys(xAxisValue, ["type", "title"], "Chart xAxis")
  const axisType = requireEnum(xAxisValue.type, ["category", "number", "time"], "Chart xAxis type")
  const xTitle = optionalNormalizedString(xAxisValue.title, 80, "Chart xAxis title")
  const yAxisValue = arguments_.yAxis === undefined ? {} : requireObject(arguments_.yAxis, "Chart yAxis")
  assertKeys(yAxisValue, ["title"], "Chart yAxis")
  const yTitle = optionalNormalizedString(yAxisValue.title, 80, "Chart yAxis title")

  const seriesValues = requireArray(arguments_.series, "Chart series")
  if (seriesValues.length === 0 || seriesValues.length > 8) throw new Error("Chart requires 1 through 8 series")
  const seriesIDs = new Set<string>()
  let totalPoints = 0
  const series = seriesValues.map((value, seriesIndex) => {
    const item = requireObject(value, `Chart series ${seriesIndex}`)
    assertKeys(item, ["id", "name", "points"], `Chart series ${seriesIndex}`)
    const id = normalizedString(item.id, 80, `Chart series ${seriesIndex} id`)
    if (seriesIDs.has(id)) throw new Error(`Duplicate chart series ID: ${id}`)
    seriesIDs.add(id)
    const name = normalizedString(item.name, 120, `Chart series ${seriesIndex} name`)
    const pointValues = requireArray(item.points, `Chart series ${seriesIndex} points`)
    if (pointValues.length === 0) throw new Error("Chart series must contain points")
    totalPoints += pointValues.length
    if (totalPoints > 500) throw new Error("Chart exceeds 500 aggregate points")
    const pointIDs = new Set<string>()
    const xValues = new Set<string>()
    const points = pointValues.map((pointValue, pointIndex) => {
      const point = requireObject(pointValue, `Chart point ${pointIndex}`)
      assertKeys(point, ["id", "x", "y"], `Chart point ${pointIndex}`)
      const pointID = normalizedString(point.id, 80, `Chart point ${pointIndex} id`)
      if (pointIDs.has(pointID)) throw new Error(`Duplicate chart point ID: ${pointID}`)
      pointIDs.add(pointID)
      const x = normalizeXValue(point.x, axisType)
      const xKey = `${typeof x}:${String(x)}`
      if (xValues.has(xKey)) throw new Error(`Duplicate chart x value: ${String(x)}`)
      xValues.add(xKey)
      return { id: pointID, x, y: requireFiniteNumber(point.y, `Chart point ${pointIndex} y`) }
    })
    return { id, name, points }
  })

  if (chartType === "pie" || chartType === "donut") {
    if (axisType !== "category" || series.length !== 1) throw new Error(`${chartType} charts require one categorical series`)
    const values = series[0]?.points.map((point) => point.y) ?? []
    const total = values.reduce((sum, value) => sum + value, 0)
    if (values.some((value) => value < 0) || !Number.isFinite(total) || total <= 0) {
      throw new Error(`${chartType} chart values must be nonnegative with a positive total`)
    }
  }
  return {
    schemaVersion: 1,
    chartType,
    ...(title === undefined ? {} : { title }),
    xAxis: { type: axisType, ...(xTitle === undefined ? {} : { title: xTitle }) },
    yAxis: { ...(yTitle === undefined ? {} : { title: yTitle }) },
    series,
  }
}

function normalizeXValue(value: JsonValue | undefined, axisType: string): string | number {
  if (axisType === "number") return requireFiniteNumber(value, "Chart numeric x value")
  const string = normalizedString(value, axisType === "time" ? 80 : 120, "Chart x value")
  if (axisType === "time" && (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(string) || Number.isNaN(Date.parse(string)))) {
    throw new Error("Chart time x values must use RFC 3339 timestamps")
  }
  return string
}

function normalizeCoordinate(value: JsonValue | undefined, field: string): JsonObject {
  const coordinate = requireObject(value, field)
  assertKeys(coordinate, ["latitude", "longitude"], field)
  const latitude = requireFiniteNumber(coordinate.latitude, `${field} latitude`)
  const longitude = requireFiniteNumber(coordinate.longitude, `${field} longitude`)
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    throw new Error(`${field} is out of range`)
  }
  return { latitude, longitude }
}

function requireSchemaVersion(arguments_: JsonObject): void {
  if (arguments_.schemaVersion !== 1) throw new Error("Visual tool requires schemaVersion 1")
}

function assertKeys(object: JsonObject, allowed: string[], field: string): void {
  const allowedKeys = new Set(allowed)
  const unknown = Object.keys(object).find((key) => !allowedKeys.has(key))
  if (unknown !== undefined) throw new Error(`${field} contains unknown field ${unknown}`)
}

function optionalNormalizedString(value: JsonValue | undefined, maximumLength: number, field: string): string | undefined {
  return value === undefined ? undefined : normalizedString(value, maximumLength, field)
}

function normalizedString(value: JsonValue | undefined, maximumLength: number, field: string, maximumBytes?: number): string {
  const normalized = requireString(value, field).trim()
  if (normalized.length === 0 || Array.from(normalized).length > maximumLength) {
    throw new Error(`${field} must contain at most ${maximumLength} characters`)
  }
  if (maximumBytes !== undefined && utf8Length(normalized) > maximumBytes) {
    throw new Error(`${field} exceeds ${maximumBytes} UTF-8 bytes`)
  }
  return normalized
}

function requireString(value: JsonValue | undefined, field: string): string {
  if (typeof value !== "string") throw new Error(`${field} must be a string`)
  return value
}

function requireObject(value: JsonValue | undefined, field: string): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error(`${field} must be an object`)
  return value
}

function requireArray(value: JsonValue | undefined, field: string): JsonValue[] {
  if (!Array.isArray(value)) throw new Error(`${field} must be an array`)
  return value
}

function requireFiniteNumber(value: JsonValue | undefined, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new Error(`${field} must be a finite number`)
  return value
}

function requireInteger(value: JsonValue | undefined, field: string): number {
  const number = requireFiniteNumber(value, field)
  if (!Number.isInteger(number)) throw new Error(`${field} must be an integer`)
  return number
}

function requireEnum(value: JsonValue | undefined, allowed: string[], field: string): string {
  if (typeof value !== "string" || !allowed.includes(value)) throw new Error(`${field} is unsupported`)
  return value
}

function utf8Length(value: string): number {
  return new TextEncoder().encode(value).length
}
