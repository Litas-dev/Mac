import { useEffect, useRef } from 'react'
import { isTauriRuntime } from '../storage/tauriJsonStore'

type AvailableUpdate = {
  version: string
  body?: string | null
  date?: string | null
  downloadAndInstall: () => Promise<void>
}

export function UpdateWatcher() {
  const promptInFlightRef = useRef(false)
  const checkInFlightRef = useRef(false)

  useEffect(() => {
    if (!isTauriRuntime()) return

    async function safeConfirm(text: string): Promise<boolean> {
      try {
        const { confirm } = await import('@tauri-apps/plugin-dialog')
        return await confirm(text, { title: 'Update available', kind: 'info' })
      } catch {
        return window.confirm(text)
      }
    }

    async function safeMessage(text: string): Promise<void> {
      try {
        const { message } = await import('@tauri-apps/plugin-dialog')
        await message(text, { title: 'Update installed', kind: 'info' })
      } catch {
        window.alert(text)
      }
    }

    const tenMinutesMs = 10 * 60 * 1000
    const remainder = Date.now() % tenMinutesMs
    const delayToNextBoundary = remainder === 0 ? tenMinutesMs : tenMinutesMs - remainder

    let intervalId: number | null = null

    async function promptToUpdate(update: AvailableUpdate) {
      if (promptInFlightRef.current) return
      promptInFlightRef.current = true
      try {
        const ok = await safeConfirm(`Kivana ${update.version} is available.\n\nUpdate now?`)
        if (!ok) return
        await update.downloadAndInstall()
        await safeMessage('Update installed. Restart Kivana to finish.')
      } finally {
        promptInFlightRef.current = false
      }
    }

    async function runCheck() {
      if (checkInFlightRef.current) return
      checkInFlightRef.current = true
      try {
        const { check } = await import('@tauri-apps/plugin-updater')
        const update = (await check()) as AvailableUpdate | null
        if (!update) return
        await promptToUpdate(update)
      } catch {
        return
      } finally {
        checkInFlightRef.current = false
      }
    }

    const timeoutId = window.setTimeout(() => {
      void runCheck()
      intervalId = window.setInterval(() => {
        void runCheck()
      }, tenMinutesMs)
    }, delayToNextBoundary)

    return () => {
      window.clearTimeout(timeoutId)
      if (intervalId !== null) window.clearInterval(intervalId)
    }
  }, [])

  return null
}
