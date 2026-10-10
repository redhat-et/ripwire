import { Base, Widget, makeBase } from './shapes';

export class Panel extends Base {
  typed(): string {
    const base: Widget = new Widget();
    return base.render();
  }

  untyped(): string {
    const base = makeBase();
    return base.render();
  }

  realSuper(): string {
    return super.render();
  }
}
