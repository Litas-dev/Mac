export interface AuthUser {
  id: string
  email: string
}

export interface AuthResult {
  accessToken: string
  refreshToken: string
  user: AuthUser
}

export async function signUp(baseURL: string, email: string, password: string): Promise<AuthResult> {
  return post<AuthResult>(baseURL, '/v1/auth/signup', { email, password })
}

export async function signIn(baseURL: string, email: string, password: string): Promise<AuthResult> {
  return post<AuthResult>(baseURL, '/v1/auth/login', { email, password })
}

export async function refreshToken(baseURL: string, refreshToken: string): Promise<AuthResult> {
  return post<AuthResult>(baseURL, '/v1/auth/refresh', { refresh_token: refreshToken })
}

export async function signOut(baseURL: string, refreshToken: string): Promise<void> {
  await post(baseURL, '/v1/auth/logout', { refresh_token: refreshToken })
}

export async function getMe(baseURL: string, accessToken: string): Promise<AuthUser> {
  const url = normalizeBaseURL(baseURL) + '/v1/me'
  const res = await fetch(url, { method: 'GET', headers: { Authorization: `Bearer ${accessToken}` } })
  if (!res.ok) throw new Error(await readError(res))
  return (await res.json()) as AuthUser
}

async function post<T = unknown>(baseURL: string, path: string, body: unknown): Promise<T> {
  const url = normalizeBaseURL(baseURL) + path
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(await readError(res))
  return (await res.json()) as T
}

function normalizeBaseURL(baseURL: string): string {
  const trimmed = baseURL.trim()
  if (!trimmed) throw new Error('Missing backend URL')
  return trimmed.replace(/\/+$/, '')
}

async function readError(res: Response): Promise<string> {
  try {
    const json = (await res.json()) as any
    const msg = String(json?.error ?? '')
    if (msg) return msg
  } catch {
  }
  return `HTTP ${res.status}`
}

