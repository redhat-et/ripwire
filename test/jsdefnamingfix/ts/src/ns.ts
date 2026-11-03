export namespace Zone {
  export class Gate { open() { jdnNsHelper(); } }
}
namespace Zone2 { export class Door { close() { jdnNsHelper(); } } }
namespace Zone3 { export class Door { close() { jdnNsHelper(); } } }
function jdnNsHelper() {}
