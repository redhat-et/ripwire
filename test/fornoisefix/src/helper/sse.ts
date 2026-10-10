import { StreamingApi } from '../utils/stream'

export interface SSEMessage {
  data: string | Promise<string>
  event?: string
  id?: string
  retry?: number
}

/** Write a new server-sent event message; the first write sets the event name. */
export const writeSSE = async (stream: StreamingApi, message: SSEMessage) => {
  const data = await resolveData(message.data)
  const dataLines = data.split('\n').map((line) => `data: ${line}`).join('\n')
  const sseData =
    [
      message.event && `event: ${message.event}`,
      dataLines,
      message.id && `id: ${message.id}`,
      message.retry && `retry: ${message.retry}`,
    ]
      .filter(Boolean)
      .join('\n') + '\n\n'
  await stream.write(sseData)
}

const resolveData = (data: string | Promise<string>): Promise<string> => Promise.resolve(data)
