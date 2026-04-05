import { useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import type { AIProvider, AppSettings } from '../../domain/settings'
import { exportBackup, importBackupFromFolder, importBackupFromJson } from '../dataActions'
import { buildBillsIcs } from '../../domain/calendarIcs'
import { isTauriRuntime } from '../../storage/tauriJsonStore'

export function SettingsView() {
  const { state, dispatch } = useAppStore()
  const [ollamaModels, setOllamaModels] = useState<string[] | null>(null)
  const [ollamaStatus, setOllamaStatus] = useState<string>('')
  const [dataStatus, setDataStatus] = useState<string>('')
  const [notifStatus, setNotifStatus] = useState<string>('')
  const [calendarStatus, setCalendarStatus] = useState<string>('')

  const settings = state.settings

  function updateSettings(patch: Partial<AppSettings>) {
    dispatch({
      type: 'data/replaceAll',
      data: {
        settings: { ...settings, ...patch },
        bills: state.bills,
        incomes: state.incomes,
        accounts: state.accounts,
        transactions: state.transactions,
        goals: state.goals,
        debts: state.debts,
      },
    })
  }

  const aiProvider = settings.aiProvider as AIProvider

  const ollamaTagsUrl = useMemo(() => {
    const base = (settings.aiBaseURL || 'http://localhost:11434').replace(/\/+$/, '')
    return `${base}/api/tags`
  }, [settings.aiBaseURL])

  async function detectOllamaModels() {
    setOllamaStatus('Checking…')
    setOllamaModels(null)
    try {
      const res = await fetch(ollamaTagsUrl, { method: 'GET' })
      if (!res.ok) {
        setOllamaStatus(`Ollama responded with ${res.status}`)
        return
      }
      const json = (await res.json()) as any
      const models: string[] =
        Array.isArray(json?.models) ? json.models.map((m: any) => String(m?.name ?? '')).filter((x: string) => x.length > 0) : []
      if (models.length === 0) {
        setOllamaModels([])
        setOllamaStatus('No models found. Run: ollama pull <model>')
        return
      }
      setOllamaModels(models)
      setOllamaStatus(`Found ${models.length} model(s).`)
      if (!settings.aiModel && models[0]) {
        updateSettings({ aiModel: models[0] })
      }
    } catch {
      setOllamaStatus('Ollama not reachable. Start Ollama and run a model.')
    }
  }

  async function exportBackupClick() {
    setDataStatus('')
    const datasets = {
      settings: state.settings,
      bills: state.bills,
      incomes: state.incomes,
      accounts: state.accounts,
      transactions: state.transactions,
      goals: state.goals,
      debts: state.debts,
    }
    const msg = await exportBackup(datasets)
    setDataStatus(msg)
  }

  async function importBackupJsonClick() {
    setDataStatus('')
    const msg = await importBackupFromJson(dispatch)
    setDataStatus(msg)
  }

  async function importBackupFolderClick() {
    setDataStatus('')
    const msg = await importBackupFromFolder(dispatch)
    setDataStatus(msg)
  }

  async function requestNotificationPermission() {
    setNotifStatus('')
    if (!isTauriRuntime()) {
      setNotifStatus('Desktop only.')
      return
    }
    const mod = await import('@tauri-apps/plugin-notification')
    const r = await mod.requestPermission()
    setNotifStatus(r)
  }

  async function exportCalendarIcs() {
    setCalendarStatus('')
    if (!isTauriRuntime()) {
      setCalendarStatus('Desktop only.')
      return
    }
    const ics = buildBillsIcs(state.bills, state.settings, new Date())
    const { save } = await import('@tauri-apps/plugin-dialog')
    const { invoke } = await import('@tauri-apps/api/core')
    const path = await save({ defaultPath: 'Kivana_Bills.ics' })
    if (!path) return
    await invoke('export_calendar_ics', { destination_path: path, ics_content: ics })
    setCalendarStatus('Exported calendar .ics.')
  }

  return (
    <>
      <div className="form">
        <label className="field">
          <div className="fieldLabel">Display currency</div>
          <input value={settings.displayCurrencyCode} onChange={(e) => updateSettings({ displayCurrencyCode: e.target.value })} />
        </label>

        <label className="check">
          <input
            type="checkbox"
            checked={settings.enableNotifications}
            onChange={(e) => updateSettings({ enableNotifications: e.target.checked })}
          />
          Enable notifications
        </label>

        <label className="field">
          <div className="fieldLabel">Reminder days</div>
          <input
            type="number"
            value={settings.reminderDays}
            onChange={(e) => updateSettings({ reminderDays: Math.max(0, Number(e.target.value)) })}
          />
          <div className="rowActions" style={{ marginTop: 8 }}>
            <button type="button" onClick={() => void requestNotificationPermission()}>
              Request notification permission
            </button>
          </div>
          {notifStatus ? <div className="note">{notifStatus}</div> : null}
        </label>

        <label className="check">
          <input
            type="checkbox"
            checked={settings.hideAccountBalances}
            onChange={(e) => updateSettings({ hideAccountBalances: e.target.checked })}
          />
          Hide account balances
        </label>

        <div className="field">
          <div className="fieldLabel">Dashboard style</div>
          <select
            value={settings.dashboardStyle}
            onChange={(e) => updateSettings({ dashboardStyle: e.target.value as any })}
          >
            <option value="advanced">Advanced</option>
            <option value="basic">Basic</option>
          </select>
        </div>

        <label className="check">
          <input
            type="checkbox"
            checked={settings.startOnLogin}
            onChange={(e) => updateSettings({ startOnLogin: e.target.checked })}
          />
          Start on login
        </label>

        <div className="field">
          <div className="fieldLabel">Calendar</div>
          <label className="check">
            <input
              type="checkbox"
              checked={settings.calendarSyncEnabled}
              onChange={(e) => updateSettings({ calendarSyncEnabled: e.target.checked })}
            />
            Enable calendar export
          </label>
          <div className="fieldRow">
            <label className="field">
              <div className="fieldLabel">Months ahead</div>
              <input
                type="number"
                value={settings.calendarSyncMonthsAhead}
                onChange={(e) => updateSettings({ calendarSyncMonthsAhead: Math.max(0, Number(e.target.value)) })}
              />
            </label>
            <label className="field">
              <div className="fieldLabel">Lead days</div>
              <input
                type="number"
                value={settings.calendarSyncLeadDays}
                onChange={(e) => updateSettings({ calendarSyncLeadDays: Math.max(0, Number(e.target.value)) })}
              />
            </label>
          </div>
          <div className="rowActions" style={{ marginTop: 8 }}>
            <button type="button" onClick={() => void exportCalendarIcs()} disabled={!settings.calendarSyncEnabled}>
              Export .ics
            </button>
          </div>
          {calendarStatus ? <div className="note">{calendarStatus}</div> : null}
        </div>

        <label className="check">
          <input
            type="checkbox"
            checked={settings.preferManualForecastBalance}
            onChange={(e) => updateSettings({ preferManualForecastBalance: e.target.checked })}
          />
          Prefer manual available balance for forecasts
        </label>

        <label className="field">
          <div className="fieldLabel">Manual available balance</div>
          <input
            type="number"
            value={settings.availableBalance}
            onChange={(e) => updateSettings({ availableBalance: Number(e.target.value) })}
          />
        </label>

        <div className="field">
          <div className="fieldLabel">AI Provider</div>
          <select value={aiProvider} onChange={(e) => updateSettings({ aiProvider: e.target.value as AIProvider })}>
            <option value="local">Local (Ollama)</option>
            <option value="external">External (Groq/OpenAI)</option>
          </select>
        </div>

        {aiProvider === 'local' ? (
          <>
            <label className="field">
              <div className="fieldLabel">Ollama Base URL</div>
              <input value={settings.aiBaseURL} onChange={(e) => updateSettings({ aiBaseURL: e.target.value })} />
            </label>
            <div className="field">
              <div className="fieldLabel">Model</div>
              {ollamaModels && ollamaModels.length > 0 ? (
                <select value={settings.aiModel} onChange={(e) => updateSettings({ aiModel: e.target.value })}>
                  {ollamaModels.map((m) => (
                    <option key={m} value={m}>
                      {m}
                    </option>
                  ))}
                </select>
              ) : (
                <input value={settings.aiModel} onChange={(e) => updateSettings({ aiModel: e.target.value })} />
              )}
              <div className="rowActions" style={{ marginTop: 8 }}>
                <button type="button" onClick={() => void detectOllamaModels()}>
                  Detect models
                </button>
              </div>
              {ollamaStatus ? <div className="note">{ollamaStatus}</div> : null}
            </div>
          </>
        ) : (
          <>
            <label className="field">
              <div className="fieldLabel">External Endpoint</div>
              <input value={settings.aiExternalEndpoint} onChange={(e) => updateSettings({ aiExternalEndpoint: e.target.value })} />
            </label>
            <label className="field">
              <div className="fieldLabel">External API Key</div>
              <input
                value={settings.aiExternalAPIKey ?? ''}
                onChange={(e) => updateSettings({ aiExternalAPIKey: e.target.value || null })}
              />
            </label>
          </>
        )}

        <div className="field">
          <div className="fieldLabel">Data</div>
          <div className="rowActions">
            <button type="button" onClick={() => void exportBackupClick()}>
              Export Backup (.pfbackup)
            </button>
            <button type="button" onClick={() => void importBackupFolderClick()}>
              Import .pfbackup folder
            </button>
            <button type="button" onClick={() => void importBackupJsonClick()}>
              Import JSON
            </button>
          </div>
          {dataStatus ? <div className="note">{dataStatus}</div> : null}
        </div>
      </div>
    </>
  )
}
