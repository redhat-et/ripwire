import { Widget } from 'ext-widgets'
import type { Single } from './single'
export class Shape {
  name(): string { return 'shape' }
}
export class Circle extends Shape {
  other: Shape
  ext: Widget
  one: Single
  constructor(o: Shape, w: Widget, s: Single) { super(); this.other = o; this.ext = w; this.one = s }
  area(): number { return 3 }
  render(): number { return 1 }
  run(): number { return 2 }
  viaBase(): number {
    return this.other.area()
  }
  viaExt(): number {
    return this.ext.render()
  }
  viaSingle(): number {
    return this.one.run()
  }
}
