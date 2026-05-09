import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

if (
  process.env.NODE_ENV === 'production' &&
  process.env.NEXT_PUBLIC_DEV_BYPASS === 'true'
) {
  throw new Error(
    'NEXT_PUBLIC_DEV_BYPASS=true is not allowed when NODE_ENV=production. ' +
      'Unset the variable before building for production.',
  )
}

const pkg = JSON.parse(
  readFileSync(new URL('./package.json', import.meta.url), 'utf8'),
)

let gitSha = process.env.GITHUB_SHA?.slice(0, 7) ?? ''
if (!gitSha) {
  try {
    gitSha = execSync('git rev-parse --short=7 HEAD', {
      stdio: ['ignore', 'pipe', 'ignore'],
    })
      .toString()
      .trim()
  } catch {
    gitSha = 'unknown'
  }
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  env: {
    NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL ?? '',
    NEXT_PUBLIC_APP_VERSION: pkg.version,
    NEXT_PUBLIC_GIT_SHA: gitSha,
    NEXT_PUBLIC_BUILD_DATE: new Date().toISOString(),
  },
  images: {
    remotePatterns: [],
  },
  experimental: {},
}

export default nextConfig
