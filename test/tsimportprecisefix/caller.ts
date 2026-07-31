import { helper } from './x';
import { widget } from './a/b';
import { idxfn } from './idx';
import React from 'react';

export function useHelper() { return helper(); }
export function useWidget() { return widget(); }
export function useIdx() { return idxfn(); }
export function useReact() { return createElement(); }
