import { useEffect, useMemo, useRef, useState } from 'react'
import { useAppStore } from '../../app/appStore'
import type { Invoice, InvoiceAttachment } from '../../domain/models'
import { fromDateInputValue, toDateInputValue } from '../date'
import { isTauriRuntime } from '../../storage/tauriJsonStore'
import { normalizePeopleSettings, visibleInvoices } from '../../domain/people'
import { currency } from '../../domain/finance'
import { useContextMenu } from '../ContextMenu'
import { MenuSelect } from '../MenuSelect'
import { setSection } from '../../app/AppProvider'

const FILES_IMPORT_PDF_EVENT = 'files:import_pdf_to_transactions'
const UNFILED = '__unfiled__'
const AUTO_FOLDER = '__auto_folder__'

export function InvoicesView() {
  const { state, dispatch } = useAppStore()
  const [isSaving, setIsSaving] = useState(false)
  const [wizardOpen, setWizardOpen] = useState(false)
  const [wizardIds, setWizardIds] = useState<string[]>([])
  const [wizardIndex, setWizardIndex] = useState(0)
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')
  const [sortMode, setSortMode] = useState<'manual' | 'newest' | 'name'>('manual')
  const [search, setSearch] = useState('')
  const [folderFilter, setFolderFilter] = useState<string>('all')
  const [newFolderName, setNewFolderName] = useState('')
  const [extraFolders, setExtraFolders] = useState<string[]>([])
  const [selectMode, setSelectMode] = useState(false)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set())
  const [bulkTargetFolder, setBulkTargetFolder] = useState<string>(UNFILED)
  const [addTargetFolder, setAddTargetFolder] = useState<string>(AUTO_FOLDER)
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null)
  const [contextId, setContextId] = useState<string | null>(null)
  const [pdfThumbById, setPdfThumbById] = useState<Record<string, string>>({})
  const [imageThumbById, setImageThumbById] = useState<Record<string, string>>({})
  const [dragId, setDragId] = useState<string | null>(null)
  const dragOverId = useRef<string | null>(null)

  const peopleSettings = useMemo(() => normalizePeopleSettings(state.settings as any), [state.settings])
  const activePerson = useMemo(() => {
    return peopleSettings.peopleEnabled ? peopleSettings.people.find((p) => p.id === peopleSettings.activePersonId) ?? null : null
  }, [peopleSettings.activePersonId, peopleSettings.people, peopleSettings.peopleEnabled])

  function base64ToBytes(b64: string): Uint8Array {
    const bin = atob(b64)
    const out = new Uint8Array(bin.length)
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
    return out
  }

  const sorted = useMemo(() => {
    const items = visibleInvoices(state.invoices, state.settings)
    if (sortMode === 'name') return [...items].sort((a, b) => a.title.localeCompare(b.title))
    if (sortMode === 'newest') return [...items].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
    return [...items].sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || b.createdAt.getTime() - a.createdAt.getTime())
  }, [sortMode, state.invoices, state.settings])

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    let items = sorted
    if (folderFilter === UNFILED) {
      items = items.filter((inv) => !String(inv.folder ?? '').trim())
    } else if (folderFilter !== 'all') {
      items = items.filter((inv) => String(inv.folder ?? '').trim() === folderFilter)
    }
    if (!q) return items
    return items.filter((inv) => {
      const hay = [
        inv.title ?? '',
        inv.vendor ?? '',
        inv.client ?? '',
        ...(inv.attachments ?? []).map((a) => a.displayName ?? ''),
      ]
        .join(' ')
        .toLowerCase()
      return hay.includes(q)
    })
  }, [folderFilter, search, sorted])

  const folderStats = useMemo(() => {
    const map = new Map<string, number>()
    for (const inv of sorted) {
      const f = String(inv.folder ?? '').trim()
      if (!f) continue
      map.set(f, (map.get(f) ?? 0) + 1)
    }
    for (const f of extraFolders) {
      if (!map.has(f)) map.set(f, 0)
    }
    return Array.from(map.entries())
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => a.name.localeCompare(b.name))
  }, [extraFolders, sorted])
  const folders = useMemo(() => folderStats.map((x) => x.name), [folderStats])

  const contextInvoice = useMemo(() => {
    if (!contextId) return null
    return state.invoices.find((x) => x.id === contextId) ?? null
  }, [contextId, state.invoices])

  const contextFirstAttachment = contextInvoice?.attachments?.[0] ?? null
  const contextRelPath = String(contextFirstAttachment?.storedRelativePath ?? '')
  const contextIsPdf = useMemo(() => {
    const s = contextRelPath.toLowerCase()
    return s.endsWith('.pdf')
  }, [contextRelPath])

  function contextMoveTargets(): Invoice[] {
    if (!contextInvoice) return []
    const contextSelected = selectedIds.has(contextInvoice.id)
    if (contextSelected && selectedIds.size > 1) {
      return state.invoices.filter((inv) => selectedIds.has(inv.id))
    }
    return [contextInvoice]
  }

  const rowMenu = useContextMenu([
    {
      id: 'details',
      label: 'Edit details',
      onSelect: () => {
        if (!contextId) return
        openWizard([contextId], 0)
      },
    },
    {
      id: 'import_pdf',
      label: 'Add PDF to Transactions',
      disabled: !contextIsPdf || !contextInvoice,
      onSelect: () => {
        if (!contextInvoice) return
        const a = contextInvoice.attachments?.[0]
        if (!a) return
        const rel = String(a.storedRelativePath ?? '').trim()
        if (!rel) return
        void (async () => {
          try {
            const { invoke } = await import('@tauri-apps/api/core')
            const r = (await invoke('read_attachment_file', { storedRelativePath: rel })) as any
            const bytesBase64 = String(r?.base64 ?? '')
            const mime = String(r?.mime ?? 'application/pdf')
            if (!bytesBase64) return
            dispatch(setSection('transactions'))
            window.dispatchEvent(
              new CustomEvent(FILES_IMPORT_PDF_EVENT, {
                detail: { bytesBase64, mime, name: a.displayName || contextInvoice.title || 'statement.pdf' },
              })
            )
          } catch {
          }
        })()
      },
    },
    { id: 'sep-folders-a', kind: 'separator' as const },
    {
      id: 'to-unfiled',
      label: 'Add to folder: Unfiled',
      disabled: !contextInvoice,
      onSelect: () => {
        const targets = contextMoveTargets()
        for (const inv of targets) {
          dispatch({ type: 'invoices/update', invoice: { ...inv, folder: null } })
        }
        clearSelection()
      },
    },
    ...folders.map((f) => ({
      id: `to-folder-${f}`,
      label: `Add to folder: ${f}`,
      disabled: !contextInvoice,
      onSelect: () => {
        const targets = contextMoveTargets()
        for (const inv of targets) {
          dispatch({ type: 'invoices/update', invoice: { ...inv, folder: f } })
        }
        clearSelection()
      },
    })),
    {
      id: 'to-folder-new',
      label: 'Add to folder: + New...',
      disabled: !contextInvoice,
      onSelect: () => {
        if (!contextInvoice) return
        const name = (window.prompt('New folder name:') ?? '').trim()
        if (!name) return
        if (!folders.includes(name)) setExtraFolders((prev) => [...prev, name])
        const targets = contextMoveTargets()
        for (const inv of targets) {
          dispatch({ type: 'invoices/update', invoice: { ...inv, folder: name } })
        }
        clearSelection()
      },
    },
    { id: 'sep1', kind: 'separator' as const },
    {
      id: 'delete',
      label: 'Delete',
      onSelect: () => {
        if (!contextId) return
        setDeleteConfirmId(contextId)
      },
    },
  ])

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

  function resolvedFolderChoice(choice: string): string | null {
    if (choice === AUTO_FOLDER) {
      if (folderFilter === UNFILED || folderFilter === 'all') return null
      return folderFilter
    }
    if (choice === UNFILED) return null
    return choice.trim() ? choice.trim() : null
  }

  async function addInvoiceImages(targetFolder?: string | null) {
    if (!isTauriRuntime()) {
      window.alert('File storage is available in the desktop app (Tauri).')
      return
    }
    setIsSaving(true)
    try {
      const { open } = await import('@tauri-apps/plugin-dialog')
      const { invoke } = await import('@tauri-apps/api/core')
      const paths = await open({
        multiple: true,
        directory: false,
        filters: [
          { name: 'Files', extensions: ['png', 'jpg', 'jpeg', 'webp', 'heic', 'heif', 'pdf'] },
        ],
      })
      if (!paths) return
      const list = Array.isArray(paths) ? paths : [paths]
      const createdIds: string[] = []
      const baseOrder = Math.max(0, ...state.invoices.map((x) => x.order ?? 0))
      let order = baseOrder + 1
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
          personId: peopleSettings.peopleEnabled ? peopleSettings.activePersonId : null,
          order,
          folder: targetFolder ?? null,
          invoiceDate: parseInvoiceDateGuess(saved.display_name),
          vendor: null,
          client: null,
          total: null,
          attachments: [att],
        }
        dispatch({ type: 'invoices/add', invoice: inv })
        createdIds.push(invoiceId)
        order += 1
      }
      if (createdIds.length > 0) openWizard(createdIds, 0)
    } catch (e) {
      console.error(e)
      const msg = e instanceof Error ? e.message : String(e)
      window.alert('Failed to add files: ' + msg)
    } finally {
      setIsSaving(false)
    }
  }

  async function removeInvoice(inv: Invoice) {
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

  function isPdfPath(p: string | null): boolean {
    const s = String(p ?? '').toLowerCase()
    return s.endsWith('.pdf')
  }

  function isImagePath(p: string | null): boolean {
    const s = String(p ?? '').toLowerCase()
    return s.endsWith('.png') || s.endsWith('.jpg') || s.endsWith('.jpeg') || s.endsWith('.webp') || s.endsWith('.heic') || s.endsWith('.heif') || s.endsWith('.gif')
  }

  useEffect(() => {
    if (viewMode !== 'grid') return
    if (!isTauriRuntime()) return
    const visible = sorted.slice(0, 40)
    const pdfs = visible.filter((inv) => isPdfPath(inv.attachments?.[0]?.storedRelativePath ?? null))
    const imgs = visible.filter((inv) => isImagePath(inv.attachments?.[0]?.storedRelativePath ?? null))
    const missingPdf = pdfs.filter((inv) => !pdfThumbById[inv.id])
    const missingImg = imgs.filter((inv) => !imageThumbById[inv.id])
    if (missingPdf.length === 0 && missingImg.length === 0) return
    let cancelled = false
    void (async () => {
      const { invoke } = await import('@tauri-apps/api/core')
      for (const inv of missingImg) {
        if (cancelled) return
        const rel = String(inv.attachments?.[0]?.storedRelativePath ?? '').trim()
        if (!rel) continue
        try {
          const r = (await invoke('read_attachment_file', { storedRelativePath: rel })) as any
          const b64 = String(r?.base64 ?? '')
          const mime = String(r?.mime ?? 'application/octet-stream')
          if (!b64) continue
          const url = `data:${mime};base64,${b64}`
          setImageThumbById((prev) => ({ ...prev, [inv.id]: url }))
        } catch {
        }
      }

      if (missingPdf.length > 0) {
        const pdfjs: any = await import('pdfjs-dist/legacy/build/pdf.mjs')
        pdfjs.GlobalWorkerOptions.workerSrc = new URL('pdfjs-dist/legacy/build/pdf.worker.mjs', import.meta.url).toString()
        for (const inv of missingPdf) {
          if (cancelled) return
          const rel = String(inv.attachments?.[0]?.storedRelativePath ?? '').trim()
          if (!rel) continue
          try {
            const r = (await invoke('read_attachment_file', { storedRelativePath: rel })) as any
            const b64 = String(r?.base64 ?? '')
            if (!b64) continue
            const data = base64ToBytes(b64)
            const doc = await pdfjs.getDocument({ data }).promise
            const page = await doc.getPage(1)
            const viewport = page.getViewport({ scale: 0.45 })
            const canvas = document.createElement('canvas')
            const ctx = canvas.getContext('2d')
            if (!ctx) continue
            canvas.width = Math.max(1, Math.floor(viewport.width))
            canvas.height = Math.max(1, Math.floor(viewport.height))
            await page.render({ canvasContext: ctx, viewport }).promise
            const thumb = canvas.toDataURL('image/png')
            if (cancelled) return
            setPdfThumbById((prev) => ({ ...prev, [inv.id]: thumb }))
          } catch {
          }
        }
      }
    })()
    return () => {
      cancelled = true
    }
  }, [imageThumbById, pdfThumbById, sorted, viewMode])

  function reorder(fromId: string, toId: string) {
    if (fromId === toId) return
    const list = [...sorted]
    const fromIdx = list.findIndex((x) => x.id === fromId)
    const toIdx = list.findIndex((x) => x.id === toId)
    if (fromIdx < 0 || toIdx < 0) return
    const [moved] = list.splice(fromIdx, 1)
    list.splice(toIdx, 0, moved!)
    const start = 1
    for (let i = 0; i < list.length; i++) {
      const inv = list[i]!
      const nextOrder = start + i
      if ((inv.order ?? 0) === nextOrder) continue
      dispatch({ type: 'invoices/update', invoice: { ...inv, order: nextOrder } })
    }
  }

  function toggleSelect(id: string) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function selectAllFiltered() {
    setSelectedIds(new Set(filtered.map((x) => x.id)))
  }

  function clearSelection() {
    setSelectedIds(new Set())
  }

  function applyBulkFolder(folder: string | null) {
    if (selectedIds.size === 0) return
    const target = folder && folder.trim() ? folder.trim() : null
    for (const inv of state.invoices) {
      if (!selectedIds.has(inv.id)) continue
      dispatch({ type: 'invoices/update', invoice: { ...inv, folder: target } })
    }
    clearSelection()
  }

  function createFolder() {
    const name = newFolderName.trim()
    if (!name) return
    if (!folders.includes(name)) setExtraFolders((prev) => [...prev, name])
    setNewFolderName('')
    setFolderFilter(name)
    setBulkTargetFolder(name)
    setAddTargetFolder(name)
  }

  function renameFolder(oldName: string) {
    const next = (window.prompt(`Rename folder "${oldName}" to:`, oldName) ?? '').trim()
    if (!next || next === oldName) return
    for (const inv of state.invoices) {
      if (String(inv.folder ?? '').trim() !== oldName) continue
      dispatch({ type: 'invoices/update', invoice: { ...inv, folder: next } })
    }
    setExtraFolders((prev) => {
      const withNew = prev.filter((x) => x !== oldName)
      if (!withNew.includes(next)) withNew.push(next)
      return withNew
    })
    if (folderFilter === oldName) setFolderFilter(next)
    if (bulkTargetFolder === oldName) setBulkTargetFolder(next)
    if (addTargetFolder === oldName) setAddTargetFolder(next)
  }

  function deleteFolder(folder: string) {
    const ok = window.confirm(`Delete folder "${folder}"? Files will move to Unfiled.`)
    if (!ok) return
    for (const inv of state.invoices) {
      if (String(inv.folder ?? '').trim() !== folder) continue
      dispatch({ type: 'invoices/update', invoice: { ...inv, folder: null } })
    }
    setExtraFolders((prev) => prev.filter((x) => x !== folder))
    if (folderFilter === folder) setFolderFilter(UNFILED)
    if (bulkTargetFolder === folder) setBulkTargetFolder(UNFILED)
    if (addTargetFolder === folder) setAddTargetFolder(AUTO_FOLDER)
  }

  return (
    <>
      {deleteConfirmId ? (
        <div className="modalBackdrop" onMouseDown={(e) => e.target === e.currentTarget && setDeleteConfirmId(null)}>
          <div className="modal" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modalTitle">Delete file</div>
            <div className="note">This will delete the saved file from app storage. This cannot be undone.</div>
            <div className="modalActions">
              <button type="button" onClick={() => setDeleteConfirmId(null)}>
                Cancel
              </button>
              <button
                type="button"
                className="btnDanger"
                onClick={() => {
                  const inv = state.invoices.find((x) => x.id === deleteConfirmId)
                  if (inv) void removeInvoice(inv)
                  setDeleteConfirmId(null)
                }}
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      ) : null}
      {wizardOpen && wizardCurrent ? (
        <div
          className="modalBackdrop"
          onMouseDown={(e) => {
            if (e.target === e.currentTarget) closeWizard()
          }}
        >
          <div className="modal" onMouseDown={(e) => e.stopPropagation()}>
            <div className="modalTitle">File details</div>
            <div className="note">
              {wizardIds.length > 1 ? `Step ${wizardIndex + 1} of ${wizardIds.length}` : 'Review and edit file info.'}
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
                  <div className="fieldLabel">Date</div>
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
                  <div className="fieldLabel">Folder</div>
                  <input
                    value={wizardCurrent.folder ?? ''}
                    onChange={(e) =>
                      dispatch({ type: 'invoices/update', invoice: { ...wizardCurrent, folder: e.target.value.trim() ? e.target.value : null } })
                    }
                    placeholder="Example: Statements"
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
        <div className="rowTitle">Files</div>
        <div className="rowActions">
          <input className="filesSearch" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search files" style={{ width: 200 }} />
          <button type="button" onClick={() => setSelectMode((v) => !v)} className={selectMode ? 'btnPrimary' : ''}>
            {selectMode ? 'Exit select' : 'Select'}
          </button>
          {selectMode ? (
            <>
              <button type="button" onClick={selectAllFiltered}>
                Select shown
              </button>
              <button type="button" onClick={clearSelection}>
                Clear selection ({selectedIds.size})
              </button>
              <MenuSelect
                value={bulkTargetFolder as any}
                options={[
                  { value: UNFILED as any, label: 'Move: Unfiled' },
                  ...folders.map((f) => ({ value: f as any, label: `Move: ${f}` })),
                ]}
                onChange={(v: any) => setBulkTargetFolder(String(v))}
                width={200}
              />
              <button
                type="button"
                className="btnPrimary"
                disabled={selectedIds.size === 0}
                onClick={() => applyBulkFolder(bulkTargetFolder === UNFILED ? null : bulkTargetFolder)}
              >
                Move selected
              </button>
            </>
          ) : null}
          <MenuSelect
            value={addTargetFolder as any}
            options={[
              { value: AUTO_FOLDER as any, label: 'Add: Current folder' },
              { value: UNFILED as any, label: 'Add: Unfiled' },
              ...folders.map((f) => ({ value: f as any, label: `Add: ${f}` })),
            ]}
            onChange={(v: any) => setAddTargetFolder(String(v))}
            width={220}
          />
          <button type="button" onClick={() => setViewMode((v) => (v === 'grid' ? 'list' : 'grid'))}>
            {viewMode === 'grid' ? 'List' : 'Grid'}
          </button>
          <button type="button" onClick={() => setSortMode((s) => (s === 'manual' ? 'newest' : s === 'newest' ? 'name' : 'manual'))}>
            Sort: {sortMode === 'manual' ? 'Manual' : sortMode === 'newest' ? 'Newest' : 'Name'}
          </button>
          <button
            type="button"
            onClick={() => void addInvoiceImages(resolvedFolderChoice(addTargetFolder))}
            className="btnPrimary"
            disabled={isSaving}
          >
            {isSaving ? 'Saving…' : 'Add files'}
          </button>
        </div>
      </div>

      <div className="groupBox" style={{ marginTop: 12 }}>
        <div className="groupTitle">Saved files</div>
        <div className="note">Files are saved inside the app data folder, so you can include them in backups.</div>
        <div style={{ marginTop: 10, display: 'grid', gridTemplateColumns: '220px 1fr', gap: 12, alignItems: 'start' }}>
          <div className="list">
            <button type="button" className={folderFilter === 'all' ? 'listItem active' : 'listItem'} onClick={() => setFolderFilter('all')}>
              <div className="listTitle">All files</div>
              <div className="listMeta">{sorted.length}</div>
            </button>
            <button type="button" className={folderFilter === UNFILED ? 'listItem active' : 'listItem'} onClick={() => setFolderFilter(UNFILED)}>
              <div className="listTitle">Unfiled</div>
              <div className="listMeta">{sorted.filter((x) => !String(x.folder ?? '').trim()).length}</div>
            </button>
            {folderStats.map((f) => (
              <div
                key={f.name}
                className={folderFilter === f.name ? 'folderRow active' : 'folderRow'}
                role="button"
                tabIndex={0}
                onClick={() => setFolderFilter(f.name)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') setFolderFilter(f.name)
                }}
              >
                <div className="folderRowMain">
                  <div className="folderRowTitle">{f.name}</div>
                  <div className="folderRowMeta">{f.count}</div>
                </div>
                <div className="folderRowActions">
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      renameFolder(f.name)
                    }}
                  >
                    Rename
                  </button>
                  <button
                    type="button"
                    className="btnDanger"
                    onClick={(e) => {
                      e.stopPropagation()
                      deleteFolder(f.name)
                    }}
                  >
                    Delete
                  </button>
                </div>
              </div>
            ))}
            <div className="listItem">
              <input
                className="filesSearch"
                value={newFolderName}
                onChange={(e) => setNewFolderName(e.target.value)}
                placeholder="New folder name"
                onKeyDown={(e) => {
                  if (e.key === 'Enter') createFolder()
                }}
              />
              <button type="button" onClick={createFolder} style={{ marginTop: 8 }}>
                Create folder
              </button>
            </div>
          </div>

          {filtered.length === 0 ? (
            <div className="empty">{activePerson ? `No files for ${activePerson.name} in this folder.` : 'No files in this folder.'}</div>
          ) : viewMode === 'grid' ? (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: 10 }}>
              {filtered.map((inv) => {
                const rel = String(inv.attachments?.[0]?.storedRelativePath ?? '')
                const isImg = isImagePath(rel)
                const isPdf = isPdfPath(rel)
                const pdfThumb = pdfThumbById[inv.id] ?? null
                const imgThumb = imageThumbById[inv.id] ?? null
                const allowDrag = sortMode === 'manual' && search.trim().length === 0
                return (
                  <div
                    key={inv.id}
                    className="listItem"
                    draggable={allowDrag}
                    onClick={() => toggleSelect(inv.id)}
                    onContextMenu={(e) => {
                      setContextId(inv.id)
                      rowMenu.open(e)
                    }}
                    onDragStart={() => setDragId(inv.id)}
                    onDragOver={(e) => {
                      if (!allowDrag) return
                      e.preventDefault()
                      dragOverId.current = inv.id
                    }}
                    onDrop={(e) => {
                      if (!allowDrag) return
                      e.preventDefault()
                      const from = dragId
                      const to = dragOverId.current
                      setDragId(null)
                      dragOverId.current = null
                      if (from && to) reorder(from, to)
                    }}
                    style={{ padding: 10 }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6, alignItems: 'center' }}>
                      <input
                        type="checkbox"
                        checked={selectedIds.has(inv.id)}
                        onClick={(e) => e.stopPropagation()}
                        onChange={() => toggleSelect(inv.id)}
                      />
                      <span className="note">{isPdf ? 'PDF' : 'FILE'}</span>
                    </div>
                    <div style={{ width: '100%', height: 110, borderRadius: 10, overflow: 'hidden', border: '1px solid var(--border)', background: 'rgba(255,255,255,0.03)' }}>
                      {isImg && imgThumb ? (
                        <img src={imgThumb} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                      ) : isPdf && pdfThumb ? (
                        <img src={pdfThumb} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                      ) : (
                        <div style={{ width: '100%', height: '100%', display: 'grid', placeItems: 'center', color: 'var(--muted)', fontSize: 12, fontWeight: 800 }}>
                          {rel.toLowerCase().endsWith('.pdf') ? 'PDF' : 'FILE'}
                        </div>
                      )}
                    </div>
                    <div style={{ marginTop: 10, display: 'grid', gap: 6 }}>
                      <input
                        className="fileTitleInput"
                        value={inv.title}
                        onClick={(e) => e.stopPropagation()}
                        onChange={(e) => dispatch({ type: 'invoices/update', invoice: { ...inv, title: e.target.value } })}
                        style={{ width: '100%' }}
                        title={inv.title}
                      />
                      {inv.folder ? <div className="note">Folder: {inv.folder}</div> : null}
                      <div className="note">
                        {inv.invoiceDate ? toDateInputValue(inv.invoiceDate) : toDateInputValue(inv.createdAt)}
                        {inv.total ? ` • ${currency(inv.total.value, inv.total.currencyCode)}` : ''}
                      </div>
                      <div style={{ display: 'flex', gap: 8 }}>
                        <button type="button" onClick={(e) => { e.stopPropagation(); openWizard([inv.id], 0) }} style={{ flex: 1 }}>
                          Details
                        </button>
                        <button type="button" onClick={(e) => { e.stopPropagation(); setDeleteConfirmId(inv.id) }} className="btnDanger" style={{ flex: 1 }}>
                          Delete
                        </button>
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          ) : (
            <div className="list">
              {filtered.map((inv) => {
                const allowDrag = sortMode === 'manual' && search.trim().length === 0
                return (
                <div
                  key={inv.id}
                  className="listItem stdRow"
                  style={{ padding: '10px 12px' }}
                  draggable={allowDrag}
                  onClick={() => toggleSelect(inv.id)}
                  onContextMenu={(e) => {
                    setContextId(inv.id)
                    rowMenu.open(e)
                  }}
                  onDragStart={() => setDragId(inv.id)}
                  onDragOver={(e) => {
                    if (!allowDrag) return
                    e.preventDefault()
                    dragOverId.current = inv.id
                  }}
                  onDrop={(e) => {
                    if (!allowDrag) return
                    e.preventDefault()
                    const from = dragId
                    const to = dragOverId.current
                    setDragId(null)
                    dragOverId.current = null
                    if (from && to) reorder(from, to)
                  }}
                >
                  <input
                    type="checkbox"
                    checked={selectedIds.has(inv.id)}
                    onClick={(e) => e.stopPropagation()}
                    onChange={() => toggleSelect(inv.id)}
                  />
                  <div className="rowMain">
                    <div className="rowTitleText">
                      <input
                        className="fileTitleInput"
                        value={inv.title}
                        onClick={(e) => e.stopPropagation()}
                        onChange={(e) => dispatch({ type: 'invoices/update', invoice: { ...inv, title: e.target.value } })}
                        style={{ width: '100%' }}
                        title={inv.title}
                      />
                    </div>
                    <div className="rowMeta">
                      {inv.invoiceDate ? toDateInputValue(inv.invoiceDate) : toDateInputValue(inv.createdAt)}
                      {inv.total ? ` • ${currency(inv.total.value, inv.total.currencyCode)}` : ''}
                      {' • '}
                      {inv.attachments?.length ?? 0} file{(inv.attachments?.length ?? 0) === 1 ? '' : 's'}
                    </div>
                  </div>
                  <div className="rowActions">
                    <button type="button" onClick={(e) => { e.stopPropagation(); openWizard([inv.id], 0) }}>
                      Details
                    </button>
                    <button type="button" onClick={(e) => { e.stopPropagation(); setDeleteConfirmId(inv.id) }} className="btnDanger">
                      Delete
                    </button>
                  </div>
                </div>
              )})}
            </div>
          )}
        </div>
      </div>
      {rowMenu.Menu}
    </>
  )
}
