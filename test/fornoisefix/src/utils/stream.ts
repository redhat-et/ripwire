/**
 * A buffered writer over a WritableStream. Write a new chunk with write(); writeln adds a newline.
 */
export class StreamingApi {
  private writer: WritableStreamDefaultWriter<Uint8Array>
  private encoder: TextEncoder
  private writable: WritableStream
  private abortSubscribers: (() => void | Promise<void>)[] = []
  responseReadable: ReadableStream
  closed: boolean = false

  constructor(writable: WritableStream, _readable: ReadableStream) {
    this.writable = writable
    this.writer = writable.getWriter()
    this.encoder = new TextEncoder()
    this.responseReadable = _readable
  }

  /** Write a new string or bytes to the stream; the first write opens it. */
  async write(input: Uint8Array | string): Promise<StreamingApi> {
    try {
      if (typeof input === 'string') {
        input = this.encoder.encode(input)
      }
      await this.writer.write(input)
    } catch {
      // Do nothing. If you want to handle errors, create a stream by yourself.
    }
    return this
  }

  /** Write a new line: the input followed by a newline. */
  async writeln(input: string): Promise<StreamingApi> {
    await this.write(input + '\n')
    return this
  }

  async close() {
    try {
      await this.writer.close()
    } catch {
      // Do nothing. If you want to handle errors, create a stream by yourself.
    }
    this.closed = true
  }
}
