export class Base {
  render(): string { return 'base'; }
}

export class Widget {
  render(): string { return 'widget'; }
}

export function makeBase(): any { return {}; }
