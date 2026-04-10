import { useMemo, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import type { Invoice, InvoiceAttachment } from '../../domain/models'
import { fromDateInputValue, toDateInputValue } from '../date'
import { isTauriRuntime } from '../../storage/tauriJsonStore'

export function InvoicesView() {
  const { state, dispatch } = useAppStore()
  const [isSaving, setIsSaving] = useState(false)
  const [wizardOpen, setWizardOpen] = useState(false)
  const [wizardIds, setWizardIds] = useState<string[]>([])
  const [wizardIndex, setWizardIndex] = useState(0)

  const sorted = useMemo(() => {
    return [...state.invoices].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
  }, [state.invoices])

  function baseTitleFromName(name: string): string {
    const trimmed = name.trim()
    if (!trimmed) return 'Invoice'
    return trimmed.replace(/\.[a-z0-9]+$/i, '')
  }

  function parseInvoiceDateGuess(text: string): Date | null {
    const s = text.trim()
    if (!s) return null

    const iso = s.match(/\b(20\d{2})[-_](\d{1,2})[-_](\d{1,2})\b/)
    if (iso) {
      const y = Number(iso[1])
      const m = Number(iso[2])
      const d = Number(iso[3])
      if (y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) return new Date(y, m - 1, d)
    }

    const dmy = s.match(/\b(\d{1,2})[-_](\d{1,2})[-_](20\d{2})\b/)
    if (dmy) {
      const d = Number(dmy[1])
      const m = Number(dmy[2])
      const y = Number(dmy[3])
      if (y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) return new Date(y, m - 1, d)
    }

    const monthMap: Record<string, number> = {
      jan: 1,
      feb: 2,
      mar: 3,
      apr: 4,
      may: 5,
      jun: 6,
      jul: 7,
      aug: 8,
      sep: 9,
      oct: 10,
      nov: 11,
      dec: 12,
    }
    const mmm = s.match(/\b(\d{1,2})[-_ ](jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[-_ ](\d{2}|\d{4})\b/i)
    if (mmm) {
      const d = Number(mmm[1])
      const m = monthMap[String(mmm[2]).toLowerCase()]
      let y = Number(mmm[3])
      if (y < 100) y += 2000
      if (y >= 2000 && m >= 1 && m <= 12 && d >= 1 && d <= 31) return new Date(y, m - 1, d)
    }

    return null
  }

  function openWizard(ids: string[], startIndex = 0) {
    if (ids.length === 0) return
    setWizardIds(ids)
    setWizardIndex(Math.min(Math.max(0, startIndex), ids.length - 1))
    setWizardOpen(true)
  }

  function closeWizard() {
    setWizardOpen(false)
    setWizardIds([])
    setWizardIndex(0)
  }

  const wizardCurrent = useMemo(() => {
    if (!wizardOpen) return null
    const id = wizardIds[wizardIndex]
    if (!id) return null
    return state.invoices.find((x) => x.id === id) ?? null
  }, [state.invoices, wizardIds, wizardIndex, wizardOpen])

  function wizardNext() {
    if (wizardIndex >= wizardIds.length - 1) {
      closeWizard()
    } else {
      setWizardIndex((i) => i + 1)
    }
  }

  async function addInvoiceImages() {
    if (!isTauriRuntime()) {
      window.alert('Invoice file storage is available in the desktop app (Tauri).')
      return
    }
    setIsSaving(true)
    try {
      const { open } = await import('@tauri-apps/plugin-dialog')
      const { invoke } = await import('@tauri-apps/api/core')
      const paths = await open({
        multiple: true,
        directory: false,
        filters: [{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'webp', 'heic', 'heif'] }],
      })
      if (!paths) return
      const list = Array.isArray(paths) ? paths : [paths]
      const createdIds: string[] = []
      for (const p of list) {
        const invoiceId = crypto.randomUUID()
        const attachmentId = crypto.randomUUID()
        const saved = (await invoke('save_invoice_attachment', {
          invoiceId,
          attachmentId,
          sourcePath: p,
          displayName: null,
        })) as { stored_relative_path: string; display_name: string }
        const att: InvoiceAttachment = {
          id: attachmentId,
          displayName: saved.display_name,
          storedRelativePath: saved.stored_relative_path,
          createdAt: new Date(),
        }
        const inv: Invoice = {
          id: invoiceId,
          title: baseTitleFromName(saved.display_name),
          createdAt: new Date(),
          invoiceDate: parseInvoiceDateGuess(saved.display_name),
          vendor: null,
          client: null,
          total: null,
          attachments: [att],
        }
        dispatch({ type: 'invoices/add', invoice: inv })
        createdIds.push(invoiceId)
      }
      if (createdIds.length > 0) openWizard(createdIds, 0)
    } catch (e) {
      console.error(e)
      const msg = e instanceof Error ? e.message : String(e)
      window.alert('Failed to add invoice images: ' + msg)
    } finally {
      setIsSaving(false)
    }
  }

  async function removeInvoice(inv: Invoice) {
    const ok = window.confirm('Delete invoice and its saved files?')
    if (!ok) return
    if (isTauriRuntime()) {
      try {
        const { invoke } = await import('@tauri-apps/api/core')
        for (const a of inv.attachments ?? []) {
          if (!a.storedRelativePath) continue
          await invoke('delete_bill_attachment', { storedRelativePath: a.storedRelativePath })
        }
      } catch (err) {
        console.error('Failed to delete invoice attachment', err)
      }
    }
    dispatch({ type: 'invoices/delete', id: inv.id })
  }

  return (
    <>
      {wizardOpen && wizardCurrent ? (
        <div
          className="modalBackdrop"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) closeWizard()
          }}
        >
          <div className="modal" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modalTitle">Invoice review</div>
            <div className="note">
              {wizardIds.length > 1 ? `Step ${wizardIndex + 1} of ${wizardIds.length}` : 'Review and edit invoice info.'}
            </div>

            <div className="groupBox" style={{ marginTop: 12 }}>
              <div className="groupTitle">Details</div>
              <div className="fieldRow" style={{ marginTop: 8 }}>
                <label className="field">
                  <div className="fieldLabel">Title</div>
                  <input
                    value={wizardCurrent.title}
                    onChange={(e) => dispatch({ type: 'invoices/update', invoice: { ...wizardCurrent, title: e.target.value } })}
                  />
                </label>
                <label className="field">
                  <div className="fieldLabel">Invoice date</div>
                  <input
                    type="date"
                    value={wizardCurrent.invoiceDate ? toDateInputValue(wizardCurrent.invoiceDate) : ''}
                    onChange={(e) =>
                      dispatch({
                        type: 'invoices/update',
                        invoice: { ...wizardCurrent, invoiceDate: e.target.value ? fromDateInputValue(e.target.value) : null },
                      })
                    }
                  />
                </label>
              </div>

              <div className="fieldRow" style={{ marginTop: 8 }}>
                <label className="field">
                  <div className="fieldLabel">Vendor</div>
                  <input
                    value={wizardCurrent.vendor ?? ''}
                    onChange={(e) => dispatch({ type: 'invoices/update', invoice: { ...wizardCurrent, vendor: e.target.value || null } })}
                    placeholder="Example: Home Care"
                  />
                </label>
                <label className="field">
                  <div className="fieldLabel">Client</div>
                  <input
                    value={wizardCurrent.client ?? ''}
                    onChange={(e) => dispatch({ type: 'invoices/update', invoice: { ...wizardCurrent, client: e.target.value || null } })}
                    placeholder="Example: Mrs Bishop-Fay"
                  />
                </label>
              </div>

              <div className="fieldRow" style={{ marginTop: 8 }}>
                <label className="field">
                  <div className="fieldLabel">Invoice total ({state.settings.displayCurrencyCode})</div>
                  <input
                    type="number"
                    value={wizardCurrent.total ? String(wizardCurrent.total.value) : ''}
                    onChange={(e) => {
                      const raw = e.target.value
                      const num = raw.trim() === '' ? null : Number(raw)
                      dispatch({
                        type: 'invoices/update',
                        invoice: {
                          ...wizardCurrent,
                          total: num == null || Number.isNaN(num) ? null : { currencyCode: state.settings.displayCurrencyCode, value: Math.abs(num) },
                        },
                      })
                    }}
                    placeholder="Example: 1319.68"
                  />
                </label>
              </div>
            </div>

            <div className="groupBox" style={{ marginTop: 12 }}>
              <div className="groupTitle">Files</div>
              <div className="note">
                Saved in app data so it can be included in backups for accountants.
              </div>
              <div className="list" style={{ marginTop: 10, maxHeight: 180, overflowY: 'auto' }}>
                {(wizardCurrent.attachments ?? []).map((a) => (
                  <div key={a.id} className="listItem stdRow" style={{ padding: '8px 12px' }}>
                    <div className="rowMain">
                      <div className="rowTitleText">{a.displayName}</div>
                      <div className="rowMeta">{a.storedRelativePath}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>

            <div className="modalActions">
              <button type="button" onClick={closeWizard}>
                Close
              </button>
              <button type="button" onClick={wizardNext} className="btnPrimary">
                {wizardIndex >= wizardIds.length - 1 ? 'Finish' : 'Next'}
              </button>
            </div>
          </div>
        </div>
      ) : null}

      <div className="row" style={{ marginTop: 8 }}>
        <div className="rowTitle">Invoices</div>
        <div className="rowActions">
          <button type="button" onClick={addInvoiceImages} className="btnPrimary" disabled={isSaving}>
            {isSaving ? 'Saving…' : 'Add images'}
          </button>
        </div>
      </div>

      <div className="groupBox" style={{ marginTop: 12 }}>
        <div className="groupTitle">Saved invoices</div>
        <div className="note">Invoice images are saved inside the app data folder, so you can include them in backups for accountants.</div>

        {sorted.length === 0 ? (
          <div className="empty">No invoices saved yet. Click “Add images”.</div>
        ) : (
          <div className="list" style={{ marginTop: 10 }}>
            {sorted.map((inv) => (
              <div key={inv.id} className="listItem stdRow" style={{ padding: '10px 12px' }}>
                <div className="rowMain">
                  <div className="rowTitleText">
                    <input
                      value={inv.title}
                      onChange={(e) => dispatch({ type: 'invoices/update', invoice: { ...inv, title: e.target.value } })}
                      style={{ width: '100%' }}
                    />
                  </div>
                  <div className="rowMeta">
                    {toDateInputValue(inv.createdAt)}
                    {inv.invoiceDate ? ` • Invoice: ${toDateInputValue(inv.invoiceDate)}` : ''}
                    {inv.total ? ` • Total: ${state.settings.displayCurrencyCode} ${inv.total.value.toFixed(2)}` : ''}
                    {' • '}
                    {inv.attachments?.length ?? 0} file{(inv.attachments?.length ?? 0) === 1 ? '' : 's'}
                  </div>
                </div>
                <div className="rowActions">
                  <button type="button" onClick={() => openWizard([inv.id], 0)}>
                    Review
                  </button>
                  <button type="button" onClick={() => void removeInvoice(inv)} className="btnDanger">
                    Delete
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </>
  )
}
