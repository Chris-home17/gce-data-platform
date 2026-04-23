if (
  process.env.NODE_ENV === 'production' &&
  process.env.NEXT_PUBLIC_DEV_BYPASS === 'true'
) {
  throw new Error(
    'NEXT_PUBLIC_DEV_BYPASS=true is not allowed when NODE_ENV=production. ' +
      'Unset the variable before building for production.',
  )
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  env: {
    NEXT_PUBLIC_API_BASE_URL: process.env.NEXT_PUBLIC_API_BASE_URL ?? '',
  },
  images: {
    remotePatterns: [],
  },
  experimental: {},
}

export default nextConfig