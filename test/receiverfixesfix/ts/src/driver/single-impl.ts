import type { Single } from '../exec/single'
export class OnlySingle implements Single {
  run(): number { return 7 }
}
