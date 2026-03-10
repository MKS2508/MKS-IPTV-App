import type { ComponentProps } from 'astro/types';
import ScrollIndicator from './index.astro';

type ScrollIndicatorProps = ComponentProps<typeof ScrollIndicator>;

export default {
  component: ScrollIndicator,
  title: 'Animations/ScrollIndicator',
};

export const Default = {
  args: {
    text: 'Desplázate para explorar',
    showLine: true,
    showGlow: true,
  } satisfies ScrollIndicatorProps,
};

export const NoGlow = {
  args: {
    text: 'Desplázate para explorar',
    showLine: true,
    showGlow: false,
  } satisfies ScrollIndicatorProps,
};

export const NoLine = {
  args: {
    text: 'Desplázate para explorar',
    showLine: false,
    showGlow: true,
  } satisfies ScrollIndicatorProps,
};

export const Minimal = {
  args: {
    text: 'Scroll',
    showLine: false,
    showGlow: false,
  } satisfies ScrollIndicatorProps,
};

export const CustomText = {
  args: {
    text: 'Desliza hacia abajo',
    showLine: true,
    showGlow: true,
  } satisfies ScrollIndicatorProps,
};