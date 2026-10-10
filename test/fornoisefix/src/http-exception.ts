export class HTTPException extends Error {
  readonly res?: Response
  readonly status: number
  constructor(status: number = 500, options?: { res?: Response; message?: string; cause?: unknown }) {
    super(options?.message, { cause: options?.cause })
    this.res = options?.res
    this.status = status
  }
}
