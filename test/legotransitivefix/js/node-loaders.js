const Loader = require('./loader');
class FileSystemLoader extends Loader {
  getSource(name) { return null; }
}
module.exports = { FileSystemLoader };
