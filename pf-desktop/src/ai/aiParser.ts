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
  const prompt = buildSystemPrompt(settings) + '\n\nUser: ' + input

  const ctrl = new AbortController()
  const t = window.setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    const res = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, prompt, stream: false }),
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

  const ctrl = new AbortController()
  const t = window.setTimeout(() => ctrl.abort(), timeoutMs)
  try {
    const body = {
      model: settings.aiModel || 'llama-3.1-8b-instant',
      messages: [
        { role: 'system', content: buildSystemPrompt(settings) },
        { role: 'user', content: input },
      ],
      temperature: 0.2,
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

function buildSystemPrompt(settings: AppSettings): string {
  const code = settings.displayCurrencyCode || 'USD'
  return [
    'You are an assistant for a personal finance app.',
    'Convert the user request into a single JSON command with no extra text.',
    'Output ONLY valid JSON.',
    'Schema:',
    '{ "type": "createTransaction"|"createBill"|"createIncome", "payload": { ... } }',
    'createTransaction payload: { "kind": "expense"|"income", "amount": number, "currencyCode"?: string, "payee"?: string, "notes"?: string }',
    'createBill payload: { "name": string, "amount": number, "currencyCode"?: string, "dueDate"?: "YYYY-MM-DD" }',
    'createIncome payload: { "name": string, "amount": number, "currencyCode"?: string, "nextPayDate"?: "YYYY-MM-DD" }',
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

