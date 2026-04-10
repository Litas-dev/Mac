import type { LoadedDatasets } from '../storage/localJsonStore'
import { attachmentPathsForBackup, decodeBackupToDatasets, encodeBackupV2 } from '../storage/backup'
import { isTauriRuntime } from '../storage/tauriJsonStore'
import type { AppAction } from '../app/appStore'

export async function exportBackup(datasets: LoadedDatasets): Promise<string> {
  const json = encodeBackupV2(datasets)
  const attachmentPaths = attachmentPathsForBackup(datasets)

  if (!isTauriRuntime()) {
    const blob = new Blob([json], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'Kivana_Backup.json'
    a.click()
    URL.revokeObjectURL(url)
    return 'Exported JSON (web mode).'
  }

  const { save } = await import('@tauri-apps/plugin-dialog')
  const { invoke } = await import('@tauri-apps/api/core')
  const df = new Date()
  const stamp = `${df.getFullYear()}-${String(df.getMonth() + 1).padStart(2, '0')}-${String(df.getDate()).padStart(2, '0')}_${String(df.getHours()).padStart(2, '0')}-${String(df.getMinutes()).padStart(2, '0')}`
  const defaultName = `Kivana_Backup_${stamp}.pfbackup`
  const path = await save({ defaultPath: defaultName })
  if (!path) return 'Export cancelled.'
  await invoke('export_backup', {
    bundleDirPath: path,
    backupJson: json,
    attachmentPaths: attachmentPaths,
  })
  return 'Export complete.'
}

export async function importBackupFromJson(dispatch: (a: AppAction) => void): Promise<string> {
  if (!isTauriRuntime()) return 'Import requires the desktop app (Tauri).'
  const { open } = await import('@tauri-apps/plugin-dialog')
  const { invoke } = await import('@tauri-apps/api/core')
  const path = await open({
    multiple: false,
    directory: false,
    filters: [{ name: 'Backup', extensions: ['json'] }],
  })
  if (!path || Array.isArray(path)) return 'Import cancelled.'
  const source = (await invoke('read_backup_source', { path })) as { json: string; attachments_source_dir: string | null }
  const decoded = decodeBackupToDatasets(source.json)
  dispatch({ type: 'data/replaceAll', data: decoded.datasets })
  clearSelections(dispatch)
  return `Imported backup v${decoded.version}.`
}

export async function importBackupFromFolder(dispatch: (a: AppAction) => void): Promise<string> {
  if (!isTauriRuntime()) return 'Import requires the desktop app (Tauri).'
  const { open } = await import('@tauri-apps/plugin-dialog')
  const { invoke } = await import('@tauri-apps/api/core')
  const dir = await open({ multiple: false, directory: true })
  if (!dir || Array.isArray(dir)) return 'Import cancelled.'
  const source = (await invoke('read_backup_source', { path: dir })) as { json: string; attachments_source_dir: string | null }
  const decoded = decodeBackupToDatasets(source.json)
  if (source.attachments_source_dir) {
    await invoke('restore_attachments_from', { sourceRootDir: source.attachments_source_dir })
  }
  dispatch({ type: 'data/replaceAll', data: decoded.datasets })
  clearSelections(dispatch)
  return `Imported backup v${decoded.version}.`
}

function clearSelections(dispatch: (a: AppAction) => void) {
  dispatch({ type: 'ui/selectBill', id: null })
  dispatch({ type: 'ui/selectIncome', id: null })
  dispatch({ type: 'ui/selectAccount', id: null })
  dispatch({ type: 'ui/selectTransaction', id: null })
  dispatch({ type: 'ui/selectGoal', id: null })
  dispatch({ type: 'ui/selectDebt', id: null })
}

