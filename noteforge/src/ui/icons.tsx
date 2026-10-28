/** Small hand-drawn SVG icons for note values (no external fonts needed). */
export function NoteIcon({ base, size = 22 }: { base: number; size?: number }) {
  const filled = base >= 4;
  const stem = base >= 2;
  const flags = base >= 8 ? Math.log2(base) - 2 : 0;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <ellipse cx="9" cy="18" rx="4.6" ry="3.3" transform="rotate(-22 9 18)" fill={filled ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth={filled ? 0 : 1.6} />
      {stem && <line x1="13.1" y1="17" x2="13.1" y2="2.5" stroke="currentColor" strokeWidth="1.4" />}
      {Array.from({ length: flags }, (_, i) => (
        <path key={i} d={`M13.1 ${2.5 + i * 3.6} q 5 2.5 4.2 7.2`} stroke="currentColor" strokeWidth="1.6" fill="none" />
      ))}
    </svg>
  );
}

export function RestIcon({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <path d="M10 3 l5 6 l-4 4.5 l4.5 6 c-3 -1.5 -6 -0.5 -4 3 c-4 -3 -2.5 -6 1 -5 l-5 -6 l4 -4.5 z" fill="currentColor" />
    </svg>
  );
}
