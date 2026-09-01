const POLL_INTERVAL_MS = 750
const TIMEOUT_MS = 4 * 60 * 1000

export function idempotencyKey() {
  return window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`
}

export async function operationResult(response) {
  const payload = await response.json()
  if (!response.ok) throw new Error(payload.error || "Request failed")
  if (!payload.status_url) return payload

  const deadline = Date.now() + TIMEOUT_MS
  while (Date.now() < deadline) {
    const statusResponse = await fetch(payload.status_url, {
      headers: { "Accept": "application/json" }
    })
    const operation = await statusResponse.json()
    if (!statusResponse.ok) throw new Error(operation.error || "Could not read operation status")
    if (operation.status === "completed") return operation.result || {}
    if (["failed", "canceled"].includes(operation.status)) {
      throw new Error(operation.error || `Operation ${operation.status}`)
    }
    await new Promise(resolve => window.setTimeout(resolve, POLL_INTERVAL_MS))
  }

  throw new Error("The operation is still running. Its status is saved in workflow activity.")
}
