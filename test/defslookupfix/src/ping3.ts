export interface Pinger { ping(): number }
export class PingThree {
  ping(): number { return 3 }
}
