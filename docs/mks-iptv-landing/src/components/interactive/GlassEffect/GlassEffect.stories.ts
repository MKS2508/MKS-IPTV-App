/**
 * @file Stories para el componente GlassEffect.
 * @author MKS
 */

import { GlassEffect } from './GlassEffect.tsx';

export default {
  component: GlassEffect,
}

export const Dock = {
  args: {
    preset: 'dock',
    draggable: true,
    initialPosition: { x: 50, y: 70 },
    children: 'Dock Glass Effect',
  },
};

export const Pill = {
  args: {
    preset: 'pill',
    draggable: true,
    initialPosition: { x: 30, y: 30 },
    children: 'Pill Shape',
  },
};

export const Bubble = {
  args: {
    preset: 'bubble',
    draggable: true,
    initialPosition: { x: 70, y: 40 },
    children: '•',
  },
};

export const Free = {
  args: {
    preset: 'free',
    draggable: true,
    initialPosition: { x: 80, y: 60 },
    children: '📱 Free Form',
  },
};

export const CustomConfig = {
  args: {
    preset: 'dock',
    config: {
      width: 200,
      height: 200,
      radius: 20,
      frost: 0.1,
      displace: 0.5,
      blur: 15,
      r: 20,
      g: 0,
      b: 0,
    },
    draggable: true,
    initialPosition: { x: 40, y: 50 },
    children: '🎨 Custom Config',
  },
};

export const StaticElement = {
  args: {
    preset: 'bubble',
    draggable: false,
    initialPosition: { x: 50, y: 50 },
    children: 'Static',
  },
};