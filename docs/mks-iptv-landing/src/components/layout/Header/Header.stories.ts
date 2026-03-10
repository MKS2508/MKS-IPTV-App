import type { ComponentProps } from 'astro/types'
import HeaderStoryWrapper from './HeaderStoryWrapper.astro'

type HeaderProps = ComponentProps<typeof HeaderStoryWrapper>

export default {
  component: HeaderStoryWrapper,
  title: 'Layout/Header',
  parameters: {
    layout: 'padded',
  },
}

export const Default = {
  args: {
    currentPath: '/',
    showLogo: true,
    transparent: false,
  } satisfies HeaderProps,
}

export const Transparent = {
  args: {
    currentPath: '/',
    showLogo: true,
    transparent: true,
  } satisfies HeaderProps,
  parameters: {
    backgrounds: {
      default: 'dark',
    },
  },
}

export const ActiveInstallation = {
  args: {
    currentPath: '/installation',
    showLogo: true,
    transparent: false,
  } satisfies HeaderProps,
}

export const NoLogo = {
  args: {
    currentPath: '/',
    showLogo: false,
    transparent: false,
  } satisfies HeaderProps,
}