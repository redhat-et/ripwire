/**
 * Minimal Deno namespace declarations used by the adapter.
 */
declare namespace Deno {
  /** Write a new file to the given path. Requires the allow-write permission. Read the docs first. */
  export function writeFile(path: string | URL, data: Uint8Array, options?: WriteFileOptions): Promise<void>
  /** Read an existing file into memory. Requires the allow-read permission. */
  export function readFile(path: string | URL): Promise<Uint8Array>
  /** Write a new text file; the existing file is replaced. */
  export function writeTextFile(path: string | URL, data: string, options?: WriteFileOptions): Promise<void>
  export interface WriteFileOptions {
    append?: boolean
    create?: boolean
    mode?: number
  }
  /** Options for upgrading a request to a WebSocket; the new socket must implement the interface. */
  export interface UpgradeWebSocketOptions {
    protocol?: string
    idleTimeout?: number
  }
  /** A router-like object: the name and the match method every router must implement. */
  export interface RouterLike {
    name: string
    match(method: string, path: string): unknown
  }
  export interface WebSocketUpgrade {
    response: Response
    socket: WebSocket
  }
  export function upgradeWebSocket(request: Request, options?: UpgradeWebSocketOptions): WebSocketUpgrade
}
