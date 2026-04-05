import { useEffect, useMemo, useRef, useState } from 'react'

type Option<T extends string> = { value: T; label: string }

export function MenuSelect<T extends string>(props: {
  value: T
  options: Option<T>[]
  onChange: (v: T) => void
  label?: string
  width?: number
  placeholder?: string
}) {
  const [open, setOpen] = useState(false)
  const [pos, setPos] = useState<{ left: number; top: number; width: number } | null>(null)
  const buttonRef = useRef<HTMLButtonElement | null>(null)

  const selectedLabel = useMemo(() => {
    const found = props.options.find((o) => o.value === props.value)
    if (found) return found.label
    return props.placeholder ?? String(props.value)
  }, [props.options, props.value, props.placeholder])

  useEffect(() => {
    if (!open) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  function openMenu() {
    const el = buttonRef.current
    if (!el) return
    const r = el.getBoundingClientRect()
    setPos({ left: r.left, top: r.bottom + 6, width: props.width ?? Math.max(220, Math.round(r.width)) })
    setOpen(true)
  }

  return (
    <>
      <button type="button" className="menuButton" onClick={openMenu} ref={buttonRef}>
        {props.label ? `${props.label}: ` : ''}
        {selectedLabel}
        <span className="menuChevron">▾</span>
      </button>
      {open ? <div className="menuOverlay" onClick={() => setOpen(false)} /> : null}
      {open && pos ? (
        <div className="menuPanel" style={{ left: pos.left, top: pos.top, width: pos.width }}>
          {props.options.map((o) => (
            <button
              key={o.value}
              type="button"
              className={o.value === props.value ? 'menuOption active' : 'menuOption'}
              onClick={() => {
                props.onChange(o.value)
                setOpen(false)
              }}
            >
              <span className="menuOptionText">{o.label}</span>
              {o.value === props.value ? <span className="menuCheck">✓</span> : <span className="menuCheck" />}
            </button>
          ))}
        </div>
      ) : null}
    </>
  )
}
