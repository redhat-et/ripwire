export class Panel {
  render(a: number): number { return a; }
  refresh(): number {
    let total = 0;
    for (const twin of [new Panel()]) { total += twin.render(this.render(total)); }
    return total;
  }
}
export function mount(p: Panel): number {
  const inner = () => p.refresh();
  return [1, 2].map((x) => p.render(x)).length + inner();
}
