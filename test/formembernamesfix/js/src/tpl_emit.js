// The template compiler: turns a parsed template tree into JavaScript source.
class TemplateCompiler {
  constructor(opts) {
    this.opts = opts || {};
    this.buffer = [];
  }

  compileBlock(node) {
    const visit = function blockVisitor(child) {
      return child.name;
    };
    return node.children.map(visit).join('');
  }

  compileSuper(node) {
    return 'parent(' + node.name + ')';
  }

  emitLine(text) {
    this.buffer.push(text + '\n');
  }

  flushOutput() {
    return this.buffer.join('');
  }
}

function compileTemplate(tree, opts) {
  return new TemplateCompiler(opts).compileBlock(tree);
}

function renderTemplate(src, ctx) {
  return compileTemplate(src, {}) + JSON.stringify(ctx);
}

module.exports = { TemplateCompiler, compileTemplate, renderTemplate };
