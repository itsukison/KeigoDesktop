// Best-effort PII redaction for AI-improvement data. Runs server-side before
// any user text is persisted for improvement/dataset use.
//
// This is a HEURISTIC pass, not a guarantee. It strips the common,
// high-confidence identifiers (emails, URLs, phone numbers, postal codes,
// long numeric IDs, labeled secrets) and makes a conservative attempt at
// Japanese addresses and honorific-marked names. Free-form Japanese names and
// addresses cannot be reliably caught by regex — this layer sits BEHIND
// explicit opt-in consent, never in front of it, and is documented as
// best-effort in the privacy policy (§7.2).
//
// Order matters: structured tokens (email/URL) are removed before the numeric
// passes so their embedded digits are not re-matched as phone/ID.

const EMAIL = /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g;
const URL = /(?:https?:\/\/|www\.)[^\s　<>()「」]+/gi;

// パスワード: xxxx / 認証コード：1234 / 口座番号 1234567 etc. Redacts the value,
// keeps the label so the shape of the text survives.
const LABELED_SECRET =
  /(パスワード|ぱすわーど|暗証番号|認証コード|確認コード|口座番号|会員番号|password|passcode|verification code|one[- ]?time code)([\s:：=＝]*)([^\s　、。,.]+)/gi;

const POSTAL = /〒?\s*\d{3}[-−ー]\d{4}/g;
const CREDIT_CARD = /\b(?:\d[ -]?){4}(?:\d[ -]?){4}(?:\d[ -]?){4}\d{1,4}\b/g;

// Japanese phone numbers: +81 forms, 0AB(J) with separators, or contiguous.
const PHONE =
  /(?:\+81[-\s]?\d{1,4}[-\s]?\d{2,4}[-\s]?\d{3,4}|0\d{1,4}[-\s]?\d{1,4}[-\s]?\d{3,4}|0\d{9,10})/g;

// 8+ digit runs: My Number (12), account numbers, order/booking IDs.
const LONG_NUMBER = /\b\d{8,}\b/g;

// Best-effort Japanese street address: prefecture → city/ward/town → block.
const ADDRESS =
  /(?:東京都|北海道|(?:京都|大阪)府|[一-龥]{2,3}県)[^\s　、。,]{1,40}?(?:市|区|町|村)[^\s　、。,]{0,40}?(?:\d+[-−ー丁目番地号]\d*(?:[-−ー]\d+)?|\d+丁目|\d+番地?|\d+号)/g;

// Name followed by a Japanese honorific. Conservative: keeps the honorific,
// masks the preceding 1–4 name characters. May over- or under-match; that is
// the accepted trade-off for a regex-only pass.
const NAME_HONORIFIC = /[一-龥ぁ-んァ-ヶー]{1,4}(様|さん|君|殿|氏|先生)/g;

export function redactPII(input: string): string {
  if (!input) return input;
  let t = input;
  t = t.replace(EMAIL, "[EMAIL]");
  t = t.replace(URL, "[URL]");
  t = t.replace(LABELED_SECRET, (_m, label, sep) => `${label}${sep}[REDACTED]`);
  t = t.replace(POSTAL, "[POSTAL]");
  t = t.replace(CREDIT_CARD, "[CARD]");
  t = t.replace(PHONE, "[PHONE]");
  t = t.replace(LONG_NUMBER, "[NUMBER]");
  t = t.replace(ADDRESS, "[ADDRESS]");
  t = t.replace(NAME_HONORIFIC, "[NAME]$1");
  return t;
}
