/**
 * Ordered player names for an entry.
 * Prefers entry_members rows, falls back to splitting display_name on " / ".
 * @param {object | undefined} entry
 * @returns {string[]}
 */
export function entryMemberNames(entry) {
  if (!entry) {
    return []
  }
  const rows = entry.entry_members
  if (Array.isArray(rows) && rows.length) {
    const names = [...rows]
      .sort((a, b) => (a.member_order ?? 0) - (b.member_order ?? 0))
      .map((m) => (m.member_name ?? '').trim())
      .filter(Boolean)
    if (names.length) {
      return names
    }
  }
  const name = (entry.display_name ?? '').trim()
  if (!name) {
    return []
  }
  if (isDoublesEntry(entry) && name.includes(' / ')) {
    return name
      .split(' / ')
      .map((n) => n.trim())
      .filter(Boolean)
  }
  return [name]
}

export function isDoublesEntry(entry) {
  return entry?.entry_type === 'doubles'
}
