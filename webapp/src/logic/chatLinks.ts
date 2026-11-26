// A message's text cut into plain words and web links, so a bubble can make
// the links tappable without ever putting the text in as HTML.

export type TextPart = { kind: 'text'; text: string } | { kind: 'link'; text: string; href: string };

const URL_PATTERN = /\b(?:https?:\/\/|www\.)[^\s<>"']+/gi;
/** Punctuation that ends a sentence, not the link: "see favcircles.com." */
const TRAILING = /[.,!?;:)\]}'"]+$/;

export function linkParts(text: string): TextPart[] {
  const parts: TextPart[] = [];
  let last = 0;
  for (const match of text.matchAll(URL_PATTERN)) {
    const start = match.index ?? 0;
    let raw = match[0];
    const trailing = raw.match(TRAILING);
    // Keep a closing bracket that has its opening one inside the link
    if (trailing) {
      let cut = trailing[0];
      if (cut.startsWith(')') && raw.includes('(')) cut = cut.slice(1);
      raw = raw.slice(0, raw.length - cut.length);
    }
    if (!raw || /^(https?:\/\/|www\.)$/i.test(raw)) continue;
    if (start > last) parts.push({ kind: 'text', text: text.slice(last, start) });
    parts.push({ kind: 'link', text: raw, href: /^www\./i.test(raw) ? `https://${raw}` : raw });
    last = start + raw.length;
  }
  if (last < text.length) parts.push({ kind: 'text', text: text.slice(last) });
  return parts;
}

/** A link a message may open: http(s) only (never javascript: or data:) */
export function safeHttpUrl(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' || url.protocol === 'http:' ? url.toString() : undefined;
  } catch {
    return undefined;
  }
}
