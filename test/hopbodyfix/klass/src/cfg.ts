export function makePanelConfig(): number {
  const MAKE_CONFIG_MARK = 3;
  return MAKE_CONFIG_MARK * 7;
}
export class BaseRunner {
  launch(x: number): number {
    const BASE_LAUNCH_MARK = x + 100;
    return BASE_LAUNCH_MARK;
  }
}
export class OtherRunner {
  launch(x: number): number {
    const OTHER_LAUNCH_MARK = x + 200;
    return OTHER_LAUNCH_MARK;
  }
}
