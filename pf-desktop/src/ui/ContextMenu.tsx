import { useEffect, useMemo, useRef, useState } from 'react'

export type ContextMenuItem =
  | { id: string; label: string; tone?: 'default' | 'danger'; disabled?: boolean; onSelect: () => void }
  | { id: string; kind: 'separator' }

export function useContextMenu(items: ContextMenuItem[]) {
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null)
  const isOpen = pos != null
  const menuRef = useRef<HTMLDivElement | null>(null)

  const normalized = useMemo(() => items, [items])

  useEffect(() => {
    if (!isOpen) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setPos(null)
    }
    function onDown(e: MouseEvent) {
      const el = menuRef.current
      if (!el) return
      if (e.target instanceof Node && el.contains(e.target)) return
      setPos(null)
    }
    window.addEventListener('keydown', onKey)
    window.addEventListener('mousedown', onDown)
    return () => {
      window.removeEventListener('keydown', onKey)
      window.removeEventListener('mousedown', onDown)
    }
  }, [isOpen])

  function open(e: React.MouseEvent) {
    e.preventDefault()
    e.stopPropagation()
    setPos({ x: e.clientX, y: e.clientY })
  }

  function close() {
    setPos(null)
  }

  const Menu = isOpen ? (
    <div className="ctxOverlay">
      <div
        className="ctxMenu"
        ref={menuRef}
        style={{
          left: pos!.x,
          top: pos!.y,
        }}
      >
        {normalized.map((it) => {
          if ((it as any).kind === 'separator') return <div key={it.id} className="ctxSep" />
          const item = it as Exclude<ContextMenuItem, { kind: 'separator'; id: string }>
          return (
            <button
              key={item.id}
              type="button"
              className={item.tone === 'danger' ? 'ctxItem danger' : 'ctxItem'}
              disabled={Boolean(item.disabled)}
              onClick={() => {
                close()
                item.onSelect()
              }}
            >
              {item.label}
            </button>
          )
        })}
      </div>
    </div>
  ) : null

  return { open, close, Menu }
}

