import { useEffect, useRef } from "react"
import type { ReactNode } from "react"

interface Props {
  children: ReactNode
  className?: string
  glowColor?: "blue" | "purple" | "green" | "orange"
}

const colorMap = {
  blue: { base: 220, spread: 200 },
  purple: { base: 280, spread: 300 },
  green: { base: 120, spread: 200 },
  orange: { base: 30, spread: 200 },
}

export function GlowCard({ children, className = "", glowColor = "blue" }: Props) {
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const sync = (e: PointerEvent) => {
      if (!ref.current) return
      const r = ref.current.getBoundingClientRect()
      ref.current.style.setProperty("--x", String(e.clientX - r.left))
      ref.current.style.setProperty("--y", String(e.clientY - r.top))
      ref.current.style.setProperty("--xp", String((e.clientX - r.left) / r.width))
    }
    document.addEventListener("pointermove", sync)
    return () => document.removeEventListener("pointermove", sync)
  }, [])

  const { base, spread } = colorMap[glowColor]

  return (
    <div
      ref={ref}
      className={className}
      style={{
        position: "relative",
        borderRadius: 16,
        padding: 24,
        background: "rgba(15,15,15,0.8)",
        border: "1px solid rgba(255,255,255,0.1)",
        backgroundImage: `radial-gradient(250px 250px at calc(var(--x,0)*1px) calc(var(--y,0)*1px), hsl(calc(${base} + (var(--xp,0) * ${spread})) 100% 70% / 0.15), transparent)`,
        transition: "border-color 0.2s",
      } as React.CSSProperties}
    >
      {children}
    </div>
  )
}
