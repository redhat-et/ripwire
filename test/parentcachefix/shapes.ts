export class Panel {
  render(a: number): number { return a; }
  refresh(): number {
    const twin = new Panel();
    return twin.render(this.render(1));
  }
}
export function mount(p: Panel): number {
  const inner = () => p.refresh();
  return [1, 2].map((x) => p.render(x)).length + inner();
}
