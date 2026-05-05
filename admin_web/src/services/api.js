import axios from 'axios'

// Use VITE_API_URL env var in production; fall back to localhost for dev
export const BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8100'
export const API_BASE = `${BASE_URL}/api/v1`
export const WS_URL = `${BASE_URL.replace(/^http/, 'ws')}/ws/queue`

export const api = axios.create({
  baseURL: API_BASE,
  timeout: 10000,
})

/**
 * Connect to the queue WebSocket.
 * Returns a cleanup function.
 */
export function connectQueueWs(onEvent) {
  let ws
  let reconnectTimer
  let disposed = false
  let pingInterval

  function connect() {
    try {
      ws = new WebSocket(WS_URL)

      ws.onmessage = (e) => {
        try {
          const data = JSON.parse(e.data)
          onEvent(data)
        } catch {}
      }

      ws.onclose = () => {
        if (!disposed) reconnectTimer = setTimeout(connect, 4000)
      }

      ws.onerror = () => {
        ws.close()
      }

      ws.onopen = () => {
        pingInterval = setInterval(() => {
          if (ws.readyState === WebSocket.OPEN) ws.send('ping')
        }, 20000)
      }
    } catch {
      if (!disposed) reconnectTimer = setTimeout(connect, 4000)
    }
  }

  connect()

  return () => {
    disposed = true
    clearTimeout(reconnectTimer)
    clearInterval(pingInterval)
    ws?.close()
  }
}
