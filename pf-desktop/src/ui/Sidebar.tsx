import { useMemo } from 'react'
import { setSection } from '../app/AppProvider'
import { useAppStore } from '../app/appStore'
import { useAuth } from '../auth/AuthProvider'
import { isAdvancedAccount } from '../licensing/licenseGates'
import { SidebarIconView } from './icons'
import { buildSidebar } from './sidebarModel'

export function Sidebar() {
  const { state, dispatch } = useAppStore()
  const auth = useAuth()
  const advanced = useMemo(() => isAdvancedAccount(auth.entitlements), [auth.entitlements])
  const groups = useMemo(() => buildSidebar(state, advanced), [advanced, state])

  return (
    <aside className="sidebar" data-tauri-drag-region>
      <div className="sidebarDragGutter" data-tauri-drag-region />
      <div className="brand" data-tauri-drag-region>Kivana</div>
      <nav className="sbNav">
        {groups.map((g) => (
          <div key={g.title} className="sbGroup">
            <div className="sbGroupTitle" data-tauri-drag-region>{g.title}</div>
            {g.items.map((item) => {
              const active = state.ui.section === item.section
              return (
                <button
                  key={item.section}
                  type="button"
                  className={active ? 'sbItem active' : 'sbItem'}
                  onClick={() => dispatch(setSection(item.section))}
                >
                  <SidebarIconView icon={item.icon} dueSeverity={item.dueSeverity} />
                  <span className="sbText">
                    <span className="sbTitle">{item.title}</span>
                    {item.subtitle ? <span className="sbSubtitle">{item.subtitle}</span> : null}
                  </span>
                </button>
              )
            })}
          </div>
        ))}
      </nav>
      <div className="sidebarDragSpacer" data-tauri-drag-region />
    </aside>
  )
}
