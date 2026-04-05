import { useMemo } from 'react'
import { setSection } from '../app/AppProvider'
import { useAppStore } from '../app/appStore'
import { SidebarIconView } from './icons'
import { buildSidebar } from './sidebarModel'

export function Sidebar() {
  const { state, dispatch } = useAppStore()
  const groups = useMemo(() => buildSidebar(state), [state])

  return (
    <aside className="sidebar">
      <div className="brand">Kivana</div>
      <nav className="sbNav">
        {groups.map((g) => (
          <div key={g.title} className="sbGroup">
            <div className="sbGroupTitle">{g.title}</div>
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
    </aside>
  )
}

