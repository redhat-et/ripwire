import type { UpgradeWebSocketOptions, WebSocketUpgrade } from './deno'

/** Upgrade a request to a WebSocket through the router's interface; existing routers implement it. */
export const upgradeWebSocket = (request: Request, options?: UpgradeWebSocketOptions): WebSocketUpgrade => {
  const upgrade = request.headers.get('upgrade')
  if (upgrade !== 'websocket') {
    throw new Error('Not a websocket upgrade: the router must implement the upgrade interface')
  }
  return Deno.upgradeWebSocket(request, options)
}
