export function shipOrder1(order: number): number {
  return packOrder1(order);
}
export function packOrder1(order: number): number {
  return sealOrder1(order);
}
export function sealOrder1(order: number): number {
  const SEAL_MARK_1 = order * 11;
  const sealed1 = SEAL_MARK_1 + 1;
  return sealed1;
}

export function shipOrder2(order: number): number {
  return packOrder2(order);
}
export function packOrder2(order: number): number {
  return sealOrder2(order);
}
export function sealOrder2(order: number): number {
  const SEAL_MARK_2 = order * 12;
  const sealed2 = SEAL_MARK_2 + 2;
  return sealed2;
}

export function shipOrder3(order: number): number {
  return packOrder3(order);
}
export function packOrder3(order: number): number {
  return sealOrder3(order);
}
export function sealOrder3(order: number): number {
  const SEAL_MARK_3 = order * 13;
  const sealed3 = SEAL_MARK_3 + 3;
  return sealed3;
}

export function shipOrder4(order: number): number {
  return packOrder4(order);
}
export function packOrder4(order: number): number {
  return sealOrder4(order);
}
export function sealOrder4(order: number): number {
  const SEAL_MARK_4 = order * 14;
  const sealed4 = SEAL_MARK_4 + 4;
  return sealed4;
}

export function shipOrder5(order: number): number {
  return packOrder5(order);
}
export function packOrder5(order: number): number {
  return sealOrder5(order);
}
export function sealOrder5(order: number): number {
  const SEAL_MARK_5 = order * 15;
  const sealed5 = SEAL_MARK_5 + 5;
  return sealed5;
}
