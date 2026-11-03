// (#448) A wordless Koa-router-style registrar: 'express'/'fastify' appear nowhere in this file.
const Router = require('@koa/router');
const router = new Router();

router.post('/feedback', submitFeedback);

function submitFeedback(ctx) {
    ctx.body = 'thanks';
}

module.exports = router;
