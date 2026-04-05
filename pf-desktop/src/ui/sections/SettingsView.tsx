import { useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import type { AIProvider, AppSettings } from '../../domain/settings'
import { exportBackup, importBackupFromFolder, importBackupFromJson } from '../dataActions'
import { buildBillsIcs } from '../../domain/calendarIcs'
import { isTauriRuntime } from '../../storage/tauriJsonStore'

export function SettingsView() {
  const { state, dispatch } = useAppStore()
  const [tab, setTab] = useState<'general' | 'notifications' | 'calendar' | 'forecast' | 'ai' | 'data'>('general')
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
      <div className="settingsPage form">
        <div className="settingsTabs">
          <div className="segmented">
            <button type="button" className={tab === 'general' ? 'active' : ''} onClick={() => setTab('general')}>
              General
            </button>
            <button type="button" className={tab === 'notifications' ? 'active' : ''} onClick={() => setTab('notifications')}>
              Notifications
            </button>
            <button type="button" className={tab === 'calendar' ? 'active' : ''} onClick={() => setTab('calendar')}>
              Calendar
            </button>
            <button type="button" className={tab === 'forecast' ? 'active' : ''} onClick={() => setTab('forecast')}>
              Forecast
            </button>
            <button type="button" className={tab === 'ai' ? 'active' : ''} onClick={() => setTab('ai')}>
              AI
            </button>
            <button type="button" className={tab === 'data' ? 'active' : ''} onClick={() => setTab('data')}>
              Data
            </button>
          </div>
        </div>

        {tab === 'general' ? (
          <div className="settingsGroup">
          <div className="settingsGroupHeader">
            <div className="settingsGroupTitle">General</div>
          </div>
          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Display currency</div>
              <div className="settingsRowHint">Used across totals, bills, and reports.</div>
            </div>
            <input
              className="settingsInput"
              value={settings.displayCurrencyCode}
              onChange={(e) => updateSettings({ displayCurrencyCode: e.target.value })}
            />
          </div>

          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Dashboard style</div>
              <div className="settingsRowHint">Choose between compact and detailed overview.</div>
            </div>
            <select value={settings.dashboardStyle} onChange={(e) => updateSettings({ dashboardStyle: e.target.value as any })}>
              <option value="advanced">Advanced</option>
              <option value="basic">Basic</option>
            </select>
          </div>

          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Hide account balances</div>
              <div className="settingsRowHint">Keeps amounts obscured across the app.</div>
            </div>
            <input
              className="settingsSwitch"
              type="checkbox"
              checked={settings.hideAccountBalances}
              onChange={(e) => updateSettings({ hideAccountBalances: e.target.checked })}
            />
          </div>
        </div>
        ) : null}

        {tab === 'notifications' ? (
          <div className="settingsGroup">
          <div className="settingsGroupHeader">
            <div className="settingsGroupTitle">Notifications</div>
          </div>

          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Enable notifications</div>
              <div className="settingsRowHint">Reminders for upcoming bills.</div>
            </div>
            <input
              className="settingsSwitch"
              type="checkbox"
              checked={settings.enableNotifications}
              onChange={(e) => updateSettings({ enableNotifications: e.target.checked })}
            />
          </div>

          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Reminder days</div>
              <div className="settingsRowHint">How many days before the due date to remind.</div>
            </div>
            <input
              className="settingsInput"
              type="number"
              value={settings.reminderDays}
              onChange={(e) => updateSettings({ reminderDays: Math.max(0, Number(e.target.value)) })}
            />
          </div>

          <div className="settingsRow settingsRowActions">
            <div className="rowActions">
              <button type="button" onClick={() => void requestNotificationPermission()}>
                Request permission
              </button>
            </div>
            {notifStatus ? <div className="note">{notifStatus}</div> : null}
          </div>
        </div>
        ) : null}

        {tab === 'general' ? (
          <div className="settingsGroup">
            <div className="settingsGroupHeader">
              <div className="settingsGroupTitle">Startup</div>
            </div>
            <div className="settingsRow">
              <div className="settingsRowText">
                <div className="settingsRowLabel">Start on login</div>
                <div className="settingsRowHint">Launch Kivana automatically when you sign in.</div>
              </div>
              <input
                className="settingsSwitch"
                type="checkbox"
                checked={settings.startOnLogin}
                onChange={(e) => updateSettings({ startOnLogin: e.target.checked })}
              />
            </div>
          </div>
        ) : null}

        {tab === 'calendar' ? (
          <div className="settingsGroup">
          <div className="settingsGroupHeader">
            <div className="settingsGroupTitle">Calendar</div>
          </div>
          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Enable calendar export</div>
              <div className="settingsRowHint">Generate an .ics file for upcoming bills.</div>
            </div>
            <input
              className="settingsSwitch"
              type="checkbox"
              checked={settings.calendarSyncEnabled}
              onChange={(e) => updateSettings({ calendarSyncEnabled: e.target.checked })}
            />
          </div>

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

          <div className="settingsRow settingsRowActions">
            <div className="rowActions">
              <button type="button" onClick={() => void exportCalendarIcs()} disabled={!settings.calendarSyncEnabled}>
                Export .ics
              </button>
            </div>
            {calendarStatus ? <div className="note">{calendarStatus}</div> : null}
          </div>
        </div>
        ) : null}

        {tab === 'forecast' ? (
          <div className="settingsGroup">
          <div className="settingsGroupHeader">
            <div className="settingsGroupTitle">Forecast</div>
          </div>

          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Use manual available balance</div>
              <div className="settingsRowHint">Overrides account totals for forecasts.</div>
            </div>
            <input
              className="settingsSwitch"
              type="checkbox"
              checked={settings.preferManualForecastBalance}
              onChange={(e) => updateSettings({ preferManualForecastBalance: e.target.checked })}
            />
          </div>

          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">Manual available balance</div>
              <div className="settingsRowHint">Used when manual balance is enabled.</div>
            </div>
            <input
              className="settingsInput"
              type="number"
              value={settings.availableBalance}
              onChange={(e) => updateSettings({ availableBalance: Number(e.target.value) })}
            />
          </div>
        </div>
        ) : null}

        {tab === 'ai' ? (
          <div className="settingsGroup">
          <div className="settingsGroupHeader">
            <div className="settingsGroupTitle">AI</div>
          </div>

          <div className="settingsRow">
            <div className="settingsRowText">
              <div className="settingsRowLabel">AI Provider</div>
              <div className="settingsRowHint">Local runs via Ollama. External uses an API key.</div>
            </div>
            <select value={aiProvider} onChange={(e) => updateSettings({ aiProvider: e.target.value as AIProvider })}>
              <option value="local">Local (Ollama)</option>
              <option value="external">External (Groq/OpenAI)</option>
            </select>
          </div>

          {aiProvider === 'local' ? (
            <>
              <div className="settingsRow">
                <div className="settingsRowText">
                  <div className="settingsRowLabel">Ollama Base URL</div>
                  <div className="settingsRowHint">Example: http://localhost:11434</div>
                </div>
                <input value={settings.aiBaseURL} onChange={(e) => updateSettings({ aiBaseURL: e.target.value })} />
              </div>
              <div className="settingsRow">
                <div className="settingsRowText">
                  <div className="settingsRowLabel">Model</div>
                  <div className="settingsRowHint">Select or type a model name.</div>
                </div>
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
              </div>
              <div className="settingsRow settingsRowActions">
                <div className="rowActions">
                  <button type="button" onClick={() => void detectOllamaModels()}>
                    Detect models
                  </button>
                </div>
                {ollamaStatus ? <div className="note">{ollamaStatus}</div> : null}
              </div>
            </>
          ) : (
            <>
              <div className="settingsRow">
                <div className="settingsRowText">
                  <div className="settingsRowLabel">External Endpoint</div>
                  <div className="settingsRowHint">Provider endpoint for chat completions.</div>
                </div>
                <input value={settings.aiExternalEndpoint} onChange={(e) => updateSettings({ aiExternalEndpoint: e.target.value })} />
              </div>
              <div className="settingsRow">
                <div className="settingsRowText">
                  <div className="settingsRowLabel">External API Key</div>
                  <div className="settingsRowHint">Stored locally on this device.</div>
                </div>
                <input
                  type="password"
                  value={settings.aiExternalAPIKey ?? ''}
                  onChange={(e) => updateSettings({ aiExternalAPIKey: e.target.value || null })}
                />
              </div>
            </>
          )}
        </div>
        ) : null}

        {tab === 'data' ? (
          <div className="settingsGroup">
          <div className="settingsGroupHeader">
            <div className="settingsGroupTitle">Data</div>
          </div>
          <div className="settingsRow settingsRowActions">
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
        ) : null}
      </div>
    </>
  )
}
