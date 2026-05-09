import { cn } from '@/lib/utils'

type LogoSize = 'sm' | 'md' | 'lg'

const sizeClass: Record<LogoSize, string> = {
  sm: 'h-4 w-auto',
  md: 'h-6 w-auto',
  lg: 'h-8 w-auto',
}

interface LogoProps {
  size?: LogoSize
  color?: string
  className?: string
}

export function Logo({ size = 'md', color = '#FC273F', className }: LogoProps) {
  return (
    <svg
      viewBox="0 0 64 24"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label="Securitas"
      className={cn(sizeClass[size], className)}
    >
      <circle cx="8" cy="12" r="6" fill={color} />
      <circle cx="32" cy="12" r="6" fill={color} />
      <circle cx="56" cy="12" r="6" fill={color} />
    </svg>
  )
}
