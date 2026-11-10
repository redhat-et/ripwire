export class Panel {
  render(a: number): number { return a; }
  refresh(): number { return this.render(1) + new Panel().render(2); }
}
export function mount(p: Panel): number {
  const inner = () => p.refresh();
  return [1, 2].map((x) => p.render(x)).length + inner();
}
