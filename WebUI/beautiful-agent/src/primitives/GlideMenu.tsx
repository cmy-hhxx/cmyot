import { useEffect, useRef, useState, type ReactNode } from "react";

type GlideMenuProps = {
  children: ReactNode;
  className?: string;
  highlightClassName?: string;
  rowSelector?: string;
};

/** A single hover layer that glides between interactive menu rows (beautifului.dev GlideMenu). */
export default function GlideMenu({
  children,
  className = "",
  highlightClassName = "inset-x-0 rounded-[8px] bg-hover",
  rowSelector = "[data-menu-row]",
}: GlideMenuProps) {
  const ref = useRef<HTMLDivElement>(null);
  const activeRowRef = useRef<HTMLElement | null>(null);
  const [box, setBox] = useState<{ left: number; top: number; width: number; height: number } | null>(null);
  const [visible, setVisible] = useState(false);

  const syncRowRect = (row: HTMLElement | null) => {
    const container = ref.current;
    if (!row || !container || !row.isConnected || !container.contains(row)) {
      activeRowRef.current = null;
      setVisible(false);
      return;
    }
    const containerRect = container.getBoundingClientRect();
    const rowRect = row.getBoundingClientRect();
    if (rowRect.width <= 0 || rowRect.height <= 0) {
      activeRowRef.current = null;
      setVisible(false);
      return;
    }
    activeRowRef.current = row;
    setBox({
      left: rowRect.left - containerRect.left,
      top: rowRect.top - containerRect.top,
      width: rowRect.width,
      height: rowRect.height,
    });
    setVisible(true);
  };

  const moveTo = (target: EventTarget | null) => {
    const container = ref.current;
    if (!(target instanceof Element) || !container) {
      activeRowRef.current = null;
      setVisible(false);
      return;
    }
    const row = target.closest(rowSelector);
    if (!(row instanceof HTMLElement) || !container.contains(row)) {
      activeRowRef.current = null;
      setVisible(false);
      return;
    }
    syncRowRect(row);
  };

  // Re-sync or hide whenever children collapse/expand so the pill never freezes over shifted headers.
  useEffect(() => {
    if (!visible) return;
    const row = activeRowRef.current;
    if (!row || !row.isConnected) {
      activeRowRef.current = null;
      setVisible(false);
      return;
    }
    syncRowRect(row);
  }, [children, visible]);

  return (
    <div
      ref={ref}
      onMouseOver={(event) => moveTo(event.target)}
      onMouseLeave={() => {
        activeRowRef.current = null;
        setVisible(false);
      }}
      onFocusCapture={(event) => moveTo(event.target)}
      onBlurCapture={(event) => {
        if (!ref.current?.contains(event.relatedTarget as Node | null)) {
          activeRowRef.current = null;
          setVisible(false);
        }
      }}
      className={`group/glide-menu relative ${className}`}
    >
      <span
        aria-hidden
        className={`pointer-events-none absolute ${highlightClassName}`}
        style={{
          left: box?.left ?? 0,
          top: box?.top ?? 0,
          width: box?.width ?? 0,
          height: box?.height ?? 0,
          opacity: box && visible ? 1 : 0,
          transition:
            "left 200ms cubic-bezier(0.23,1,0.32,1), top 200ms cubic-bezier(0.23,1,0.32,1), width 200ms cubic-bezier(0.23,1,0.32,1), height 200ms cubic-bezier(0.23,1,0.32,1), opacity 140ms ease",
        }}
      />
      {children}
    </div>
  );
}
