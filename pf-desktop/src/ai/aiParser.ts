import type { AppSettings } from '../domain/settings'
import type { AIParseResult } from './commands'
import { normalizeParsedCommand } from './commands'

export async function parseWithAI(input: string, settings: AppSettings, timeoutMs = 60_000): Promise<AIParseResult> {
  const provider = settings.aiProvider
  if (provider === 'local') {
    return parseWithOllama(input, settings, timeoutMs)
  }
  return parseWithExternal(input, settings, timeoutMs)
}

async function parseWithOllama(input: string, settings: AppSettings, timeoutMs: number): Promise<AIParseResult> {
  const base = (settings.aiBaseURL || 'http://localhost:11434').replace(/\/+$/, '')
  const endpoint = `${base}/api/generate`
  const model = settings.aiModel || 'qwen3.5:4b'
  const now = new Date()
  const prompt = buildSystemPrompt(settings, now) + '\n\nUser: ' + input

  const ctrl = new AbortController()
  const t = window.setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, prompt, stream: false, format: 'json' }),
      signal: ctrl.signal,
    })
    if (!res.ok) throw new Error(`Ollama error: ${res.status}`)
    const json = (await res.json()) as any
    const raw = String(json?.response ?? '')
    const parsed = safeExtractJSON(raw)
    return { raw, command: normalizeParsedCommand(parsed) }
  } finally {
    window.clearTimeout(t)
  }
}

async function parseWithExternal(input: string, settings: AppSettings, timeoutMs: number): Promise<AIParseResult> {
  const endpoint = settings.aiExternalEndpoint || 'https://api.groq.com/openai/v1/chat/completions'
  const apiKey = settings.aiExternalAPIKey
  if (!apiKey) throw new Error('Missing external API key.')

  const externalModel = (settings.aiModel && !settings.aiModel.includes(':')) 
    ? settings.aiModel 
    : 'llama-3.1-8b-instant'

  const now = new Date()
  const ctrl = new AbortController()
  const t = window.setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    const body = {
      model: externalModel,
      messages: [
        { role: 'system', content: buildSystemPrompt(settings, now) },
        { role: 'user', content: input },
      ],
      temperature: 0.2,
      response_format: { type: 'json_object' },
    }
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(body),
      signal: ctrl.signal,
    })
    if (!res.ok) throw new Error(`External AI error: ${res.status}`)
    const json = (await res.json()) as any
    const raw = String(json?.choices?.[0]?.message?.content ?? '')
    const parsed = safeExtractJSON(raw)
    return { raw, command: normalizeParsedCommand(parsed) }
  } finally {
    window.clearTimeout(t)
  }
}

function buildSystemPrompt(settings: AppSettings, now: Date): string {
  const code = settings.displayCurrencyCode || 'USD'
  const yyyy = now.getFullYear()
  const mm = String(now.getMonth() + 1).padStart(2, '0')
  const dd = String(now.getDate()).padStart(2, '0')
  const today = `${yyyy}-${mm}-${dd}`
  return [
    'You are an assistant for a personal finance app.',
    "Extract the transaction, bill, or income from the user's text.",
    'Respond with ONLY a raw JSON object and nothing else. No markdown, no explanations.',
    `Today is ${today}.`,
    'If the user gives a relative date like "in 4 days" or "tomorrow", convert it to YYYY-MM-DD using today.',
    'Valid categories: housing, utilities, subscriptions, insurance, taxes, transport, other.',
    'If you can infer a category, set it as payload.category. Otherwise omit it.',
    '',
    'Output format:',
    '{',
    '  "type": "createTransaction" | "createBill" | "createIncome",',
    '  "payload": { ... }',
    '}',
    '',
    'Examples:',
    'User: i sold my car for 5000 nok',
    '{"type":"createTransaction","payload":{"kind":"income","amount":5000,"currencyCode":"NOK","payee":"car sale","category":"transport"}}',
    '',
    'User: bus ticket 40 nok',
    '{"type":"createTransaction","payload":{"kind":"expense","amount":40,"currencyCode":"NOK","payee":"bus ticket","category":"transport"}}',
    '',
    'User: add bill . i payed 500 eur for new phone',
    '{"type":"createBill","payload":{"name":"new phone","amount":500,"currencyCode":"EUR","category":"other"}}',
    '',
    'User: just bought a coffee for 4.50',
    '{"type":"createTransaction","payload":{"kind":"expense","amount":4.5,"payee":"coffee","category":"other"}}',
    '',
    'User: got my 2000 paycheck',
    '{"type":"createTransaction","payload":{"kind":"income","amount":2000,"payee":"paycheck"}}',
    '',
    'User: schedule rent 1500 every month',
    '{"type":"createBill","payload":{"name":"rent","amount":1500,"category":"housing"}}',
    '',
    `If currency is not specified, use ${code}.`,
  ].join('\n')
}

function safeExtractJSON(raw: string): unknown {
  const trimmed = raw.trim()
  if (!trimmed) return null
  try {
    return JSON.parse(trimmed)
  } catch {
  }
  const start = trimmed.indexOf('{')
  const end = trimmed.lastIndexOf('}')
  if (start >= 0 && end > start) {
    const slice = trimmed.slice(start, end + 1)
    try {
      return JSON.parse(slice)
    } catch {
    }
  }
  return null
}
